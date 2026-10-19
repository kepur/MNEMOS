"""Unit test suite for Serafina 5.0 Persistent Agent Runtime (PAR)."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from serafina_runtime import (
    EventStore,
    ProgressLedger,
    TaskState,
    LoopDetector,
    LoopAnomaly,
    CircuitBreaker,
    BreakerLevel,
    ExecutionController,
    ToolEffectType,
    CheckpointManager,
    ContextCompiler,
    MemoryEngine,
    GPUFaultSupervisor,
    RuntimeHealthSupervisor,
    HealthState,
    RuntimeLayer,
    GPUFaultClassifier,
    FaultType,
    ModelCapabilityProfile,
    ModelCapabilityRegistry,
    MemoryPressureBudget,
    ComputeBudget,
    PersistenceBudget,
)


class SerafinaRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.event_store = EventStore(self.root / "test_events.db")
        self.ledger = ProgressLedger(
            task_id="test-task-001",
            project_id="test-proj",
            workspace_root=str(self.root),
            event_store=self.event_store,
        )

    def tearDown(self):
        self.tmp.cleanup()

    def test_01_two_dimensional_evidence_and_regression_risk(self):
        # Initial baseline: 5 tests, 2 passed, 3 failed
        eval1 = self.ledger.evaluate_step_progress(
            tool="bash",
            cmd="pytest",
            exit_code=1,
            output="3 failed, 2 passed",
            cwd=str(self.root),
            test_summary={"total": 5, "passed": 2, "failed": 3, "failed_names": ["test_a", "test_b", "test_c"]},
        )
        self.assertFalse(eval1["has_progress"])

        # Genuine progress: 1 failed resolved, passed increases to 3
        eval2 = self.ledger.evaluate_step_progress(
            tool="bash",
            cmd="pytest",
            exit_code=1,
            output="2 failed, 3 passed",
            cwd=str(self.root),
            test_summary={"total": 5, "passed": 3, "failed": 2, "failed_names": ["test_b", "test_c"]},
        )
        self.assertTrue(eval2["has_progress"])
        self.assertFalse(eval2["regression_risk"])

        # Test Deletion Fraud: 1 failed test removed from suite without passed increasing
        eval3 = self.ledger.evaluate_step_progress(
            tool="bash",
            cmd="pytest",
            exit_code=1,
            output="1 failed, 3 passed",
            cwd=str(self.root),
            test_summary={"total": 4, "passed": 3, "failed": 1, "failed_names": ["test_c"]},
        )
        # Should flag regression risk (suspected test deletion)
        self.assertTrue(eval3["regression_risk"])

    def test_02_prefix_cache_eligibility_vs_hit(self):
        compiler = ContextCompiler()
        messages, meta = compiler.compile_prompt(
            system_rules="Be helpful",
            project_core="Serafina 5.0 Core Specs",
            task_ledger_summary="Goal: LAN detection",
            retrieved_evidence=["arp_engine.py located at src/arp_engine.py"],
            recent_turns=[{"role": "user", "content": "hello"}],
        )
        self.assertIn("prefix_eligibility_key", meta)
        self.assertEqual(compiler.total_requests, 1)
        self.assertEqual(compiler.eligible_requests, 1)

        # Record cache hit
        compiler.record_actual_hit(True)
        metrics = compiler.get_cache_metrics()
        self.assertEqual(metrics["actual_hit_rate_pct"], 100.0)
        self.assertEqual(metrics["eligibility_rate_pct"], 100.0)

    def test_03_execution_controller_and_idempotency(self):
        controller = ExecutionController(self.event_store)

        # 1. Read-only classification
        read_check = controller.check_pre_execution("task-1", "cat", "first.txt", str(self.root))
        self.assertTrue(read_check["permitted"])
        self.assertEqual(read_check["effect_type"], ToolEffectType.READ_ONLY)

        # 2. Non-idempotent write executed once
        write_check1 = controller.check_pre_execution("task-1", "bash", "echo 'x' >> log.txt", str(self.root))
        self.assertTrue(write_check1["permitted"])
        self.assertEqual(write_check1["effect_type"], ToolEffectType.NON_IDEMPOTENT_WRITE)

        controller.record_post_execution(write_check1["idempotency_key"], exit_code=0, output_summary="appended")

        # 3. Duplicate execution of identical non-idempotent command is blocked
        write_check2 = controller.check_pre_execution("task-1", "bash", "echo 'x' >> log.txt", str(self.root))
        self.assertFalse(write_check2["permitted"])
        self.assertIn("Deduplication blocked", write_check2["reason"])

    def test_04_quiescent_checkpoint_and_state_verification(self):
        mgr = CheckpointManager(str(self.root), self.event_store)
        self.ledger.transition_to(TaskState.PLANNING)
        self.ledger.transition_to(TaskState.EXECUTING)
        cp = mgr.capture_checkpoint(self.ledger, step_number=5)
        self.assertEqual(self.ledger.state, TaskState.PAUSED)
        self.assertTrue(cp["workspace_quiescent"])

        # Recovery protocol: must transition through VERIFYING
        restore = mgr.restore_and_verify(self.ledger, cp["checkpoint_id"])
        self.assertTrue(restore["verified"])
        self.assertEqual(self.ledger.state, TaskState.EXECUTING)

    def test_05_loop_detector_8_types(self):
        detector = LoopDetector(window_size=12)

        # Type A: Exact Repeat 3 times
        r1 = detector.observe_turn("bash", "cat a.py", str(self.root), 0, "code", "looking", False)
        self.assertIsNone(r1)
        r2 = detector.observe_turn("bash", "cat a.py", str(self.root), 0, "code", "looking", False)
        self.assertIsNone(r2)
        r3 = detector.observe_turn("bash", "cat a.py", str(self.root), 0, "code", "looking", False)
        self.assertIsNotNone(r3)
        self.assertEqual(r3["type"], LoopAnomaly.TYPE_A)

        # Type E: Premature completion
        r_premature = detector.observe_turn("bash", "pytest", str(self.root), 1, "failed", "任务完成了！", False, all_criteria_met=False)
        self.assertIsNotNone(r_premature)
        self.assertEqual(r_premature["type"], LoopAnomaly.TYPE_E)

    def test_06_circuit_breaker_3_tiers_and_mutation(self):
        breaker = CircuitBreaker()

        # Step 1: L1 Warning
        res1 = breaker.evaluate_breaker(current_step=1, anomaly={"type": "EXACT_REPEAT"}, consecutive_no_progress=1)
        self.assertEqual(res1["level"], BreakerLevel.L1_WARN)

        # Step 2: L1 Warning again
        res2 = breaker.evaluate_breaker(current_step=2, anomaly={"type": "EXACT_REPEAT"}, consecutive_no_progress=2)
        self.assertEqual(res2["level"], BreakerLevel.L1_WARN)

        # Step 3: Escalates to L2 Strategy Mutation with Diagnostic Subtask
        res3 = breaker.evaluate_breaker(current_step=3, anomaly={"type": "EXACT_REPEAT"}, consecutive_no_progress=3)
        self.assertEqual(res3["level"], BreakerLevel.L2_MUTATE)
        self.assertIn("subtask", res3)
        self.assertIn("search_workspace", res3["subtask"]["allowed_actions"])

        # Step 6: Escalates to L3 Pause
        res4 = breaker.evaluate_breaker(current_step=6, anomaly=None, consecutive_no_progress=6)
        self.assertEqual(res4["level"], BreakerLevel.L3_PAUSE)

    def test_07_memory_engine_fts_and_blob_storage(self):
        engine = MemoryEngine(self.root / "mem.db", self.root / "blobs")

        # FTS5 Indexing & Search
        engine.index_fact("task-1", "proj-a", "architecture", "The gateway listens on port 8002", "spec.md")
        hits = engine.search_facts("proj-a", "port 8002")
        self.assertEqual(len(hits), 1)
        self.assertIn("8002", hits[0]["content"])

        # Blob Store
        large_output = "Line of output\n" * 500
        h, size = engine.store_blob(large_output)
        self.assertEqual(len(h), 64)
        restored = engine.read_blob(h)
        self.assertEqual(restored, large_output)

    def test_08_gpu_fault_supervisor_and_degradation(self):
        sup = GPUFaultSupervisor(cooldown_seconds=10.0)

        # 1. Fault classification
        metal_err = "kIOGPUCommandBufferCallbackErrorImpactingInteractivity"
        ft1 = GPUFaultClassifier.classify(metal_err)
        self.assertEqual(ft1, FaultType.METAL_GPU)

        oom_err = "Metal memory allocation failure: out of memory"
        ft2 = GPUFaultClassifier.classify(oom_err)
        self.assertEqual(ft2, FaultType.OOM_SWAP)

        # 2. First Metal fault degrades prefill chunk
        ft, action = sup.record_fault("qwen3-coder", "http://127.0.0.1:8000", metal_err)
        self.assertEqual(ft, FaultType.METAL_GPU)
        self.assertIn("degrade_prefill_chunk:1024", action)
        self.assertEqual(sup.prefill_mgr.get_chunk_size("qwen3-coder"), 1024)

        # 3. Second consecutive fault isolates model into cooldown
        ft_sec, action_sec = sup.record_fault("qwen3-coder", "http://127.0.0.1:8000", metal_err)
        self.assertIn("isolate_and_cooldown", action_sec)
        is_iso, rem = sup.is_isolated("qwen3-coder")
        self.assertTrue(is_iso)
        self.assertGreater(rem, 0.0)

        # 4. Successful inference clears consecutive counter
        sup.record_success("qwen3-coder")
        self.assertEqual(sup.consecutive_faults["qwen3-coder"], 0)

    def test_09_model_capability_profiles_and_registry(self):
        registry = ModelCapabilityRegistry()
        prof = ModelCapabilityProfile(
            model_id="qwen3-coder-30b",
            backend="mtplx",
            endpoint="http://127.0.0.1:8000",
        )
        prof.runtime.mtp = True
        prof.runtime.prefill_chunk = 2048
        registry.register(prof)

        retrieved = registry.get("qwen3-coder-30b")
        self.assertIsNotNone(retrieved)
        self.assertEqual(retrieved.backend, "mtplx")
        self.assertTrue(retrieved.runtime.mtp)

        # Serialization roundtrip
        d = prof.to_dict()
        prof_from_dict = ModelCapabilityProfile.from_dict(d)
        self.assertEqual(prof_from_dict.model_id, prof.model_id)
        self.assertEqual(prof_from_dict.runtime.mtp, prof.runtime.mtp)

    def test_10_task_state_reconciling(self):
        self.ledger.transition_to(TaskState.PLANNING)
        self.ledger.transition_to(TaskState.EXECUTING)
        self.ledger.git_head_commit = "commit-abc"
        self.ledger.git_dirty_files = ["main.swift"]

        # Interrupt happens -> PAUSED -> RECOVERING -> RECONCILING
        self.ledger.transition_to(TaskState.PAUSED)
        self.ledger.transition_to(TaskState.RECOVERING)
        self.ledger.transition_to(TaskState.RECONCILING, reason="Verifying interrupted tool execution")
        self.assertEqual(self.ledger.state, TaskState.RECONCILING)

        # Reconcile matching state
        ok, details = self.ledger.reconcile_state(
            current_git_head="commit-abc",
            current_dirty_files=["main.swift"],
            last_tool_call_completed=True,
        )
        self.assertTrue(ok)
        self.assertTrue(details["git_head_matched"])

        # Reconcile dirty mismatch
        ok_fail, details_fail = self.ledger.reconcile_state(
            current_git_head="commit-abc",
            current_dirty_files=["main.swift", "unexpected_dirty.py"],
            last_tool_call_completed=True,
        )
        self.assertFalse(ok_fail)
        self.assertFalse(details_fail["dirty_files_matched"])

    def test_11_resource_budgets(self):
        mem_budget = MemoryPressureBudget(critical_threshold_pct=95.0)
        state = mem_budget.get_memory_pressure_state()
        self.assertIn("total_gb", state)
        self.assertIn("pressure_level", state)
        self.assertIn("allow_context_expansion", state)

        compute_budget = ComputeBudget(max_concurrent_llm=1)
        self.assertTrue(compute_budget.acquire_inference_slot())
        self.assertFalse(compute_budget.acquire_inference_slot()) # Serialized!
        self.assertFalse(compute_budget.can_run_embedding())
        compute_budget.release_inference_slot()
        self.assertTrue(compute_budget.can_run_embedding())

    def test_12_runtime_health_supervisor_and_observability_layers(self):
        sup = RuntimeHealthSupervisor(cooldown_seconds=15.0)

        # Baseline: all 6 layers HEALTHY
        matrix = sup.get_health_matrix()
        self.assertEqual(matrix["overall"], HealthState.HEALTHY.value)
        self.assertEqual(len(matrix["layers"]), 6)
        self.assertEqual(matrix["layers"]["L1_SYSTEM"]["state"], HealthState.HEALTHY.value)
        self.assertEqual(matrix["layers"]["L2_METAL_GPU"]["state"], HealthState.HEALTHY.value)

        # Record verified progress and productive tokens
        sup.record_progress_step(verified=True)
        sup.record_progress_step(verified=True)
        sup.record_success("model-a", prompt_tokens=1000, completion_tokens=200)

        # Productivity metrics check
        eat = sup.get_eat_per_min()
        self.assertGreater(eat, 0.0)
        self.assertEqual(sup.get_wcr_pct(), 0.0)

        # Simulate 1st Metal Fault -> Degraded
        ft, action = sup.record_fault("model-a", "http://127.0.0.1:7777", "kIOGPUCommandBufferCallbackErrorImpactingInteractivity")
        self.assertEqual(ft, FaultType.METAL_GPU)
        self.assertEqual(sup.layer_states[RuntimeLayer.L2_METAL_GPU], HealthState.DEGRADED)
        self.assertEqual(sup.get_overall_health(), HealthState.DEGRADED)

        # Record wasted tokens
        sup.record_wasted("model-a", prompt_tokens=1000, completion_tokens=0, reason="Metal Watchdog Abort")
        wcr = sup.get_wcr_pct()
        self.assertGreater(wcr, 0.0)
        self.assertLessEqual(wcr, 100.0)

        # Simulate 2nd Consecutive Metal Fault -> Quarantine & ARP Circuit Breaker
        ft2, action2 = sup.record_fault("model-a", "http://127.0.0.1:7777", "command buffer failed: Impacting Interactivity")
        self.assertIn("isolate_and_cooldown", action2)
        self.assertEqual(sup.layer_states[RuntimeLayer.L2_METAL_GPU], HealthState.QUARANTINED)
        self.assertEqual(sup.layer_states[RuntimeLayer.L3_INFERENCE_BACKEND], HealthState.QUARANTINED)
        self.assertEqual(sup.get_overall_health(), HealthState.QUARANTINED)

        # Verify isolation query
        is_iso, rem = sup.is_isolated("model-a")
        self.assertTrue(is_iso)
        self.assertGreater(rem, 0.0)

        # Matrix reports quarantine details
        matrix_iso = sup.get_health_matrix()
        self.assertEqual(matrix_iso["overall"], HealthState.QUARANTINED.value)
        self.assertEqual(len(matrix_iso["quarantined_models"]), 1)
        self.assertEqual(matrix_iso["quarantined_models"][0]["model"], "model-a")


if __name__ == "__main__":
    unittest.main()
