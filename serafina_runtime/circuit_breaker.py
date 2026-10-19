"""3-Tier Circuit Breaker and Diagnostic Strategy Mutation for Serafina 5.0.

Levels:
  Level 1: Advisory Nudge (Informs the model of repeated actions and lack of progress)
  Level 2: Strategy Mutation (Blocks exact repeated failure and issues a diagnostic subtask)
  Level 3: Checkpoint & Pause (Quiesces workspace and requests human intervention)
"""
from __future__ import annotations

import dataclasses
import time
from typing import Any, Dict, List, Optional


class BreakerLevel:
    NORMAL = 0
    L1_WARN = 1
    L2_MUTATE = 2
    L3_PAUSE = 3


@dataclasses.dataclass
class DiagnosticSubtask:
    reason: str
    forbidden_pattern: str
    required_outcome: str
    allowed_actions: List[str]
    max_attempts: int = 4
    attempts_made: int = 0
    expires_at_step: int = 0
    on_failure: str = "pause_with_checkpoint"

    def to_dict(self) -> Dict[str, Any]:
        return dataclasses.asdict(self)

    def is_expired(self, current_step: int) -> bool:
        return current_step >= self.expires_at_step


class CircuitBreaker:
    def __init__(self, max_l1_warnings: int = 2, max_l2_mutations: int = 2):
        self.max_l1 = max_l1_warnings
        self.max_l2 = max_l2_mutations

        self.current_level = BreakerLevel.NORMAL
        self.l1_count = 0
        self.l2_count = 0

        # Scoped expiring blocklist: {fingerprint: (expiry_step, reason)}
        self.blocklist: Dict[str, Tuple[int, str]] = {}
        self.active_subtask: Optional[DiagnosticSubtask] = None

    def evaluate_breaker(
        self,
        current_step: int,
        anomaly: Optional[Dict[str, Any]],
        consecutive_no_progress: int,
    ) -> Dict[str, Any]:
        """Determines breaker state and action required."""
        # Clean expired blocklist items
        self.blocklist = {k: v for k, v in self.blocklist.items() if v[0] > current_step}
        if self.active_subtask and self.active_subtask.is_expired(current_step):
            self.active_subtask = None

        if not anomaly and consecutive_no_progress < 2:
            self.current_level = BreakerLevel.NORMAL
            return {"level": BreakerLevel.NORMAL, "action": "CONTINUE"}

        # Escalate based on consecutive failures & anomaly presence
        if consecutive_no_progress >= 6 or self.l2_count >= self.max_l2:
            self.current_level = BreakerLevel.L3_PAUSE
            return {
                "level": BreakerLevel.L3_PAUSE,
                "action": "PAUSE_AND_CHECKPOINT",
                "reason": "Exhausted budget without progress or exceeded strategy mutation attempts",
            }

        if consecutive_no_progress >= 3 or (anomaly and self.l1_count >= self.max_l1):
            self.current_level = BreakerLevel.L2_MUTATE
            self.l2_count += 1
            reason = anomaly.get("type", "NO_PROGRESS") if anomaly else "NO_PROGRESS"
            subtask = self._generate_diagnostic_subtask(reason, current_step)
            self.active_subtask = subtask
            return {
                "level": BreakerLevel.L2_MUTATE,
                "action": "MUTATE_STRATEGY",
                "subtask": subtask.to_dict(),
                "reason": reason,
            }

        # Level 1 Advisory
        self.current_level = BreakerLevel.L1_WARN
        self.l1_count += 1
        return {
            "level": BreakerLevel.L1_WARN,
            "action": "WARN_ADVISORY",
            "message": anomaly.get("message", "Repeated attempts without progress observed.") if anomaly else "Progress stalled.",
        }

    def _generate_diagnostic_subtask(self, reason: str, current_step: int) -> DiagnosticSubtask:
        """Creates an exploratory diagnostic subtask with explicit allowed actions rather than forcing a single command."""
        allowed_actions = ["locate_files", "read_test_failure", "inspect_manifest", "query_git_diff"]
        required_outcome = "verify_prerequisites"
        if "PATH_NOT_FOUND" in reason or "EXACT_REPEAT" in reason:
            allowed_actions = ["search_workspace", "inspect_directory_tree", "check_entrypoint_path"]
            required_outcome = "resolve_correct_path"
        elif "ERROR_SIGNATURE" in reason:
            allowed_actions = ["read_traceback_source", "check_dependencies", "isolate_failing_function"]
            required_outcome = "identify_root_cause"

        return DiagnosticSubtask(
            reason=reason,
            forbidden_pattern="repeat_exact_last_command",
            required_outcome=required_outcome,
            allowed_actions=allowed_actions,
            max_attempts=4,
            expires_at_step=current_step + 4,
        )

    def is_action_blocked(self, fp: str, current_step: int) -> Optional[str]:
        if fp in self.blocklist:
            expiry, reason = self.blocklist[fp]
            if current_step < expiry:
                return f"Action blocked until step {expiry}: {reason}"
        return None

    def add_to_blocklist(self, fp: str, current_step: int, duration_steps: int = 4, reason: str = "") -> None:
        self.blocklist[fp] = (current_step + duration_steps, reason)

    def reset_on_progress(self) -> None:
        """Called when verifiable machine progress is detected."""
        self.current_level = BreakerLevel.NORMAL
        self.l1_count = 0
        self.l2_count = 0
        self.active_subtask = None
        self.blocklist.clear()
