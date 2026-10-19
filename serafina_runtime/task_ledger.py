"""Progress Ledger Engine for Serafina 5.0.

Implements the two-dimensional evidence evaluation model:
  Progress = Observable State Change + Acceptance Criteria Improvement + Evidence Provenance - Regression Risk

Does NOT blindly trust compiler exit codes or Git diffs.
"""
from __future__ import annotations

import dataclasses
import hashlib
import json
import time
from typing import Any, Dict, List, Optional, Set
from .event_store import EventStore


class TaskState:
    CREATED = "CREATED"
    PLANNING = "PLANNING"
    EXECUTING = "EXECUTING"
    VERIFYING = "VERIFYING"
    COMPLETED = "COMPLETED"
    DIAGNOSING = "DIAGNOSING"
    PAUSED = "PAUSED"
    CHECKPOINTING = "CHECKPOINTING"
    RECOVERING = "RECOVERING"
    RECONCILING = "RECONCILING"


@dataclasses.dataclass
class AcceptanceCriterion:
    id: str
    description: str
    verified: bool = False
    verification_type: str = "test"  # 'test', 'diff', 'manual', 'lint'
    verification_evidence: str = ""
    verified_at: Optional[float] = None

    def to_dict(self) -> Dict[str, Any]:
        return dataclasses.asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> AcceptanceCriterion:
        return cls(**data)


@dataclasses.dataclass
class EvidenceItem:
    source_type: str  # 'git_diff', 'compiler_exit', 'test_run', 'search_path', 'agent_claim'
    tool_name: str
    exit_code: Optional[int]
    observational_authenticity: float  # 0.0 - 1.0 (How real is the observation)
    completion_power: float  # 0.0 - 1.0 (How much does it prove the goal)
    summary: str
    detail_hash: str
    timestamp: float = dataclasses.field(default_factory=time.time)

    def to_dict(self) -> Dict[str, Any]:
        return dataclasses.asdict(self)


