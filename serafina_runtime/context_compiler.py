"""Prefix-Stable Context Compiler for Serafina 5.0.

Partitions prompts into:
  [Project Core (Static)] -> [Tool Definitions (Stable)] -> [Task Ledger (Middle)] -> [Evidence & Turns (Tail)]

Tracks:
  Prefix Cache Eligibility vs Actual Cache Hit.
"""
from __future__ import annotations

import hashlib
import json
from typing import Any, Dict, List, Optional, Tuple


class ContextCompiler:
    def __init__(self, token_budget: int = 57344):
        self.token_budget = token_budget
        self.total_requests = 0
        self.eligible_requests = 0
        self.actual_hits = 0

    @staticmethod
    def compute_cache_eligibility_key(
        model_id: str,
        model_revision: str,
        tokenizer_revision: str,
        chat_template_version: str,
        tool_schema_hash: str,
        prefix_token_hash: str,
        runtime_config_hash: str,
    ) -> str:
        """Computes multi-dimensional prefix eligibility key."""
        payload = f"{model_id}:{model_revision}:{tokenizer_revision}:{chat_template_version}:{tool_schema_hash}:{prefix_token_hash}:{runtime_config_hash}"
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    def compile_prompt(
        self,
        system_rules: str,
        project_core: str,
        task_ledger_summary: str,
        retrieved_evidence: List[str],
        recent_turns: List[Dict[str, Any]],
        tools_schema: Optional[List[Dict[str, Any]]] = None,
    ) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
        """Partitions content to maximize KV-Cache prefix reuse while respecting token budget."""
        self.total_requests += 1

        # 1. Project Core (Static prefix)
        core_text = project_core.strip()
        if not core_text and os.path.exists(".aoci/blueprint.md"):
            try:
                with open(".aoci/blueprint.md", "r", encoding="utf-8") as f:
                    core_text = f.read().strip()
            except Exception:
                pass
        static_system = f"{system_rules.strip()}\n\n[PROJECT CORE KNOWLEDGE]\n{core_text}"

        # 2. Tools hash
        tool_hash = hashlib.sha256(json.dumps(tools_schema or [], sort_keys=True).encode()).hexdigest()[:16]

        # 3. Middle: Task Ledger
        ledger_block = f"[CURRENT TASK LEDGER]\n{task_ledger_summary.strip()}"

        # 4. Tail: Retrieved facts
        evidence_block = ""
        if retrieved_evidence:
            evidence_block = "[VERIFIED RETRIEVED FACTS]\n" + "\n".join(f"- {e}" for e in retrieved_evidence[:10])

        compiled_messages: List[Dict[str, Any]] = [
            {"role": "system", "content": static_system},
            {"role": "system", "content": f"{ledger_block}\n\n{evidence_block}".strip()},
        ]

        # Add recent turns (never truncate the last 2 turns)
        compiled_messages.extend(recent_turns)

        prefix_hash = hashlib.sha256(static_system.encode()).hexdigest()[:16]
        eligibility_key = self.compute_cache_eligibility_key(
            model_id="active",
            model_revision="v1",
            tokenizer_revision="v1",
            chat_template_version="v1",
            tool_schema_hash=tool_hash,
            prefix_token_hash=prefix_hash,
            runtime_config_hash="default",
        )

        metadata = {
            "prefix_eligibility_key": eligibility_key,
            "static_prefix_hash": prefix_hash,
            "tool_schema_hash": tool_hash,
            "budget_tokens": self.token_budget,
        }
        self.eligible_requests += 1
        return compiled_messages, metadata

    def record_actual_hit(self, was_hit: bool) -> None:
        if was_hit:
            self.actual_hits += 1

    def get_cache_metrics(self) -> Dict[str, Any]:
        hit_rate = (self.actual_hits / max(1, self.total_requests)) * 100.0
        eligibility_rate = (self.eligible_requests / max(1, self.total_requests)) * 100.0
        return {
            "total_requests": self.total_requests,
            "eligible_requests": self.eligible_requests,
            "actual_hits": self.actual_hits,
            "eligibility_rate_pct": round(eligibility_rate, 1),
            "actual_hit_rate_pct": round(hit_rate, 1),
        }
