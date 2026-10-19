"""Task ledger (SQLite): the durable state the orchestrator decides from.

New sessions are rebuilt from the ledger (task card + facts + handoff), never
by replaying transcripts.
"""
from __future__ import annotations

import json
import sqlite3
import time
import uuid
from pathlib import Path

SCHEMA = '''
CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY, repo TEXT, workspace TEXT, branch TEXT, goal TEXT, accept TEXT,
  status TEXT, created REAL, updated REAL, result TEXT);
CREATE TABLE IF NOT EXISTS tasks (
  id TEXT PRIMARY KEY, run_id TEXT, parent_id TEXT, role TEXT, goal TEXT, accept TEXT,
  status TEXT, attempts INTEGER DEFAULT 0, sessions INTEGER DEFAULT 0,
  created REAL, updated REAL, result TEXT);
CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY, task_id TEXT, seq INTEGER, role TEXT, status TEXT, end_reason TEXT,
  rounds INTEGER DEFAULT 0, prompt_tokens INTEGER DEFAULT 0, cached_tokens INTEGER DEFAULT 0,
  new_prefill_tokens INTEGER DEFAULT 0, completion_tokens INTEGER DEFAULT 0,
  model_s REAL DEFAULT 0, tool_s REAL DEFAULT 0, last_prompt_tokens INTEGER DEFAULT 0,
  started REAL, ended REAL);
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT, session_id TEXT, round INTEGER,
  kind TEXT, data TEXT, created REAL);
CREATE TABLE IF NOT EXISTS facts (
  id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT, kind TEXT, text TEXT, created REAL);
CREATE TABLE IF NOT EXISTS handoffs (
  session_id TEXT PRIMARY KEY, task_id TEXT, data TEXT, created REAL);
CREATE INDEX IF NOT EXISTS events_task ON events(task_id, id);
CREATE INDEX IF NOT EXISTS facts_task ON facts(task_id, id);
'''


def _dumps(value):
    return json.dumps(value, ensure_ascii=False)


