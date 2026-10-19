"""SQLite WAL Event Store and Persistence Engine for Serafina 5.0.

Provides durable, low-latency, CPU-first storage for task events, progress
ledgers, side-effect logs, and quiescent checkpoints.
"""
from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

DEFAULT_DB_PATH = Path.home() / ".local/share/serafina/runtime_events.db"

SCHEMA = """
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA busy_timeout=5000;

CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    turn_id TEXT DEFAULT '',
    event_type TEXT NOT NULL,
    source TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    created_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_task ON events(task_id, id);
CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id, id);

CREATE TABLE IF NOT EXISTS ledgers (
    task_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    workspace_root TEXT NOT NULL,
    state TEXT NOT NULL,
    phase TEXT NOT NULL,
    budget_json TEXT NOT NULL,
    acceptance_json TEXT NOT NULL,
    progress_json TEXT NOT NULL,
    evidence_json TEXT NOT NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS side_effects (
    effect_id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    tool_name TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    effect_type TEXT NOT NULL,
    status TEXT NOT NULL,
    args_hash TEXT NOT NULL,
    result_summary TEXT DEFAULT '',
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_effects_key ON side_effects(task_id, idempotency_key);

CREATE TABLE IF NOT EXISTS checkpoints (
    checkpoint_id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    step_number INTEGER NOT NULL,
    git_head TEXT DEFAULT '',
    git_dirty INTEGER DEFAULT 0,
    files_captured_json TEXT NOT NULL,
    workspace_quiescent INTEGER NOT NULL,
    state_snapshot_json TEXT NOT NULL,
    created_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_checkpoints_task ON checkpoints(task_id, step_number);
"""


