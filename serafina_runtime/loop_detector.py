"""8-Type Loop Detector for Serafina 5.0.

Detects:
  Type A: Exact call repeat (command & normalized args)
  Type B: Periodic cycle (A -> B -> C -> A -> B -> C)
  Type C: Error signature repeat
  Type D: False progress (claims progress without diff/test changes)
  Type E: Premature completion (claims done without passing criteria)
  Type F: Context amnesia cycle (re-investigating facts already established)
  Type G: Tool wait/polling cycle (polling same command with identical output)
  Type H: Model output regurgitation (repeating identical planning text)
"""
from __future__ import annotations

import collections
import hashlib
import json
import re
from typing import Any, Deque, Dict, List, Optional, Tuple


class LoopAnomaly:
    TYPE_A = "EXACT_REPEAT"
    TYPE_B = "PERIODIC_CYCLE"
    TYPE_C = "ERROR_SIGNATURE_REPEAT"
    TYPE_D = "FALSE_PROGRESS"
    TYPE_E = "PREMATURE_COMPLETION"
    TYPE_F = "CONTEXT_AMNESIA"
    TYPE_G = "POLLING_CYCLE"
    TYPE_H = "OUTPUT_REGURGITATION"


class LoopDetector:
    def __init__(self, window_size: int = 24):
        self.window_size = window_size
        self.history: Deque[Dict[str, Any]] = collections.deque(maxlen=window_size)
        self.output_hashes: Deque[str] = collections.deque(maxlen=10)
        self.error_counts: Dict[str, int] = collections.defaultdict(int)

    @staticmethod
    def normalize_command(cmd: str) -> str:
        """Strip variable flags or whitespace for canonical fingerprinting."""
        cleaned = re.sub(r"\s+", " ", cmd.strip())
        # Normalize relative path prefixes
        cleaned = re.sub(r"\./", "", cleaned)
        return cleaned

    def fingerprint_call(self, tool: str, args: Any, cwd: str = "") -> str:
        cmd_str = ""
        if isinstance(args, dict):
            cmd_str = args.get("cmd") or args.get("command") or json.dumps(args, sort_keys=True)
        elif isinstance(args, str):
            cmd_str = args
        norm = self.normalize_command(str(cmd_str))
        payload = f"{tool}:{cwd}:{norm}"
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]

    def observe_turn(
        self,
        tool: str,
        args: Any,
        cwd: str,
        exit_code: Optional[int],
        output: str,
        assistant_text: str,
        has_progress: bool,
        known_facts: Optional[List[str]] = None,
        all_criteria_met: bool = False,
    ) -> Optional[Dict[str, Any]]:
        """Analyzes recent interactions and detects any of the 8 loop anomalies."""
        fp = self.fingerprint_call(tool, args, cwd)
        out_hash = hashlib.sha256(output[:1000].encode("utf-8")).hexdigest()[:16]
        text_hash = hashlib.sha256(assistant_text[:1000].encode("utf-8")).hexdigest()[:16] if assistant_text else ""

        # Extract error signature if command failed
        error_sig = ""
        if exit_code not in (None, 0):
            # Take last 2 lines of stderr/output as error signature
            lines = [l.strip() for l in output.splitlines() if l.strip()]
            error_sig = " ".join(lines[-2:]) if lines else f"exit_{exit_code}"
            # Truncate and clean error signature
            error_sig = re.sub(r"0x[0-9a-fA-F]+", "0xADDR", error_sig)[:120]
            self.error_counts[error_sig] += 1

        record = {
            "tool": tool,
            "args": args,
            "fp": fp,
            "cwd": cwd,
            "exit_code": exit_code,
            "out_hash": out_hash,
            "text_hash": text_hash,
            "has_progress": has_progress,
            "error_sig": error_sig,
            "assistant_text": assistant_text,
        }
        self.history.append(record)
        if text_hash:
            self.output_hashes.append(text_hash)

        # 1. Type A: Exact Call Repeat (3+ times without progress)
        recent_fps = [r["fp"] for r in list(self.history)[-4:] if not r["has_progress"]]
        if len(recent_fps) >= 3 and recent_fps[-1] == recent_fps[-2] == recent_fps[-3]:
            return {
                "type": LoopAnomaly.TYPE_A,
                "severity": "high",
                "message": f"Exact tool call repeated 3 times without progress: {tool} {args}",
                "pattern": [r["fp"] for r in self.history][-3:],
            }

        # 2. Type B: Periodic Cycle (A -> B -> A -> B or A -> B -> C -> A -> B -> C)
        all_fps = [r["fp"] for r in self.history]
        if len(all_fps) >= 6:
            # Check period 2: [A, B, A, B]
            if all_fps[-4:-2] == all_fps[-2:]:
                return {
                    "type": LoopAnomaly.TYPE_B,
                    "severity": "high",
                    "message": "Periodic 2-step tool oscillation detected",
                    "pattern": all_fps[-4:],
                }
            # Check period 3: [A, B, C, A, B, C]
            if len(all_fps) >= 6 and all_fps[-6:-3] == all_fps[-3:]:
                return {
                    "type": LoopAnomaly.TYPE_B,
                    "severity": "high",
                    "message": "Periodic 3-step tool oscillation detected",
                    "pattern": all_fps[-6:],
                }

        # 3. Type C: Error Signature Repeat
        if error_sig and self.error_counts[error_sig] >= 3:
            return {
                "type": LoopAnomaly.TYPE_C,
                "severity": "high",
                "message": f"Identical failure signature encountered {self.error_counts[error_sig]} times: {error_sig}",
                "error_sig": error_sig,
            }

        # 4. Type D: False Progress (Agent claims fix while progress is False)
        claim_keywords = ["已完成修复", "fixed the issue", "i have resolved", "successfully implemented", "修复完成"]
        if any(k in assistant_text.lower() for k in claim_keywords) and not has_progress:
            # Check if this occurred in the previous turn as well
            prev_claims = [r for r in list(self.history)[-3:] if any(k in r["assistant_text"].lower() for k in claim_keywords) and not r["has_progress"]]
            if len(prev_claims) >= 2:
                return {
                    "type": LoopAnomaly.TYPE_D,
                    "severity": "medium",
                    "message": "Agent repeatedly claims progress without verifiable state changes",
                }

        # 5. Type E: Premature Completion
        if ("任务完成" in assistant_text or "task completed" in assistant_text.lower()) and not all_criteria_met:
            return {
                "type": LoopAnomaly.TYPE_E,
                "severity": "high",
                "message": "Agent declared task complete but acceptance criteria remain unverified",
            }

        # 6. Type F: Context Amnesia Cycle (Re-investigating already recorded facts)
        if known_facts and tool in ("bash", "read_file", "cat"):
            cmd_str = str(args)
            for fact in known_facts:
                if fact in cmd_str and not has_progress:
                    return {
                        "type": LoopAnomaly.TYPE_F,
                        "severity": "medium",
                        "message": f"Agent is re-querying established fact: {fact}",
                    }

        # 7. Type G: Polling Cycle (Identical command & identical output 4+ times)
        recent_polls = list(self.history)[-4:]
        if len(recent_polls) == 4 and len(set(r["fp"] for r in recent_polls)) == 1 and len(set(r["out_hash"] for r in recent_polls)) == 1:
            return {
                "type": LoopAnomaly.TYPE_G,
                "severity": "medium",
                "message": "Unchanged polling loop detected (same output across 4 iterations)",
            }

        # 8. Type H: Output Regurgitation (Repeating identical explanation/plan text)
        if len(self.output_hashes) >= 3 and list(self.output_hashes)[-1] == list(self.output_hashes)[-2]:
            return {
                "type": LoopAnomaly.TYPE_H,
                "severity": "medium",
                "message": "Model generated identical response text consecutively",
            }

        return None


