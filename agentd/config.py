"""Settings. Defaults are engineering starting points, not model limits.

Overrides: runtime.json {"agentd": {...}} written by the switcher app, then
command line flags.
"""
from __future__ import annotations

import json
from pathlib import Path

HOME = Path.home()
RUNTIME = HOME / '.local/state/mtplx-qwen38/runtime.json'
DATA = HOME / '.local/share/agentd'
TRAFFIC = HOME / 'Library/Logs/CodexModelSwitcher/traffic.jsonl'

DEFAULTS = {
    # Per worker session. At handoff_ratio of the budget the worker writes a
    # structured handoff and a fresh session continues from the task card.
    'team_mode': False,
    'companion_model': 'openai/gpt-oss-20b',
    'review_rounds': 6,
    'input_budget': 24576,
    'handoff_ratio': 0.7,
    'max_output_tokens': 8192,
    'rounds_per_session': 16,
    # Per task.
    'max_sessions': 6,
    'max_attempts': 4,        # failed acceptance runs
    'max_stalls': 2,          # sessions that ended without measurable progress
    # Loop guards inside a session.
    'repeat_limit': 3,        # duplicate calls before the session is ended as a loop
    'no_action_limit': 2,     # replies without a tool call
    'edits_before_verify': 3, # edits to one file without a successful run
    'run_timeout': 180,
    # 'auto' keeps MTPLX's restored prefix stable; 'required' forces a tool
    # call every round but voids the session cache after a few rounds.
    'tool_choice': 'auto',
    'accept_timeout': 600,
}


def runtime() -> dict:
    try:
        return json.loads(RUNTIME.read_text())
    except (OSError, ValueError):
        return {}


def load(overrides: dict | None = None) -> dict:
    config = dict(DEFAULTS)
    stored = runtime().get('agentd')
    if isinstance(stored, dict):
        config.update({k: v for k, v in stored.items() if k in DEFAULTS})
    config.update({k: v for k, v in (overrides or {}).items() if v is not None})
    return config