class Ledger:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as c:
            c.execute('PRAGMA journal_mode=WAL')
            c.executescript(SCHEMA)

    def connect(self):
        conn = sqlite3.connect(self.path, timeout=30)
        conn.row_factory = sqlite3.Row
        return conn

    # -- runs and tasks ----------------------------------------------------
    @staticmethod
    def new_run_id():
        return time.strftime('%m%d-%H%M%S-') + uuid.uuid4().hex[:4]

    def create_run(self, run_id, repo, workspace, branch, goal, accept):
        now = time.time()
        with self.connect() as c:
            c.execute('INSERT INTO runs VALUES (?,?,?,?,?,?,?,?,?,?)',
                      (run_id, str(repo), str(workspace), branch, goal, accept, 'running', now, now, None))
        return run_id

    def finish_run(self, run_id, status, result):
        with self.connect() as c:
            c.execute('UPDATE runs SET status=?, updated=?, result=? WHERE id=?',
                      (status, time.time(), _dumps(result), run_id))

    def create_task(self, run_id, goal, accept, role='coder', parent_id=None):
        task_id = run_id + '-t' + uuid.uuid4().hex[:4]
        now = time.time()
        with self.connect() as c:
            c.execute('INSERT INTO tasks (id, run_id, parent_id, role, goal, accept, status, created, updated) '
                      'VALUES (?,?,?,?,?,?,?,?,?)', (task_id, run_id, parent_id, role, goal, accept, 'pending', now, now))
        return task_id

    def update_task(self, task_id, **fields):
        if 'result' in fields:
            fields['result'] = _dumps(fields['result'])
        fields['updated'] = time.time()
        keys = ', '.join(f'{k}=?' for k in fields)
        with self.connect() as c:
            c.execute(f'UPDATE tasks SET {keys} WHERE id=?', (*fields.values(), task_id))

    def task(self, task_id):
        with self.connect() as c:
            row = c.execute('SELECT * FROM tasks WHERE id=?', (task_id,)).fetchone()
        return dict(row) if row else None

    # -- sessions ----------------------------------------------------------
    def start_session(self, task_id, seq, role):
        session_id = f'{task_id}-s{seq}'
        with self.connect() as c:
            c.execute('INSERT OR REPLACE INTO sessions (id, task_id, seq, role, status, started) VALUES (?,?,?,?,?,?)',
                      (session_id, task_id, seq, role, 'running', time.time()))
        return session_id

    def add_usage(self, session_id, usage, model_s):
        with self.connect() as c:
            c.execute('UPDATE sessions SET rounds=rounds+1, prompt_tokens=prompt_tokens+?, cached_tokens=cached_tokens+?, '
                      'new_prefill_tokens=new_prefill_tokens+?, completion_tokens=completion_tokens+?, model_s=model_s+?, '
                      'last_prompt_tokens=? WHERE id=?',
                      (int(usage.get('prompt_tokens') or 0), int(usage.get('cached_tokens') or 0),
                       int(usage.get('new_prefill_tokens') or 0), int(usage.get('completion_tokens') or 0),
                       float(model_s), int(usage.get('prompt_tokens') or 0), session_id))

    def add_tool_time(self, session_id, seconds):
        with self.connect() as c:
            c.execute('UPDATE sessions SET tool_s=tool_s+? WHERE id=?', (float(seconds), session_id))

    def end_session(self, session_id, end_reason):
        with self.connect() as c:
            c.execute('UPDATE sessions SET status=?, end_reason=?, ended=? WHERE id=?',
                      ('ended', end_reason, time.time(), session_id))

    def sessions(self, task_id):
        with self.connect() as c:
            return [dict(r) for r in c.execute('SELECT * FROM sessions WHERE task_id=? ORDER BY seq', (task_id,))]

    # -- events, facts, handoffs ------------------------------------------
    def event(self, task_id, session_id, round_no, kind, data):
        with self.connect() as c:
            c.execute('INSERT INTO events (task_id, session_id, round, kind, data, created) VALUES (?,?,?,?,?,?)',
                      (task_id, session_id, round_no, kind, _dumps(data), time.time()))

    def events(self, task_id, kinds=None, limit=200):
        sql = 'SELECT * FROM events WHERE task_id=?'
        params = [task_id]
        if kinds:
            sql += f' AND kind IN ({",".join("?" * len(kinds))})'
            params += list(kinds)
        sql += ' ORDER BY id DESC LIMIT ?'
        with self.connect() as c:
            rows = [dict(r) for r in c.execute(sql, (*params, limit))]
        for row in rows:
            row['data'] = json.loads(row['data'])
        return rows[::-1]

    def fact(self, task_id, kind, text):
        with self.connect() as c:
            exists = c.execute('SELECT 1 FROM facts WHERE task_id=? AND kind=? AND text=?', (task_id, kind, text)).fetchone()
            if not exists:
                c.execute('INSERT INTO facts (task_id, kind, text, created) VALUES (?,?,?,?)',
                          (task_id, kind, text, time.time()))

    def facts(self, task_id, limit=20):
        with self.connect() as c:
            rows = c.execute('SELECT kind, text FROM facts WHERE task_id=? ORDER BY id DESC LIMIT ?',
                             (task_id, limit)).fetchall()
        return [dict(r) for r in rows][::-1]

    def save_handoff(self, session_id, task_id, data):
        with self.connect() as c:
            c.execute('INSERT OR REPLACE INTO handoffs VALUES (?,?,?,?)', (session_id, task_id, _dumps(data), time.time()))

    # -- reporting ---------------------------------------------------------
    def runs(self, limit=10):
        with self.connect() as c:
            return [dict(r) for r in c.execute('SELECT * FROM runs ORDER BY created DESC LIMIT ?', (limit,))]

    def run(self, run_id):
        with self.connect() as c:
            row = c.execute('SELECT * FROM runs WHERE id=?', (run_id,)).fetchone()
            tasks = [dict(r) for r in c.execute('SELECT * FROM tasks WHERE run_id=? ORDER BY created', (run_id,))]
        return (dict(row) if row else None), tasks