class ControlState:
    NORMAL = "NORMAL"
    WARN = "WARN"
    RESTRICT = "RESTRICT"
    PAUSE = "PAUSE"


class RepetitionDetector:
    """Detects exact duplicate commands and periodic oscillation cycles."""

    def __init__(self, detector: LoopDetector):
        self._d = detector

    def check(self) -> Optional[Dict[str, Any]]:
        if not self._d.history:
            return None
        last = self._d.history[-1]
        return self._d.evaluate(
            tool=last.get("tool", ""),
            args=last.get("args", {}),
            cwd=last.get("cwd", ""),
            output=last.get("output", ""),
            assistant_text=last.get("assistant_text", ""),
        )


class ProgressEvaluator:
    """Evaluates whether recent tool actions produced observable state progress."""

    def __init__(self, detector: LoopDetector):
        self._d = detector

    def check(self, has_progress: bool, assistant_text: str = "") -> Optional[Dict[str, Any]]:
        if not self._d.history:
            return None
        last = self._d.history[-1]
        return self._d.evaluate(
            tool=last.get("tool", ""),
            args=last.get("args", {}),
            cwd=last.get("cwd", ""),
            output=last.get("output", ""),
            assistant_text=assistant_text or last.get("assistant_text", ""),
            has_progress=has_progress,
        )


class SemanticLoopDetector:
    """Detects context amnesia, polling loops, and identical output regurgitation."""

    def __init__(self, detector: LoopDetector):
        self._d = detector

    def check(self, known_facts: Optional[List[str]] = None) -> Optional[Dict[str, Any]]:
        if not self._d.history:
            return None
        last = self._d.history[-1]
        return self._d.evaluate(
            tool=last.get("tool", ""),
            args=last.get("args", {}),
            cwd=last.get("cwd", ""),
            output=last.get("output", ""),
            assistant_text=last.get("assistant_text", ""),
            known_facts=known_facts,
        )


class CompletionVerifier:
    """Strictly checks whether agent claim of completion is backed by verified criteria."""

    @staticmethod
    def verify(assistant_text: str, all_criteria_met: bool) -> Tuple[bool, Optional[str]]:
        claims = ["任务完成", "task completed", "successfully finished", "all done"]
        is_claiming = any(c in assistant_text.lower() for c in claims)
        if is_claiming and not all_criteria_met:
            return False, "Agent claimed task completion but acceptance criteria remain unverified"
        return True, None