class ProgressLedger:
    """Manages the lifecycle, evidence evaluation, and state transitions of a Task."""

    def __init__(
        self,
        task_id: str,
        project_id: str,
        workspace_root: str,
        event_store: Optional[EventStore] = None,
        max_steps: int = 40,
        token_budget: int = 64000,
    ):
        self.task_id = task_id
        self.project_id = project_id
        self.workspace_root = workspace_root
        self.event_store = event_store or EventStore()
        self.state = TaskState.CREATED
        self.phase = "init"

        self.budget = {
            "max_steps": max_steps,
            "current_step": 0,
            "max_repeated_attempts": 3,
            "token_budget": token_budget,
            "tokens_used": 0,
            "consecutive_no_progress": 0,
        }

        self.acceptance_criteria: List[AcceptanceCriterion] = []
        self.blockers: List[Dict[str, Any]] = []
        self.evidence_log: List[EvidenceItem] = []

        # Tracking state metrics
        self.git_head_commit = ""
        self.git_dirty_files: Set[str] = set()
        self.git_deleted_files: Set[str] = set()
        self.test_stats = {"total": 0, "passed": 0, "failed": 0, "skipped": 0}
        self.prior_failed_tests: Set[str] = set()

        self._load_or_save()

    def _load_or_save(self) -> None:
        saved = self.event_store.load_ledger(self.task_id)
        if saved:
            self.state = saved["state"]
            self.phase = saved["phase"]
            self.budget = saved["budget"]
            self.acceptance_criteria = [AcceptanceCriterion.from_dict(c) for c in saved["acceptance"]]
            progress = saved["progress"]
            self.blockers = progress.get("blockers", [])
            self.git_head_commit = progress.get("git_head_commit", "")
            self.git_dirty_files = set(progress.get("git_dirty_files", []))
            self.git_deleted_files = set(progress.get("git_deleted_files", []))
            self.test_stats = progress.get("test_stats", self.test_stats)
            self.prior_failed_tests = set(progress.get("prior_failed_tests", []))
            self.evidence_log = [EvidenceItem(**e) for e in saved.get("evidence", [])]
        else:
            self._flush()

    def _flush(self) -> None:
        progress = {
            "blockers": self.blockers,
            "git_head_commit": self.git_head_commit,
            "git_dirty_files": list(self.git_dirty_files),
            "git_deleted_files": list(self.git_deleted_files),
            "test_stats": self.test_stats,
            "prior_failed_tests": list(self.prior_failed_tests),
        }
        self.event_store.save_ledger(
            task_id=self.task_id,
            project_id=self.project_id,
            workspace_root=self.workspace_root,
            state=self.state,
            phase=self.phase,
            budget=self.budget,
            acceptance=[c.to_dict() for c in self.acceptance_criteria],
            progress=progress,
            evidence=[e.to_dict() for e in self.evidence_log],
        )

    def set_criteria(self, criteria: List[Dict[str, Any]]) -> None:
        self.acceptance_criteria = [
            AcceptanceCriterion(
                id=c.get("id", f"ac_{i+1}"),
                description=c.get("desc", c.get("description", "")),
                verification_type=c.get("type", "test"),
            )
            for i, c in enumerate(criteria)
        ]
        self._flush()

    def transition_to(self, new_state: str, reason: str = "") -> bool:
        """Validates state machine transitions according to PAR state diagram."""
        valid_transitions = {
            TaskState.CREATED: [TaskState.PLANNING],
            TaskState.PLANNING: [TaskState.EXECUTING, TaskState.PAUSED],
            TaskState.EXECUTING: [TaskState.VERIFYING, TaskState.DIAGNOSING, TaskState.CHECKPOINTING, TaskState.PAUSED],
            TaskState.VERIFYING: [TaskState.COMPLETED, TaskState.EXECUTING, TaskState.DIAGNOSING, TaskState.CHECKPOINTING],
            TaskState.DIAGNOSING: [TaskState.EXECUTING, TaskState.CHECKPOINTING, TaskState.PAUSED],
            TaskState.CHECKPOINTING: [TaskState.PAUSED, TaskState.RECOVERING],
            TaskState.PAUSED: [TaskState.RECOVERING],
            TaskState.RECOVERING: [TaskState.RECONCILING, TaskState.VERIFYING, TaskState.EXECUTING],
            TaskState.RECONCILING: [TaskState.VERIFYING, TaskState.EXECUTING, TaskState.PAUSED, TaskState.DIAGNOSING],
            TaskState.COMPLETED: [],
        }

        allowed = valid_transitions.get(self.state, [])
        if new_state not in allowed:
            # Prevent illegal jumps (e.g., RECOVERING directly to COMPLETED without verification)
            return False

        old_state = self.state
        self.state = new_state
        self._flush()
        self.event_store.record_event(
            task_id=self.task_id,
            session_id=self.task_id,
            event_type="state_transition",
            payload={"old_state": old_state, "new_state": new_state, "reason": reason},
            source="supervisor",
        )
        return True

    def reconcile_state(
        self,
        current_git_head: str,
        current_dirty_files: List[str],
        last_tool_call_completed: bool = True,
    ) -> Tuple[bool, Dict[str, Any]]:
        """Reconciles workspace ground truth during RECONCILING phase."""
        git_matched = (not self.git_head_commit) or (self.git_head_commit == current_git_head)
        dirty_matched = set(self.git_dirty_files) == set(current_dirty_files)
        is_consistent = git_matched and dirty_matched and last_tool_call_completed
        details = {
            "git_head_matched": git_matched,
            "dirty_files_matched": dirty_matched,
            "last_tool_completed": last_tool_call_completed,
            "is_consistent": is_consistent,
        }
        return is_consistent, details

    def evaluate_step_progress(
        self,
        tool: str,
        cmd: str,
        exit_code: Optional[int],
        output: str,
        cwd: str,
        git_diff_summary: Optional[Dict[str, Any]] = None,
        test_summary: Optional[Dict[str, Any]] = None,
        agent_claim: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Calculates:
        Progress = Observable State Change + Acceptance Improvement + Evidence Provenance - Regression Risk
        """
        self.budget["current_step"] += 1
        observable_change = 0.0
        acceptance_improvement = 0.0
        evidence_provenance = 0.0
        regression_risk = 0.0
        reasons = []

        # 1. Observable State Change (Git & File Changes)
        if git_diff_summary:
            added = git_diff_summary.get("lines_added", 0)
            deleted = git_diff_summary.get("lines_deleted", 0)
            files = git_diff_summary.get("files_changed", [])
            for f in files:
                self.git_dirty_files.add(f)
            if added > 0 or deleted > 0:
                observable_change += 0.4
                reasons.append(f"files modified ({len(files)} files, +{added}/-{deleted})")

        # Check for path discovery / search convergence
        if exit_code == 0 and ("grep" in cmd or "find" in cmd or "ls" in cmd):
            if output.strip() and len(output.splitlines()) < 50:
                observable_change += 0.3
                reasons.append("targeted path discovery succeeded")

        # 2. Acceptance Criteria & Test Results
        if test_summary:
            cur_passed = test_summary.get("passed", 0)
            cur_failed = test_summary.get("failed", 0)
            cur_failed_names = set(test_summary.get("failed_names", []))

            # Did tests improve?
            if cur_passed > self.test_stats["passed"] and cur_failed <= self.test_stats["failed"]:
                acceptance_improvement += 0.8
                reasons.append(f"tests improved (passed {self.test_stats['passed']} -> {cur_passed})")
            elif cur_failed < self.test_stats["failed"] and cur_passed >= self.test_stats["passed"]:
                acceptance_improvement += 0.7
                reasons.append(f"failures resolved ({self.test_stats['failed']} -> {cur_failed})")

            # 3. Regression Risk Check
            # Check A: Did previously failing tests vanish without passing count increasing? (Test deletion fraud)
            vanished_failures = self.prior_failed_tests - cur_failed_names
            if vanished_failures and cur_passed <= self.test_stats["passed"]:
                regression_risk += 0.9
                reasons.append(f"suspected test deletion: {len(vanished_failures)} tests missing")

            # Check B: Did test failures increase?
            if cur_failed > self.test_stats["failed"]:
                regression_risk += 0.5
                reasons.append(f"test failures increased ({self.test_stats['failed']} -> {cur_failed})")

            self.test_stats = {
                "total": test_summary.get("total", 0),
                "passed": cur_passed,
                "failed": cur_failed,
                "skipped": test_summary.get("skipped", 0),
            }
            self.prior_failed_tests = cur_failed_names

        # 4. Evidence Provenance
        if exit_code == 0 and ("test" in cmd or "pytest" in cmd or "unittest" in cmd):
            evidence_provenance += 0.8
        elif exit_code == 0:
            evidence_provenance += 0.3
        elif exit_code != 0:
            evidence_provenance += 0.1  # Failed command provides investigative falsification, but no positive progress

        # Agent claim weighting (low weight without machine evidence)
        if agent_claim and ("fixed" in agent_claim.lower() or "completed" in agent_claim.lower()):
            if acceptance_improvement <= 0 and observable_change <= 0:
                reasons.append("agent claims fix without machine evidence")
                # Does not grant positive progress

        # Net progress score
        net_score = (observable_change * 0.35) + (acceptance_improvement * 0.5) + (evidence_provenance * 0.15) - regression_risk
        has_progress = net_score > 0.25

        if has_progress:
            self.budget["consecutive_no_progress"] = 0
        else:
            self.budget["consecutive_no_progress"] += 1

        evidence_item = EvidenceItem(
            source_type="test_run" if test_summary else ("git_diff" if git_diff_summary else "command"),
            tool_name=tool,
            exit_code=exit_code,
            observational_authenticity=0.9 if exit_code is not None else 0.4,
            completion_power=0.9 if acceptance_improvement > 0.5 else 0.3,
            summary="; ".join(reasons) if reasons else ("command run" if exit_code == 0 else "command failed"),
            detail_hash=hashlib.sha256(f"{cmd}:{exit_code}:{output[:500]}".encode()).hexdigest()[:16],
        )
        self.evidence_log.append(evidence_item)
        if len(self.evidence_log) > 60:
            self.evidence_log.pop(0)

        self._flush()
        return {
            "has_progress": has_progress,
            "net_score": round(net_score, 3),
            "reasons": reasons,
            "consecutive_no_progress": self.budget["consecutive_no_progress"],
            "regression_risk": regression_risk > 0.4,
        }

    def verify_all_completed(self) -> bool:
        """Returns True only if machine criteria have passed and tests exit 0."""
        if not self.acceptance_criteria:
            return self.test_stats["failed"] == 0 and self.test_stats["passed"] > 0
        return all(c.verified for c in self.acceptance_criteria) and self.test_stats["failed"] == 0
