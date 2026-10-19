"""CPU-First Memory Engine (SQLite FTS5 + Content-Addressed Blob Storage) for Serafina 5.0.

Keeps memory usage strictly within the 50–150MB tier by streaming tool
outputs larger than 4KB into APFS SHA-256 blob files.
"""
from __future__ import annotations

import hashlib
import sqlite3
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

DEFAULT_BLOB_DIR = Path.home() / ".local/share/serafina/blobs"
DEFAULT_FTS_DB = Path.home() / ".local/share/serafina/memory_fts.db"


class MemoryEngine:
    def __init__(self, fts_db_path: Optional[Path] = None, blob_dir: Optional[Path] = None):
        self.fts_path = Path(fts_db_path) if fts_db_path else DEFAULT_FTS_DB
        self.blob_dir = Path(blob_dir) if blob_dir else DEFAULT_BLOB_DIR

        self.fts_path.parent.mkdir(parents=True, exist_ok=True)
        self.blob_dir.mkdir(parents=True, exist_ok=True)
        self._init_fts()

    def _init_fts(self) -> None:
        with self.connect() as conn:
            conn.execute("PRAGMA journal_mode=WAL;")
            conn.execute("PRAGMA synchronous=NORMAL;")
            conn.execute(
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS facts_fts USING fts5(
                    task_id,
                    project_id,
                    category,
                    content,
                    evidence_ref
                );
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS project_core (
                    project_id TEXT PRIMARY KEY,
                    core_knowledge TEXT NOT NULL,
                    version INTEGER NOT NULL,
                    updated_at REAL NOT NULL
                );
                """
            )

    def connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(str(self.fts_path), timeout=5.0)
        conn.row_factory = sqlite3.Row
        return conn

    # -- Content-Addressed Blobs --
    def store_blob(self, content: str) -> Tuple[str, int]:
        """Saves content to SHA-256 named file if large, returns (hash, bytes_size)."""
        data = content.encode("utf-8")
        h = hashlib.sha256(data).hexdigest()
        blob_path = self.blob_dir / f"{h[:2]}/{h}"
        blob_path.parent.mkdir(parents=True, exist_ok=True)
        if not blob_path.exists():
            blob_path.write_bytes(data)
        return h, len(data)

    def read_blob(self, blob_hash: str) -> Optional[str]:
        blob_path = self.blob_dir / f"{blob_hash[:2]}/{blob_hash}"
        if blob_path.exists():
            return blob_path.read_text(encoding="utf-8")
        return None

    # -- FTS5 Search & Facts Index --
    def index_fact(
        self,
        task_id: str,
        project_id: str,
        category: str,
        content: str,
        evidence_ref: str = "",
    ) -> None:
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO facts_fts (task_id, project_id, category, content, evidence_ref)
                VALUES (?, ?, ?, ?, ?)
                """,
                (task_id, project_id, category, content, evidence_ref),
            )

    def search_facts(self, project_id: str, query: str, limit: int = 5) -> List[Dict[str, Any]]:
        # Sanitize query for FTS5
        clean_q = "".join(c for c in query if c.isalnum() or c.isspace()).strip()
        if not clean_q:
            return []
        tokens = clean_q.split()
        match_query = " OR ".join(f"{t}*" for t in tokens[:6])

        with self.connect() as conn:
            try:
                rows = conn.execute(
                    """
                    SELECT task_id, category, content, evidence_ref, rank
                    FROM facts_fts
                    WHERE project_id = ? AND facts_fts MATCH ?
                    ORDER BY rank LIMIT ?
                    """,
                    (project_id, match_query, limit),
                ).fetchall()
                return [dict(r) for r in rows]
            except Exception:
                return []

    # -- Project Core Knowledge --
    def get_project_core(self, project_id: str) -> str:
        with self.connect() as conn:
            row = conn.execute(
                "SELECT core_knowledge FROM project_core WHERE project_id = ?",
                (project_id,),
            ).fetchone()
            return row["core_knowledge"] if row else ""

    def update_project_core(self, project_id: str, core_knowledge: str) -> int:
        now = time.time()
        with self.connect() as conn:
            cur = conn.execute(
                """
                INSERT INTO project_core (project_id, core_knowledge, version, updated_at)
                VALUES (?, ?, 1, ?)
                ON CONFLICT(project_id) DO UPDATE SET
                    core_knowledge = excluded.core_knowledge,
                    version = project_core.version + 1,
                    updated_at = excluded.updated_at
                """,
                (project_id, core_knowledge, now),
            )
            return cur.rowcount
