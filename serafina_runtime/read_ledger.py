"""Read Ledger for Serafina L5 (loop guard against read paralysis).

Built from the client's *full* message history (before compaction), so it keeps
working even when the model itself only sees a tiny rolling window.

Design:
  * Progress signal = a mutating tool call (edit/write/patch/...), not keyword luck.
  * Per-file accounting: reads of a file reset when that file is mutated.
  * Levels: 0 ok, 1 notice (re-read), 2 stuck (mask read tools), 3 handled by caller (pause).
  * A new user message resets everything (user intervention = new intent).
"""
from __future__ import annotations

import json
import posixpath
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

_PATH_KEYS = ("path", "filePath", "file_path", "target_file", "AbsolutePath", "file", "filename", "uri")
_READ_NAMES = {"read", "read_file", "view", "view_file", "cat", "open", "open_file", "get_file", "fetch"}
_MUTATE_HINTS = ("write", "edit", "patch", "replace", "apply", "create", "delete", "remove", "move", "rename", "multiedit", "insert")

# Thresholds
REREAD_NOTICE = 2        # same unmodified file read this many times -> notice
REREAD_STUCK = 3         # ... -> stuck (mask reads)
OSCILLATION_WINDOW = 6   # last N reads touching <=2 files -> stuck
NO_PROGRESS_READS = 10   # consecutive reads with no mutation -> stuck


def _short(name: str) -> str:
    return (name or "").split(".")[-1].split("/")[-1].lower()


def is_read_tool(name: str) -> bool:
    n = _short(name)
    return n in _READ_NAMES or n.startswith("read") or n.startswith("view")


def is_mutating_tool(name: str) -> bool:
    n = _short(name)
    return any(h in n for h in _MUTATE_HINTS)


def extract_path(args: Any) -> str:
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except Exception:
            return ""
    if not isinstance(args, dict):
        return ""
    for key in _PATH_KEYS:
        value = args.get(key)
        if isinstance(value, str) and value:
            return value
    return ""


@dataclass
class FileState:
    path: str
    reads: int = 0
    modified_since_read: bool = False
    summary: str = ""


@dataclass
class LedgerVerdict:
    level: int = 0
    reason: str = ""
    files: Dict[str, FileState] = field(default_factory=dict)
    consecutive_reads: int = 0
    mutations: int = 0

    def block(self, path: str) -> bool:
        """Should a read of `path` be refused right now?"""
        st = self.files.get(path)
        return bool(st and st.reads >= REREAD_NOTICE and not st.modified_since_read)

    def render(self) -> str:
        if not self.files:
            return ""
        lines = ["[Serafina 任务台账 · 已读文件，内容已知，不要重复读取]"]
        for st in list(self.files.values())[-8:]:
            tag = "已修改，可再读一次核对" if st.modified_since_read else f"已读{st.reads}次"
            lines.append(f"- {posixpath.basename(st.path)}（{tag}）{st.summary}")
        lines.append(f"- 累计修改操作：{self.mutations}；连续只读：{self.consecutive_reads}")
        if self.level >= 1:
            lines.append("下一步：基于已知信息直接编辑/写入文件；如需定位依赖关系，请优先使用 code_outline 或 code_callers，避免暴力重复读取全文。")
        return "\n".join(lines)


def analyze(messages: List[Dict[str, Any]]) -> LedgerVerdict:
    v = LedgerVerdict()
    pending: Dict[str, str] = {}   # tool_call_id -> path (reads awaiting result)
    recent_reads: List[str] = []

    for m in messages:
        role = m.get("role")
        if role == "user":
            # user intervention resets intent
            v = LedgerVerdict()
            pending.clear()
            recent_reads.clear()
            continue
        if role == "assistant":
            for call in m.get("tool_calls") or []:
                fn = call.get("function") if isinstance(call, dict) else None
                if not isinstance(fn, dict):
                    continue
                name = str(fn.get("name") or "")
                path = extract_path(fn.get("arguments"))
                if is_read_tool(name) and path:
                    st = v.files.setdefault(path, FileState(path))
                    st.reads += 1
                    st.modified_since_read = False
                    v.consecutive_reads += 1
                    recent_reads.append(path)
                    if call.get("id"):
                        pending[str(call["id"])] = path
                elif is_mutating_tool(name):
                    v.mutations += 1
                    v.consecutive_reads = 0
                    recent_reads.clear()
                    if path and path in v.files:
                        v.files[path].modified_since_read = True
                        v.files[path].reads = 0
                    elif not path:
                        for st in v.files.values():
                            st.modified_since_read = True
                            st.reads = 0
                # shell/other tools: neutral (neither progress nor read)
        elif role == "tool":
            pid = pending.pop(str(m.get("tool_call_id") or ""), None)
            if pid and pid in v.files:
                text = m.get("content")
                if isinstance(text, str) and text:
                    flat = " ".join(text.split())
                    v.files[pid].summary = "：" + flat[:120] if flat else ""

    worst = max((s.reads for s in v.files.values() if not s.modified_since_read), default=0)
    if worst >= REREAD_STUCK:
        v.level, v.reason = 2, f"同一文件未修改却已读 {worst} 次"
    elif len(recent_reads) >= OSCILLATION_WINDOW and len(set(recent_reads[-OSCILLATION_WINDOW:])) <= 2:
        v.level, v.reason = 2, f"最近 {OSCILLATION_WINDOW} 次读取在 ≤2 个文件间来回切换"
    elif v.consecutive_reads >= NO_PROGRESS_READS:
        v.level, v.reason = 2, f"连续 {v.consecutive_reads} 次只读且无任何修改"
    elif worst >= REREAD_NOTICE:
        v.level, v.reason = 1, f"文件被重复读取 {worst} 次"
    return v