class EventStore:
    def __init__(self, db_path: Optional[Path] = None):
        self.path = Path(db_path) if db_path else DEFAULT_DB_PATH
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _init_db(self) -> None:
        with self.connect() as conn:
            conn.executescript(SCHEMA)

    def connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(str(self.path), timeout=10.0)
        conn.row_factory = sqlite3.Row
        return conn

    # -- Event Append & Query --
    def record_event(
        self,
        task_id: str,
        session_id: str,
        event_type: str,
        payload: Dict[str, Any],
        source: str = "gateway",
        turn_id: str = "",
    ) -> int:
        now = time.time()
        payload_str = json.dumps(payload, ensure_ascii=False, sort_keys=True)
        with self.connect() as conn:
            cur = conn.execute(
                """
                INSERT INTO events (task_id, session_id, turn_id, event_type, source, payload_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (task_id, session_id, turn_id, event_type, source, payload_str, now),
            )
            return cur.lastrowid or 0

    def query_events(
        self,
        task_id: str,
        limit: int = 50,
        event_types: Optional[List[str]] = None,
    ) -> List[Dict[str, Any]]:
        with self.connect() as conn:
            if event_types:
                placeholders = ",".join("?" * len(event_types))
                query = f"""
                    SELECT id, task_id, session_id, turn_id, event_type, source, payload_json, created_at
                    FROM events
                    WHERE task_id = ? AND event_type IN ({placeholders})
                    ORDER BY id DESC LIMIT ?
                """
                rows = conn.execute(query, (task_id, *event_types, limit)).fetchall()
            else:
                query = """
                    SELECT id, task_id, session_id, turn_id, event_type, source, payload_json, created_at
                    FROM events
                    WHERE task_id = ?
                    ORDER BY id DESC LIMIT ?
                """
                rows = conn.execute(query, (task_id, limit)).fetchall()

        results = []
        for r in reversed(rows):
            results.append({
                "id": r["id"],
                "task_id": r["task_id"],
                "session_id": r["session_id"],
                "turn_id": r["turn_id"],
                "event_type": r["event_type"],
                "source": r["source"],
                "payload": json.loads(r["payload_json"]),
                "created_at": r["created_at"],
            })
        return results

    # -- Side Effects Logging (Idempotency Protection) --
    def check_or_record_side_effect(
        self,
        effect_id: str,
        task_id: str,
        tool_name: str,
        idempotency_key: str,
        effect_type: str,
        args_hash: str,
    ) -> Dict[str, Any]:
        """Check if an effect with the same idempotency_key already exists.
        Returns {'exists': bool, 'status': str, 'record': dict}
        """
        now = time.time()
        with self.connect() as conn:
            row = conn.execute(
                """
                SELECT effect_id, task_id, tool_name, idempotency_key, effect_type, status, args_hash, result_summary, created_at
                FROM side_effects
                WHERE task_id = ? AND idempotency_key = ?
                """,
                (task_id, idempotency_key),
            ).fetchone()

            if row:
                return {
                    "exists": True,
                    "status": row["status"],
                    "record": dict(row),
                }

            conn.execute(
                """
                INSERT INTO side_effects (effect_id, task_id, tool_name, idempotency_key, effect_type, status, args_hash, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, ?)
                """,
                (effect_id, task_id, tool_name, idempotency_key, effect_type, args_hash, now, now),
            )
            return {
                "exists": False,
                "status": "pending",
                "record": None,
            }

    def update_side_effect(
        self,
        effect_id: str,
        status: str,
        result_summary: str = "",
    ) -> None:
        now = time.time()
        with self.connect() as conn:
            conn.execute(
                """
                UPDATE side_effects
                SET status = ?, result_summary = ?, updated_at = ?
                WHERE effect_id = ?
                """,
                (status, result_summary[:1000], now, effect_id),
            )

    # -- Ledgers Store --
    def save_ledger(
        self,
        task_id: str,
        project_id: str,
        workspace_root: str,
        state: str,
        phase: str,
        budget: Dict[str, Any],
        acceptance: List[Dict[str, Any]],
        progress: Dict[str, Any],
        evidence: List[Dict[str, Any]],
    ) -> None:
        now = time.time()
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO ledgers (task_id, project_id, workspace_root, state, phase, budget_json, acceptance_json, progress_json, evidence_json, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(task_id) DO UPDATE SET
                    state = excluded.state,
                    phase = excluded.phase,
                    budget_json = excluded.budget_json,
                    acceptance_json = excluded.acceptance_json,
                    progress_json = excluded.progress_json,
                    evidence_json = excluded.evidence_json,
                    updated_at = excluded.updated_at
                """,
                (
                    task_id,
                    project_id,
                    workspace_root,
                    state,
                    phase,
                    json.dumps(budget, ensure_ascii=False),
                    json.dumps(acceptance, ensure_ascii=False),
                    json.dumps(progress, ensure_ascii=False),
                    json.dumps(evidence, ensure_ascii=False),
                    now,
                    now,
                ),
            )

    def load_ledger(self, task_id: str) -> Optional[Dict[str, Any]]:
        with self.connect() as conn:
            row = conn.execute(
                "SELECT * FROM ledgers WHERE task_id = ?",
                (task_id,),
            ).fetchone()
            if not row:
                return None
            return {
                "task_id": row["task_id"],
                "project_id": row["project_id"],
                "workspace_root": row["workspace_root"],
                "state": row["state"],
                "phase": row["phase"],
                "budget": json.loads(row["budget_json"]),
                "acceptance": json.loads(row["acceptance_json"]),
                "progress": json.loads(row["progress_json"]),
                "evidence": json.loads(row["evidence_json"]),
                "created_at": row["created_at"],
                "updated_at": row["updated_at"],
            }

    # -- Checkpoint Store --
    def record_checkpoint(
        self,
        checkpoint_id: str,
        task_id: str,
        step_number: int,
        git_head: str,
        git_dirty: bool,
        files_captured: List[str],
        workspace_quiescent: bool,
        state_snapshot: Dict[str, Any],
    ) -> None:
        now = time.time()
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO checkpoints (checkpoint_id, task_id, step_number, git_head, git_dirty, files_captured_json, workspace_quiescent, state_snapshot_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    checkpoint_id,
                    task_id,
                    step_number,
                    git_head,
                    1 if git_dirty else 0,
                    json.dumps(files_captured, ensure_ascii=False),
                    1 if workspace_quiescent else 0,
                    json.dumps(state_snapshot, ensure_ascii=False),
                    now,
                ),
            )

    def get_latest_checkpoint(self, task_id: str) -> Optional[Dict[str, Any]]:
        with self.connect() as conn:
            row = conn.execute(
                """
                SELECT * FROM checkpoints
                WHERE task_id = ?
                ORDER BY step_number DESC LIMIT 1
                """,
                (task_id,),
            ).fetchone()
            if not row:
                return None
            return {
                "checkpoint_id": row["checkpoint_id"],
                "task_id": row["task_id"],
                "step_number": row["step_number"],
                "git_head": row["git_head"],
                "git_dirty": bool(row["git_dirty"]),
                "files_captured": json.loads(row["files_captured_json"]),
                "workspace_quiescent": bool(row["workspace_quiescent"]),
                "state_snapshot": json.loads(row["state_snapshot_json"]),
                "created_at": row["created_at"],
            }
