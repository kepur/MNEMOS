"""Execution Controller for Serafina 5.0.

Provides tool permissions, timeout enforcement, process group tracking,
and At-Least-Once / Idempotent Side-Effect Protection.
"""
from __future__ import annotations

import hashlib
import json
import re
import time
from typing import Any, Dict, Optional, Tuple
from .event_store import EventStore


class ToolEffectType:
    READ_ONLY = "read_only"
    IDEMPOTENT_WRITE = "idempotent_write"
    NON_IDEMPOTENT_WRITE = "non_idempotent_write"
    IRREVERSIBLE = "irreversible"


class ExecutionController:
    """Controls tool execution policies and side-effect deduplication."""

    def __init__(self, event_store: Optional[EventStore] = None):
        self.event_store = event_store or EventStore()

    @staticmethod
    def classify_tool(tool: str, args: Any) -> str:
        """Classifies tool into one of the 4 side-effect categories."""
        cmd = ""
        if isinstance(args, dict):
            cmd = args.get("cmd") or args.get("command") or ""
        elif isinstance(args, str):
            cmd = args

        cmd_lower = cmd.lower().strip()

        # Irreversible commands
        irreversible_patterns = [
            r"rm\s+-rf",
            r"git\s+reset\s+--hard",
            r"git\s+clean\s+-fd",
            r"mkfs",
            r"dd\s+if=",
            r"drop\s+table",
        ]
        if any(re.search(pat, cmd_lower) for pat in irreversible_patterns):
            return ToolEffectType.IRREVERSIBLE

        # Read-only tools/commands
        read_only_tools = {"read_file", "view_file", "search_web", "list_dir", "cat", "grep"}
        read_only_cmds = [
            r"^(cat|grep|egrep|find|ls|pwd|head|tail|wc|git\s+status|git\s+diff|git\s+log|stat|file)\b",
            r"pytest\b",
            r"python3\s+-m\s+unittest\b",
        ]
        if tool in read_only_tools or any(re.search(pat, cmd_lower) for pat in read_only_cmds):
            return ToolEffectType.READ_ONLY

        # Idempotent writes
        idempotent_cmds = [
            r"^mkdir\s+-p",
            r"^cp\b",
            r"^touch\b",
            r"^chmod\b",
            r"^ln\s+-sf",
        ]
        if tool in {"write_to_file", "overwrite_file"} or any(re.search(pat, cmd_lower) for pat in idempotent_cmds):
            return ToolEffectType.IDEMPOTENT_WRITE

        # Default fallback for other mutations (appends, commits, network POSTs)
        return ToolEffectType.NON_IDEMPOTENT_WRITE

    @staticmethod
    def generate_idempotency_key(task_id: str, tool: str, args: Any, cwd: str) -> str:
        """Deterministic fingerprint of action intent."""
        payload = f"{task_id}:{tool}:{cwd}:{json.dumps(args, sort_keys=True, default=str)}"
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    def check_pre_execution(
        self,
        task_id: str,
        tool: str,
        args: Any,
        cwd: str,
    ) -> Dict[str, Any]:
        """Validates tool execution permissions and deduplicates non-idempotent side effects."""
        effect_type = self.classify_tool(tool, args)
        idempotency_key = self.generate_idempotency_key(task_id, tool, args, cwd)
        args_hash = hashlib.sha256(str(args).encode()).hexdigest()[:16]

        # 1. Read-only commands: always permitted without side-effect tracking
        if effect_type == ToolEffectType.READ_ONLY:
            return {
                "permitted": True,
                "effect_type": effect_type,
                "idempotency_key": idempotency_key,
                "reason": "read_only_safe",
            }

        # 2. Check side-effect registry for duplicate non-idempotent actions
        check = self.event_store.check_or_record_side_effect(
            effect_id=idempotency_key[:16],
            task_id=task_id,
            tool_name=tool,
            idempotency_key=idempotency_key,
            effect_type=effect_type,
            args_hash=args_hash,
        )

        if check["exists"] and check["status"] == "executed":
            if effect_type in (ToolEffectType.NON_IDEMPOTENT_WRITE, ToolEffectType.IRREVERSIBLE):
                return {
                    "permitted": False,
                    "effect_type": effect_type,
                    "idempotency_key": idempotency_key,
                    "reason": f"Deduplication blocked: Identical {effect_type} effect already executed in this task.",
                    "prior_record": check["record"],
                }

        # 3. Irreversible commands: flag safety check
        if effect_type == ToolEffectType.IRREVERSIBLE:
            return {
                "permitted": True,
                "effect_type": effect_type,
                "idempotency_key": idempotency_key,
                "warning": "High-risk irreversible command detected. Side-effect logged.",
            }

        return {
            "permitted": True,
            "effect_type": effect_type,
            "idempotency_key": idempotency_key,
            "reason": "approved",
        }

    def record_post_execution(
        self,
        idempotency_key: str,
        exit_code: Optional[int],
        output_summary: str,
    ) -> None:
        status = "executed" if exit_code == 0 else "failed"
        self.event_store.update_side_effect(
            effect_id=idempotency_key[:16],
            status=status,
            result_summary=output_summary[:500],
        )
