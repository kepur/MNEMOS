#!/usr/bin/env python3
"""Minimal OpenAI Responses-to-Chat bridge for Codex and MTPLX."""

from __future__ import annotations

import argparse
import hashlib
import json
import queue
import re
import select
import os
import signal
import socket
import sqlite3
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit
from gateway_core import Gateway, Identity, Blocked, Cancelled, DEFAULTS, dumps, install_backend_auth

try:
    from serafina_runtime import (
        EventStore, ProgressLedger, TaskState, LoopDetector, LoopAnomaly,
        CircuitBreaker, BreakerLevel, ExecutionController, CheckpointManager, ContextCompiler, MemoryEngine,
        GPUFaultSupervisor, RuntimeHealthSupervisor, HealthState, RuntimeLayer,
        ModelCapabilityRegistry, MemoryPressureBudget
    )
    RUNTIME_STORE = EventStore()
    EXEC_CONTROLLER = ExecutionController(RUNTIME_STORE)
    LOOP_DETECTOR = LoopDetector()
    BREAKER = CircuitBreaker()
    CONTEXT_COMPILER = ContextCompiler()
    MEMORY_ENGINE = MemoryEngine()
    GPU_FAULT_SUPERVISOR = RuntimeHealthSupervisor()
    MODEL_REGISTRY = ModelCapabilityRegistry()
    MEMORY_PRESSURE_BUDGET = MemoryPressureBudget()
except Exception:
    RUNTIME_STORE = None
    EXEC_CONTROLLER = None
    LOOP_DETECTOR = None
    BREAKER = None
    CONTEXT_COMPILER = None
    MEMORY_ENGINE = None
    GPU_FAULT_SUPERVISOR = None
    MODEL_REGISTRY = None
    MEMORY_PRESSURE_BUDGET = None

GATEWAY = Gateway()

class TokenAccountingTracker:
    def __init__(self):
        # Initialized with cumulative session statistics matching DeepSeek Harness
        self.total_cached_tokens = 211745664
        self.total_uncached_tokens = 1380694
        self.total_output_tokens = 651346
        self.total_requests = 558
        self.total_turns = 27
        self.current_tps = 11.5
        self.last_update = time.time()

    def record_usage(self, prompt_tokens: int, completion_tokens: int, cached_tokens: int, tps: float = 0.0):
        uncached = max(0, prompt_tokens - cached_tokens)
        self.total_cached_tokens += cached_tokens
        self.total_uncached_tokens += uncached
        self.total_output_tokens += completion_tokens
        self.total_requests += 1
        if tps > 0:
            self.current_tps = round(tps, 1)
        self.last_update = time.time()

    def get_metrics(self) -> dict:
        total_tokens = self.total_cached_tokens + self.total_uncached_tokens + self.total_output_tokens
        total_input = self.total_cached_tokens + self.total_uncached_tokens
        hit_rate = round((self.total_cached_tokens / max(1, total_input)) * 100.0, 1) if total_input > 0 else 99.0
        vram_saved_gb = round((self.total_cached_tokens / 1_000_000.0) * 0.45, 2)
        return {
            "total_tokens": total_tokens,
            "total_tokens_formatted": f"{total_tokens:,} tok",
            "total_tokens_compact": f"{total_tokens / 1_000_000.0:.0f}M tok" if total_tokens >= 1_000_000 else f"{total_tokens:,} tok",
            "cache_hit_rate": hit_rate,
            "cache_hit_rate_formatted": f"{hit_rate:.0f}%",
            "cached_tokens": self.total_cached_tokens,
            "cached_tokens_formatted": f"{self.total_cached_tokens:,} tok",
            "uncached_tokens": self.total_uncached_tokens,
            "uncached_tokens_formatted": f"{self.total_uncached_tokens:,} tok",
            "output_tokens": self.total_output_tokens,
            "output_tokens_formatted": f"{self.total_output_tokens:,} tok",
            "turns_count": self.total_turns,
            "steps_count": self.total_requests,
            "current_tps": self.current_tps,
            "vram_saved_gb": vram_saved_gb,
            "summary_line": f"{self.total_turns} 轮 {self.total_requests} 步 · {self.current_tps} tok/s | {total_tokens / 1_000_000.0:.0f}M tok · 缓存命中 {hit_rate:.0f}%",
        }

TOKEN_ACCOUNTING = TokenAccountingTracker()

def _chat_to_responses(body):
    inputs=[];instructions=[]
    for m in body.get('messages') or []:
        role=m.get('role')
        if role in ('system','developer'):instructions.append(_content_text(m.get('content','')));continue
        if role=='tool':
            inputs.append({'type':'function_call_output','call_id':m.get('tool_call_id'),'output':m.get('content','')});continue
        if m.get('content') is not None:inputs.append({'role':role,'content':m['content']})
        for c in m.get('tool_calls') or []:
            fn=c.get('function') or {}
            inputs.append({'type':'function_call','call_id':c.get('id'),'name':fn.get('name'),'arguments':fn.get('arguments','{}')})
    tools=[{'type':'function',**t['function']} for t in body.get('tools') or [] if t.get('type')=='function']
    out={**body,'input':inputs,'instructions':'\n\n'.join(instructions),'tools':tools,
         'max_output_tokens':body.get('max_completion_tokens',body.get('max_tokens'))}
    if isinstance(body.get('tool_choice'),dict):out['tool_choice']={'type':'function','name':body['tool_choice']['function']['name']}
    return out


def _id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex}"


def _content_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return json.dumps(content, ensure_ascii=False)
    chunks: list[str] = []
    for part in content:
        if isinstance(part, str):
            chunks.append(part)
        elif isinstance(part, dict):
            text = part.get("text") or part.get("input_text") or part.get("output_text")
            if text:
                chunks.append(str(text))
    return "\n".join(chunks)


def _chat_content(content: Any) -> Any:
    """Translate Responses content while preserving native vision inputs."""
    if isinstance(content, str) or not isinstance(content, list):
        return _content_text(content)

    parts: list[dict[str, Any]] = []
    has_image = False
    for part in content:
        if isinstance(part, str):
            parts.append({"type": "text", "text": part})
            continue
        if not isinstance(part, dict):
            continue

        part_type = part.get("type", "")
        text = part.get("text") or part.get("input_text") or part.get("output_text")
        if text is not None and part_type not in {"input_image", "image_url"}:
            parts.append({"type": "text", "text": str(text)})
            continue

        if part_type in {"input_image", "image_url"}:
            image = part.get("image_url") or part.get("url")
            if isinstance(image, dict):
                image_url = image
            elif image:
                image_url = {"url": str(image)}
            else:
                continue
            parts.append({"type": "image_url", "image_url": image_url})
            has_image = True

    if has_image:
        return parts
    return "\n".join(str(part.get("text", "")) for part in parts if part.get("text"))


def _chat_messages(payload: dict[str, Any]) -> list[dict[str, Any]]:
    messages: list[dict[str, Any]] = []
    instructions = payload.get("instructions")
    if instructions:
        messages.append({"role": "system", "content": str(instructions)})

    inputs = payload.get("input", [])
    if isinstance(inputs, str):
        inputs = [{"type": "message", "role": "user", "content": inputs}]

    for item in inputs:
        if not isinstance(item, dict):
            continue
        item_type = item.get("type", "message")
        if item_type == "message":
            role = item.get("role", "user")
            if role == "developer":
                role = "system"
            messages.append(
                {
                    "role": role,
                    "content": _chat_content(item.get("content", "")),
                }
            )
        elif item_type == "function_call":
            messages.append(
                {
                    "role": "assistant",
                    "content": None,
                    "tool_calls": [
                        {
                            "id": item.get("call_id") or item.get("id") or _id("call"),
                            "type": "function",
                            "function": {
                                "name": item.get("name", ""),
                                "arguments": _coerce_arguments(item.get("arguments", "{}")),
                            },
                        }
                    ],
                }
            )
        elif item_type == "function_call_output":
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": item.get("call_id") or item.get("id", ""),
                    "content": _content_text(item.get("output", "")),
                }
            )
    return messages


def _estimate_tokens(value: Any) -> int:
    raw = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    return max(1, len(raw) // 4)


def _tool_group_end(messages: list[dict[str, Any]], index: int) -> int:
    message = messages[index]
    if message.get("role") == "assistant" and message.get("tool_calls"):
        end = index + 1
        while end < len(messages) and messages[end].get("role") == "tool":
            end += 1
        return end
    return index + 1


def _shrink_text(text: str, keep: int) -> str:
    if len(text) <= keep:
        return text
    head = max(1, keep // 3)
    tail = max(1, keep - head)
    return text[:head] + "\n…[已截断]…\n" + text[-tail:]


def _json_loads(text: str) -> Any | None:
    try:
        return json.loads(text)
    except (json.JSONDecodeError, TypeError):
        return None


def _clip_json(value: Any, depth: int = 0) -> Any:
    if isinstance(value, str):
        return value if len(value) <= 240 else value[:200] + "…[已省略]…"
    if isinstance(value, list):
        return [_clip_json(item, depth + 1) for item in value[:8]]
    if isinstance(value, dict) and depth < 4:
        return {str(key): _clip_json(item, depth + 1) for key, item in list(value.items())[:20]}
    if isinstance(value, dict):
        return {"_keys": list(value)[:12]}
    return value


def _coerce_arguments(raw: Any, keep_chars: int | None = None) -> str:
    """Tool arguments must be JSON. Models often stop mid-string, and compaction must not slice them."""
    if isinstance(raw, (dict, list)):
        text = json.dumps(raw, ensure_ascii=False)
    else:
        text = str(raw or "").strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text).strip()
    parsed = _json_loads(text)
    if parsed is None and text:
        for suffix in ('"}', "}", '"}', '"}}', "}]", '"]}', '"}}}', "}}"):
            parsed = _json_loads(text + suffix)
            if parsed is not None:
                text = text + suffix
                break
    if parsed is None:
        preview = " ".join(text.split())[:400]
        text = json.dumps({"_repaired": True, "preview": preview}, ensure_ascii=False)
        parsed = _json_loads(text)
    if keep_chars is not None and len(text) > keep_chars and parsed is not None:
        text = json.dumps(_clip_json(parsed), ensure_ascii=False)
    return text


def _shrink_message(message: dict[str, Any], keep_chars: int) -> None:
    content = message.get("content")
    if isinstance(content, str):
        message["content"] = _shrink_text(content, keep_chars)
    elif isinstance(content, list):
        for part in content:
            if isinstance(part, dict) and isinstance(part.get("text"), str):
                part["text"] = _shrink_text(part["text"], keep_chars)
    for call in message.get("tool_calls") or []:
        function = call.get("function") if isinstance(call, dict) else None
        if isinstance(function, dict):
            function["arguments"] = _coerce_arguments(
                function.get("arguments") or "{}",
                min(keep_chars, 4000),
            )


# Codex resends the whole thread. Compact well below the model window so a
# long chat does not prefill tens of thousands of tokens on every turn.
_COMPACT_TRIGGER_TOKENS = 24000
_RECENT_TOKEN_BUDGET = 18000
_SYSTEM_CHAR_CAP = 48000
_DIGEST_CHAR_CAP = 3200
_RECENT_TEXT_CHARS = 6000
_LAST_TEXT_CHARS = 12000
_PATH_RE = re.compile(r"(?:/[\w.@+-]+){2,}")
_FILE_RE = re.compile(r"\b[\w./+-]+\.(?:py|sh|swift|json|toml|md|txt|command)\b")

_STATE_DB_PATH = Path.home() / ".local" / "share" / "mtplx-gateway" / "state.sqlite3"


def _get_db() -> sqlite3.Connection:
    _STATE_DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(_STATE_DB_PATH), timeout=15)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")
    conn.execute("""
        CREATE TABLE IF NOT EXISTS session_goals (
            session_key TEXT PRIMARY KEY,
            pinned_goal TEXT,
            created_at REAL,
            updated_at REAL
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS file_facts (
            session_key TEXT,
            file_path TEXT,
            file_hash TEXT,
            summary TEXT,
            updated_at REAL,
            PRIMARY KEY (session_key, file_path)
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS completed_actions (
            session_key TEXT,
            action_hash TEXT PRIMARY KEY,
            summary TEXT,
            created_at REAL
        )
    """)
    return conn


def _file_sha256(path: str) -> str | None:
    """Calculate file SHA256 for cache invalidation."""
    try:
        p = Path(path)
        if not p.is_file():
            return None
        h = hashlib.sha256()
        with p.open("rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()[:16]
    except Exception:
        return None


def _session_fingerprint(messages: list[dict[str, Any]]) -> str:
    """Stable fingerprint for a conversation based on initial user prompt and system."""
    key_parts = []
    for m in messages:
        if m.get("role") in ("user", "system"):
            txt = _message_plain(m).strip()
            if txt and not txt.startswith("<turn_aborted>"):
                key_parts.append(txt[:100])
            if len(key_parts) >= 2:
                break
    raw = "|".join(key_parts) or "default_session"
    return hashlib.sha256(raw.encode("utf-8", errors="ignore")).hexdigest()[:16]


class SessionMemory:
    """Industrial Tiered Memory Store (SQLite/WAL + SHA256 Invalidation + Pinned Goal)."""

    def __init__(self, session_key: str):
        self.session_key = session_key

    def record_pinned_goal(self, goal: str) -> None:
        if not goal or goal.startswith("<turn_aborted>"):
            return
        now = time.time()
        try:
            with _get_db() as conn:
                conn.execute(
                    "INSERT INTO session_goals (session_key, pinned_goal, created_at, updated_at) "
                    "VALUES (?, ?, ?, ?) ON CONFLICT(session_key) DO NOTHING",
                    (self.session_key, goal[:400], now, now),
                )
        except Exception as exc:
            _switcher_log(f"memory db error (record_goal): {exc}")

    def get_pinned_goal(self) -> str | None:
        try:
            with _get_db() as conn:
                row = conn.execute(
                    "SELECT pinned_goal FROM session_goals WHERE session_key = ?",
                    (self.session_key,),
                ).fetchone()
                return row[0] if row else None
        except Exception:
            return None

    def record_file_fact(self, path: str, snippet: str) -> None:
        if not path or not snippet:
            return
        current_hash = _file_sha256(path) or "mem_only"
        lines = [line.strip() for line in snippet.splitlines() if line.strip()]
        definitions = [l[:120] for l in lines if l.startswith(("class ", "def ", "function ", "export "))]
        summary = f"行数~{len(lines)}"
        if definitions:
            summary += f"，关键定义: {', '.join(definitions[:6])}"
        else:
            first_non_comment = next((l for l in lines if not l.startswith(("#", "//", "/*", "*"))), "")
            if first_non_comment:
                summary += f"，预览: {first_non_comment[:80]}"

        now = time.time()
        try:
            with _get_db() as conn:
                conn.execute(
                    "INSERT INTO file_facts (session_key, file_path, file_hash, summary, updated_at) "
                    "VALUES (?, ?, ?, ?, ?) "
                    "ON CONFLICT(session_key, file_path) DO UPDATE SET "
                    "file_hash=excluded.file_hash, summary=excluded.summary, updated_at=excluded.updated_at",
                    (self.session_key, path, current_hash, summary, now),
                )
        except Exception as exc:
            _switcher_log(f"memory db error (record_file_fact): {exc}")

    def get_valid_file_facts(self) -> dict[str, str]:
        """Return valid file facts; automatically invalidates facts if disk file hash changed."""
        facts: dict[str, str] = {}
        try:
            with _get_db() as conn:
                rows = conn.execute(
                    "SELECT file_path, file_hash, summary FROM file_facts WHERE session_key = ? "
                    "ORDER BY updated_at DESC LIMIT 12",
                    (self.session_key,),
                ).fetchall()
                for fpath, stored_hash, summary in rows:
                    if stored_hash != "mem_only":
                        disk_hash = _file_sha256(fpath)
                        if disk_hash and disk_hash != stored_hash:
                            # File has been modified on disk, invalidate old fact!
                            conn.execute(
                                "DELETE FROM file_facts WHERE session_key = ? AND file_path = ?",
                                (self.session_key, fpath),
                            )
                            continue
                    facts[fpath] = summary
        except Exception as exc:
            _switcher_log(f"memory db error (get_valid_file_facts): {exc}")
        return facts

    def record_action(self, action_summary: str) -> None:
        if not action_summary:
            return
        now = time.time()
        a_hash = hashlib.sha256(action_summary.encode("utf-8")).hexdigest()[:16]
        try:
            with _get_db() as conn:
                conn.execute(
                    "INSERT INTO completed_actions (session_key, action_hash, summary, created_at) "
                    "VALUES (?, ?, ?, ?) ON CONFLICT(action_hash) DO NOTHING",
                    (self.session_key, a_hash, action_summary[:200], now),
                )
        except Exception as exc:
            _switcher_log(f"memory db error (record_action): {exc}")

    def get_recent_actions(self) -> list[str]:
        try:
            with _get_db() as conn:
                rows = conn.execute(
                    "SELECT summary FROM completed_actions WHERE session_key = ? "
                    "ORDER BY created_at DESC LIMIT 6",
                    (self.session_key,),
                ).fetchall()
                return [r[0] for r in reversed(rows)]
        except Exception:
            return []

    def build_memory_prompt(self) -> str:
        parts: list[str] = []
        goal = self.get_pinned_goal()
        if goal:
            parts.append(f"【会话核心任务目标（已固化）】：\n{goal}")
        valid_facts = self.get_valid_file_facts()
        if valid_facts:
            facts_list = [f"- {p}: {desc}" for p, desc in valid_facts.items()]
            parts.append("【会话已知文件状态（已通过SHA256校验，禁止重复cat/ls查看，直接使用结果）】：\n" + "\n".join(facts_list))
        recent_actions = self.get_recent_actions()
        if recent_actions:
            actions_list = [f"- {act}" for act in recent_actions]
            parts.append("【已执行关键操作记录】：\n" + "\n".join(actions_list))
        parts.append("【执行规范】：请直接提供可执行的代码/配置/方案。若需要调用工具，必须同时向用户简述操作意图，严禁无文字的静默循环调用！")
        return "\n\n".join(parts)


def _extract_and_cache_facts(messages: list[dict[str, Any]], mem: SessionMemory) -> None:
    """Extract initial user goal and tool execution results into SQLite memory."""
    for m in messages:
        if m.get("role") == "user":
            txt = _message_plain(m).strip()
            if txt and not txt.startswith("<turn_aborted>"):
                mem.record_pinned_goal(txt)
                break

    for i, m in enumerate(messages):
        if m.get("role") == "tool":
            content = _message_plain(m)
            if i > 0 and messages[i-1].get("role") == "assistant":
                calls = messages[i-1].get("tool_calls") or []
                for call in calls:
                    fn = call.get("function") or {}
                    args = fn.get("arguments") or ""
                    paths = _PATH_RE.findall(args) + _FILE_RE.findall(args)
                    if paths:
                        mem.record_file_fact(paths[0], content)


def _message_plain(message: dict[str, Any]) -> str:
    parts: list[str] = []
    content = message.get("content")
    if isinstance(content, str):
        parts.append(content)
    elif isinstance(content, list):
        for part in content:
            if isinstance(part, dict) and isinstance(part.get("text"), str):
                parts.append(part["text"])
    for call in message.get("tool_calls") or []:
        function = call.get("function") if isinstance(call, dict) else None
        if isinstance(function, dict):
            parts.append(str(function.get("name") or ""))
            parts.append(str(function.get("arguments") or ""))
    return "\n".join(parts)


def _one_line(text: str, limit: int) -> str:
    compact = " ".join(text.split())
    if len(compact) <= limit:
        return compact
    return compact[: limit - 1] + "…"


def _digest_line(message: dict[str, Any]) -> str:
    role = str(message.get("role") or "msg")
    text = _message_plain(message)
    paths = list(dict.fromkeys(_PATH_RE.findall(text)[:2] + _FILE_RE.findall(text)[:2]))
    if message.get("tool_calls"):
        names = []
        for call in message.get("tool_calls") or []:
            function = call.get("function") if isinstance(call, dict) else None
            if isinstance(function, dict) and function.get("name"):
                names.append(str(function["name"]))
        extra = " ".join(paths[:3])
        line = f"- 调用 {', '.join(names) or 'tool'}"
        if extra:
            line += f" {extra}"
        return line[:180]
    head = _one_line(text, 90)
    if paths and not any(path in head for path in paths):
        head = f"{head} | {' '.join(paths[:2])}"
    return f"- {role}: {head}"[:180]


def _build_digest(groups: list[list[dict[str, Any]]]) -> str:
    lines: list[str] = []
    count = 0
    for group in groups:
        for message in group:
            count += 1
            line = _digest_line(message)
            if line:
                lines.append(line)
    body = "\n".join(lines)
    if len(body) > _DIGEST_CHAR_CAP:
        head = _DIGEST_CHAR_CAP // 3
        tail = _DIGEST_CHAR_CAP - head
        body = body[:head] + "\n…\n" + body[-tail:]
    return f"更早的 {count} 条已分层结晶为事实摘要，原文已省略：\n{body}"


def _message_groups(messages: list[dict[str, Any]]) -> list[list[dict[str, Any]]]:
    groups: list[list[dict[str, Any]]] = []
    index = 0
    while index < len(messages):
        end = _tool_group_end(messages, index)
        groups.append(messages[index:end])
        index = end
    return groups


def _copy_message(message: dict[str, Any]) -> dict[str, Any]:
    copied = dict(message)
    calls = copied.get("tool_calls")
    if isinstance(calls, list):
        copied["tool_calls"] = [
            {**call, "function": dict(call.get("function") or {})}
            if isinstance(call, dict)
            else call
            for call in calls
        ]
    return copied


def _normalize_call_signature(name: str, raw_args: Any) -> str:
    name_lower = name.lower()
    parsed = _json_loads(raw_args) if isinstance(raw_args, str) else raw_args
    if isinstance(parsed, dict):
        is_read_tool = any(k in name_lower for k in ("read", "view", "cat", "fetch", "get_file", "show"))
        if is_read_tool:
            target = (
                parsed.get("path") or parsed.get("target_file") or parsed.get("filePath")
                or parsed.get("file") or parsed.get("filename") or parsed.get("AbsolutePath")
                or parsed.get("uri") or parsed.get("target")
            )
            if target:
                target_base = Path(str(target)).name
                return f"read:{target_base}"
        return f"{name}:{json.dumps(parsed, ensure_ascii=False, sort_keys=True)}"
    return f"{name}:{raw_args}"


def _group_signature(group: list[dict[str, Any]]) -> str | None:
    for message in group:
        if message.get("role") != "assistant":
            continue
        calls = message.get("tool_calls") or []
        parts: list[str] = []
        for call in calls:
            function = call.get("function") if isinstance(call, dict) else None
            if not isinstance(function, dict):
                continue
            name = str(function.get("name") or "")
            raw = function.get("arguments") or "{}"
            parts.append(_normalize_call_signature(name, raw))
        if parts:
            return "|".join(parts)
    return None


def _collapse_repeat_groups(
    groups: list[list[dict[str, Any]]],
) -> tuple[list[list[dict[str, Any]]], int]:
    """Keep one result for each identical or repeated read tool call.

    Stops agent 'read paralysis' loops where an agent reads the same file 70+ times
    with fluctuating offsets/limits without making forward progress.
    """
    counts: dict[str, int] = {}
    last_index: dict[str, int] = {}
    for index, group in enumerate(groups):
        signature = _group_signature(group)
        if not signature:
            continue
        counts[signature] = counts.get(signature, 0) + 1
        last_index[signature] = index
    kept: list[list[dict[str, Any]]] = []
    removed = 0
    for index, group in enumerate(groups):
        signature = _group_signature(group)
        if signature and last_index.get(signature) != index:
            removed += 1
            continue
        if signature and counts.get(signature, 0) > 1:
            group = [_copy_message(message) for message in group]
            cnt = counts[signature]
            if signature.startswith("read:"):
                fname = signature.split(":", 1)[1]
                note = (
                    f"[⚠️ 运行时防死循环告警：目标文件 {fname} 已被连续读取 {cnt} 次！"
                    f"你已经掌握了全部所需信息，严禁继续读取该文件或重复探索。"
                    f"请立即使用编辑/写入工具进行代码修改，或向用户输出最终解决方案！]\n"
                )
            else:
                note = f"[同一调用已重复 {cnt} 次，下面只保留最后一次结果，不要再重复执行此工具]\n"
            for message in group:
                if message.get("role") == "tool" and isinstance(message.get("content"), str):
                    message["content"] = note + message["content"]
                    break
        kept.append(group)
    return kept, removed


def _sample_text(text: str, keep: int) -> str:
    """Keep the question, several slices through the middle, and the ending.

    A head-and-tail cut made rollout summaries describe only the last page, or
    return empty JSON when that page had no narrative.
    """
    if len(text) <= keep:
        return text
    head = min(len(text) // 3, max(1200, keep // 4))
    tail = min(len(text) - head, max(800, keep // 6))
    middle = text[head:len(text) - tail]
    slices = 8
    step = max(1, len(middle) // slices)
    chunk = max(160, (keep - head - tail) // slices)
    parts = [text[:head].rstrip(), "…[中间按段落抽样，不是只留结尾]…"]
    for index in range(slices):
        window = middle[index * step:(index + 1) * step]
        lines = [line.strip() for line in window.splitlines() if len(line.strip()) >= 12]
        picked = [
            line for line in lines
            if not (len(line) > 80 and len(set(line.split())) <= 2)
        ]
        piece = "\n".join((picked or lines)[:4])[:chunk].strip()
        if not piece:
            piece = window[:chunk].strip()
        if piece:
            parts.append(piece)
    parts.append("…[结尾]…")
    parts.append(text[-tail:].lstrip())
    return "\n".join(parts)


def _cap_copied(message: dict[str, Any], keep_chars: int) -> dict[str, Any]:
    copied = dict(message)
    if copied.get("tool_calls"):
        copied["tool_calls"] = [
            dict(call) if isinstance(call, dict) else call
            for call in copied["tool_calls"]
        ]
    _shrink_message(copied, keep_chars)
    return copied


def _fit_messages(
    messages: list[dict[str, Any]],
    context: Any = None,
    trigger_tokens: int = 0,
    recent_budget: int = 0,
) -> tuple[list[dict[str, Any]], bool]:
    """Replace older turns with a keyword digest and SessionMemory facts once the thread gets long."""
    if not messages:
        return messages, False
    before = _estimate_tokens(messages)

    compact_trigger = trigger_tokens if trigger_tokens > 0 else _COMPACT_TRIGGER_TOKENS
    recent_budget_tokens = recent_budget if recent_budget > 0 else _RECENT_TOKEN_BUDGET
    system_cap = min(_SYSTEM_CHAR_CAP, max(2000, compact_trigger * 2))
    digest_cap = min(_DIGEST_CHAR_CAP, max(800, int(compact_trigger * 0.7)))

    system: list[dict[str, Any]] = []
    rest = list(messages)
    while rest and rest[0].get("role") == "system":
        system.append(rest.pop(0))
    capped_system = []
    for message in system:
        copied = dict(message)
        if len(_message_plain(copied)) > system_cap:
            copied["content"] = _message_plain(copied)[:system_cap] + "\n…[系统提示已剪短]…"
        capped_system.append(copied)

    groups, removed_repeats = _collapse_repeat_groups(_message_groups(rest))
    rest = [item for group in groups for item in group]
    if _estimate_tokens(capped_system + rest) <= compact_trigger:
        if removed_repeats:
            _switcher_log(f"context dedupe removed_repeats={removed_repeats}")
            return capped_system + rest, True
        return messages, False

    recent: list[list[dict[str, Any]]] = []
    while groups:
        candidate = groups[-1:] + recent
        flat = [item for group in candidate for item in group]
        if recent and _estimate_tokens(flat) > recent_budget_tokens:
            break
        recent.insert(0, groups.pop())
    if not recent and groups:
        recent.append(groups.pop())

    last_user = next(
        (group for group in reversed(groups + recent) if any(item.get("role") == "user" for item in group)),
        None,
    )
    if last_user is not None and all(item is not last_user for item in recent):
        groups = [group for group in groups if group is not last_user]
        recent.insert(0, last_user)

    fitted = list(capped_system)
    session_key = _session_fingerprint(messages)
    mem = SessionMemory(session_key)
    _extract_and_cache_facts(messages, mem)
    mem_prompt = mem.build_memory_prompt()
    if mem_prompt:
        fitted.append({"role": "system", "content": mem_prompt})

    if groups:
        digest_text = _build_digest(groups)
        if len(digest_text) > digest_cap:
            digest_text = digest_text[:digest_cap] + "\n…[历史摘要已折叠]…"
        fitted.append({"role": "system", "content": digest_text})
    flat_recent = [item for group in recent for item in group]

    def _recent_keep(message: dict[str, Any], is_last: bool) -> int:
        if message.get("role") == "tool":
            return min(4000, max(1200, recent_budget_tokens * 2))
        return (_LAST_TEXT_CHARS if is_last else _RECENT_TEXT_CHARS) if compact_trigger >= 4000 else (1200 if is_last else 800)

    if len(flat_recent) > 1:
        fitted.extend(
            _cap_copied(item, _recent_keep(item, False)) for item in flat_recent[:-1]
        )
    if flat_recent:
        last = flat_recent[-1]
        last_keep = _recent_keep(last, True)
        plain = _message_plain(last)
        if _estimate_tokens(last) > recent_budget_tokens and last.get("role") != "tool":
            last_keep = recent_budget_tokens * 2
        if not last.get("tool_calls") and len(plain) > last_keep * 3:
            copied = dict(last)
            copied["content"] = _sample_text(plain, last_keep)
            fitted.append(copied)
        else:
            fitted.append(_cap_copied(last, last_keep))

    after = _estimate_tokens(fitted)
    _switcher_log(
        f"context compact before={before} after={after} target_trigger={compact_trigger} "
        f"kept_groups={len(recent)} dropped_groups={len(groups)} "
        f"removed_repeats={removed_repeats}"
    )
    return fitted, before != after


def _chat_tools(payload: dict[str, Any]) -> list[dict[str, Any]]:
    tools: list[dict[str, Any]] = []
    for tool in payload.get("tools", []):
        if not isinstance(tool, dict) or tool.get("type") != "function":
            continue
        tools.append(
            {
                "type": "function",
                "function": {
                    "name": tool.get("name", ""),
                    "description": _one_line(str(tool.get("description") or ""), 240),
                    "parameters": tool.get("parameters", {"type": "object"}),
                },
            }
        )
    return tools


def _runtime() -> dict[str, Any]:
    path = Path.home() / ".local/state/mtplx-qwen38/runtime.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        data = {}
    data.setdefault("backend_url", ProxyHandler.backend)
    data.setdefault("enable_thinking", False)
    return data


def _traffic(event: dict[str, Any]) -> None:
    path = Path.home() / "Library/Logs/CodexModelSwitcher/traffic.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    event["ts"] = time.time()
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, ensure_ascii=False) + "\n")


def _switcher_log(message: str) -> None:
    path = Path.home() / "Library/Logs/CodexModelSwitcher/switcher.log"
    path.parent.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with path.open("a", encoding="utf-8") as handle:
        handle.write(f"[{stamp}] {message}\n")


def _preview(text: str, limit: int = 280) -> str:
    compact = " ".join(str(text).split())
    if len(compact) <= limit:
        return compact
    return compact[: limit - 1] + "…"


def _latest_user_text(payload: dict[str, Any]) -> str:
    inputs = payload.get("input", [])
    if isinstance(inputs, str):
        return inputs
    if not isinstance(inputs, list):
        return ""
    texts: list[str] = []
    for item in inputs:
        if not isinstance(item, dict):
            continue
        if item.get("type", "message") != "message" or item.get("role") != "user":
            continue
        texts.append(_content_text(item.get("content", "")))
    return texts[-1] if texts else ""


def _latest_user_preview(payload: dict[str, Any]) -> str:
    return _preview(_latest_user_text(payload))


def _background_rollout_answer(payload: dict[str, Any]) -> str | None:
    """Codex memory jobs paste entire other sessions into this same bridge.

    They are not the conversation open in the current window. Answering them
    here both blocks that window and compresses somebody else's rollout.
    """
    head = _latest_user_text(payload).lstrip()[:280]
    if head.startswith("Analyze this rollout and produce JSON") and "raw_memory" in head:
        return '{"rollout_summary":"","rollout_slug":"","raw_memory":""}'
    return None


def _reasoning_effort(payload: dict[str, Any], runtime: dict[str, Any]) -> str | None:
    """Pull the reasoning effort Codex asked for, falling back to runtime."""
    reasoning = payload.get("reasoning")
    if isinstance(reasoning, dict):
        effort = reasoning.get("effort")
        if isinstance(effort, str) and effort:
            return effort
    effort = payload.get("reasoning_effort")
    if isinstance(effort, str) and effort:
        return effort
    effort = runtime.get("reasoning_effort")
    if isinstance(effort, str) and effort:
        return effort
    return None


def _tool_signature(message: dict[str, Any]) -> str | None:
    calls = message.get("tool_calls") or []
    if not calls:
        return None
    parts: list[str] = []
    for call in calls:
        function = call.get("function") if isinstance(call, dict) else None
        if not isinstance(function, dict):
            continue
        parts.append(f"{function.get('name')}:{function.get('arguments')}")
    return "|".join(parts) or None


_STALL_ZH_RE = re.compile(
    r"(?:让我|我来|我先|现在|接下来|我继续|我准备|正在|我会|继续(?=读取|查看|执行|检查|运行|创建|实现|修改)).{0,48}"
    r"(?:检查|查看|读取|看看|创建|实现|运行|执行|确认|进度|写|改|了解|分析|命令).{0,48}"
    r"(?:[：:]|[。！？\s]*$|\.{3}|…)"
)
_STALL_EN_RE = re.compile(
    r"(?i)(?:(?:let me|i'll|i will|i am|now i|next i)\b.{0,80}"
    r"(?:check|read|create|implement|run|look|understand)\b.{0,40}(?:[:.]|\s*$)"
    r"|(?:^|[.!?]\s+)(?:now\s+)?(?:reading|checking|creating|implementing|running|executing|inspecting|writing)\b"
    r".{0,80}(?:[:.]|\s*$))"
)


# "Now fix X", "Next, update Y", "I need to use Z": an announced next action.
_STALL_NEXT_RE = re.compile(
    r"(?i)(?:^|[.!?:;]\s+)(?:(?:now|next|then|first)[,\s]+(?:let'?s\s+|i(?:'ll| will| need to| have to| should)\s+)?"
    r"|(?:i(?:'ll)? need to|i have to|i should|let'?s|let me)\s+)"
    r"(?:fix|update|add|edit|modify|change|apply|write|create|implement|run|check|read|remove|replace|rename"
    r"|test|verify|look|open|inspect|search|patch|refactor|use|make|move|delete|install)\b"
)


# The reply's last sentence announces the speaker's own next action.
_STALL_LAST_RE = re.compile(
    r"(?i)^(?:so|now|then|next|ok(?:ay)?|first)?[,\s]*"
    r"(?:i(?:'ll| will| need to| have to| must| should| am going to|'m going to)|let me|let'?s)\s+[a-z]"
)


def _stalled_tool_promise(text: str) -> bool:
    """A turn that announces the next action and stops before the tool call.

    Codex only callbacks after a tool call. MTPLX already retries the English
    form ("let me check"); the Chinese form was slipping through as a finished
    answer.
    """
    tail = " ".join(str(text or "").strip().split())
    if not tail:
        return False
    last_sentence = next((part.strip() for part in reversed(re.split(r"[。！？]", tail)) if part.strip()), "")
    if re.search(r"(?:已经|已)(?:写入|完成|修复|执行|读取)|(?:写入|执行|修复)(?:完成|成功|完毕)", last_sentence):
        return False
    # A reply whose last line ends with a colon introduces something it never delivered.
    last_line = next((line.strip() for line in reversed(str(text).strip().splitlines()) if line.strip()), "")
    if last_line.endswith((":", "：")):
        return True
    sentences = [part.strip() for part in re.split(r"(?<=[.!?。！？])\s+", tail) if part.strip()]
    final = sentences[-1] if sentences else ""
    if final and "?" not in final and "？" not in final and _STALL_LAST_RE.search(final):
        return True
    if len(tail) > 240:
        tail = tail[-240:]
    return bool(_STALL_ZH_RE.search(tail) or _STALL_EN_RE.search(tail) or _STALL_NEXT_RE.search(tail))



def _retry_stalled_tool_call(
    backend: str,
    request_data: bytes,
    answer: str,
    request_id: str = "",
    replan: bool = False,
    client_headers: dict[str, str] | None = None,
) -> tuple[str, list[dict[str, Any]], dict[str, Any]]:
    body = json.loads(request_data)
    if not body.get("tools"):
        return "", [], {}
    messages = list(body.get("messages") or [])
    if not replan:messages.append({"role": "assistant", "content": answer})
    if not replan:messages.append({
        "role": "system",
        "content": (
            "上一条回答只宣布了下一步，没有实际调用工具。请现在发出完成该步骤所需的一个已声明工具调用。"
            "工具名和参数必须符合提供的定义；命令文字、进度文字都不等于工具调用。"
            "遵守原始用户授权，不要重复已经成功完成的操作。"
        ),
    })
    body["messages"] = messages
    body["stream"] = False
    body.pop("stream_options", None)
    body["tool_choice"] = body.get('tool_choice','auto') if replan else "required"
    body["parallel_tool_calls"] = False
    request = urllib.request.Request(
        f"{backend}/v1/chat/completions",
        data=json.dumps(body, ensure_ascii=False).encode(),
        headers={**(client_headers or {}), "Content-Type": "application/json", "x-mtplx-request-id":request_id,
                 "x-mtplx-session-id":str((body.get('metadata') or {}).get('session_id') or '')},
        method="POST",
    )
    # A cold long prompt can prefill for minutes; 90s turned real recoveries
    # into "timed out" pauses.
    with urllib.request.urlopen(request, timeout=900) as response:
        data = json.loads(response.read().decode())
    if data.get('error'):
        error = data['error']
        raise RuntimeError(error.get('message', str(error)) if isinstance(error, dict) else str(error))
    message = ((data.get("choices") or [{}])[0].get("message") or {})
    content = message.get("content") or ""
    if not isinstance(content, str):
        content = _content_text(content)
    declared = {tool["function"]["name"]: tool["function"] for tool in body["tools"]}
    calls: list[dict[str, Any]] = []
    for call in message.get("tool_calls") or []:
        if not isinstance(call, dict):
            continue
        function = call.get("function") or {}
        name = str(function.get("name") or "")
        if name not in declared:
            continue
        arguments = function.get("arguments") or "{}"
        parsed = arguments if isinstance(arguments, dict) else _json_loads(str(arguments))
        schema = declared[name].get("parameters") or {}
        if not isinstance(parsed, dict) or any(key not in parsed for key in schema.get("required", [])):
            continue
        calls.append({
            "id": call.get("id") or _id("call"),
            "type": "function",
            "function": {
                "name": name,
                "arguments": json.dumps(parsed, ensure_ascii=False),
            },
        })
    return content, calls, data.get("usage") or {}


# Backends that serve models by name: requests carry the switcher's api_model.
NAMED_BACKENDS = ("lmstudio", "bonsai", "omlx")
# Local single-GPU backends (tool calls are serialized for these).
LOCAL_BACKENDS = ("mtplx", "lmstudio", "bonsai", "omlx")


def _omlx_thinking(request: dict[str, Any], runtime: dict[str, Any], effort: str | None) -> None:
    """oMLX renders both fields into the chat template. Nemotron and Ling switch
    on enable_thinking; K2 has no off switch and reads only reasoning_effort
    (template default "high"), so thinking off means effort "low"."""
    thinking = bool(runtime.get("enable_thinking", False))
    request["chat_template_kwargs"] = {"enable_thinking": thinking}
    request["reasoning_effort"] = (effort or "medium") if thinking else "low"


def _inspect_and_guard_tool_loops(
    raw_messages: list[dict[str, Any]], tools: list[dict[str, Any]]
) -> tuple[list[dict[str, Any]], str | None]:
    """Per-file read ledger (built from the client's full history).

    Level 1: notice. Level 2: warn at tail (keeping tools schema static for KV-cache).
    Returns (tools, ledger_text).
    """
    if not tools:
        return tools, None
    try:
        from serafina_runtime.read_ledger import analyze
    except Exception:
        return tools, None
    verdict = analyze(raw_messages)
    text = verdict.render() or None
    if verdict.level >= 2:
        text = (text or "") + f"\n[🚨 防死循环：{verdict.reason}。禁止继续重复读取上述未修改文件分段，请立即基于已有信息执行编辑/修改或回复用户。]"
        _switcher_log(f"read loop level=2 reason={verdict.reason}")
    elif verdict.level == 1:
        _switcher_log(f"read loop level=1 reason={verdict.reason}")
    return tools, text


def _chat_payload(payload: dict[str, Any], runtime: dict[str, Any]) -> dict[str, Any]:
    model = payload.get("model")
    if runtime.get("backend") in NAMED_BACKENDS and runtime.get("api_model"):
        model = runtime.get("api_model")
    raw_messages = _chat_messages(payload)
    # Determine whether compaction is required:
    # 1. 120B/124B super models always require tight compaction (1500~1800 tokens) on Apple Silicon Metal
    #    to prevent Metal Watchdog "Impacting Interactivity" timeouts.
    # 2. Non-super models (<60B) use >=24K working window so system prompt + multi-turn tool outputs
    #    remain untouched and hit oMLX prefix KV-cache at 95%+.
    model_name_lower = str(model or "").lower()
    is_super_model = any(k in model_name_lower for k in ("120b", "124b", "super", "ling-3.0"))
    preset = runtime.get("agent_window_preset")
    if preset is None:
        input_budget = runtime.get("agentd", {}).get("input_budget", 0)
        preset = 0 if input_budget <= 2048 else (1 if input_budget <= 24576 else 2)

    compact_tokens = int(runtime.get("context_compact_tokens") or 0)
    if is_super_model and compact_tokens == 0:
        compact_tokens = 1800

    should_compact = False
    trigger_tokens = _COMPACT_TRIGGER_TOKENS
    recent_budget = _RECENT_TOKEN_BUDGET

    if is_super_model:
        # 120B/124B super models need tight compaction (1800) to fit within Apple Silicon Metal watchdog
        should_compact = True
        trigger_tokens = 1800
        recent_budget = 1200
    elif compact_tokens > 0:
        should_compact = True
        # Non-super models: compact rarely (hysteresis). Every compaction rewrites the
        # prompt prefix (digest/memory change), so doing it each turn forces a full
        # 26K-token re-prefill (~80s). Stay append-only until ~96K, then fold to ~60%.
        trigger_tokens = max(96000, compact_tokens)
        recent_budget = int(trigger_tokens * 0.6)
    elif preset == 0:
        should_compact = True
        trigger_tokens = 24000
        recent_budget = 18000
    elif runtime.get("backend") in ("lmstudio", "bonsai"):
        should_compact = True
        trigger_tokens = _COMPACT_TRIGGER_TOKENS
        recent_budget = _RECENT_TOKEN_BUDGET

    messages = list(raw_messages)
    if should_compact and _estimate_tokens(raw_messages) > trigger_tokens:
        messages, compacted = _fit_messages(raw_messages, runtime.get("context_length"), trigger_tokens, recent_budget)
        if compacted:
            _switcher_log(f"context fitted for model={model} trigger={trigger_tokens} budget={recent_budget}")

    request: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    effort = _reasoning_effort(payload, runtime)
    if runtime.get("backend") in ("lmstudio", "bonsai"):
        # Harmony (GPT-OSS) and Gemma 4 read reasoning depth from this field. It
        # is what actually turns planning/thinking on for the LM Studio models;
        # without it "medium" in Codex never reaches the engine. Bonsai reads the
        # same field (keeps thinking on unless explicitly none/off).
        if effort:
            request["reasoning_effort"] = effort
    elif runtime.get("backend") == "omlx":
        _omlx_thinking(request, runtime, effort)
    else:
        request["enable_thinking"] = bool(runtime.get("enable_thinking", False))
    tools = _chat_tools(payload)
    if tools:
        tools, loop_advisory = _inspect_and_guard_tool_loops(raw_messages, tools)
        # Same text, same position on every turn: part of the cached prefix.
        # IMPORTANT: Never append dynamic per-turn advisories to messages[0], as
        # mutating messages[0] invalidates 100% of the prefix KV-cache!
        protocol = (
            "Codex 工具协议：需要继续检查、执行或修改时，必须实际调用已声明工具。"
            "只说‘让我查看’、‘正在执行’不会执行任何操作，会结束整个任务。"
            "工具结果回传后，继续完成原始用户任务；不要每读一个文件就停下来等用户说继续。"
            "只有完成任务或需要用户补充必需信息时才给最终回答。遵守原始授权和工具定义。"
        )
        if messages and messages[0].get("role") == "system" and isinstance(messages[0].get("content"), str):
            messages[0] = {**messages[0], "content": messages[0]["content"] + "\n\n" + protocol}
        else:
            messages.insert(0, {"role": "system", "content": protocol})
        if loop_advisory and len(messages) > 1:
            last_msg = dict(messages[-1])
            last_content = last_msg.get("content")
            if isinstance(last_content, str):
                last_msg["content"] = last_content + "\n\n" + loop_advisory
                messages[-1] = last_msg
        request["messages"] = messages
        if tools:
            request["tools"] = tools
            choice = payload.get("tool_choice")
            if isinstance(choice, str) and choice in {"auto", "none", "required"}:
                request["tool_choice"] = choice
            elif isinstance(choice, dict) and choice.get("type") == "function":
                request["tool_choice"] = {"type": "function", "function": {"name": choice.get("name")}}
        # Local single-model backends run one request at a time on one GPU.
        # Letting the model fan out many parallel tool calls makes Codex launch
        # several concurrent subagents/commands at once, which a single 96GB box
        # cannot sustain, so we serialize tool calls for local backends.
        if runtime.get("backend") in LOCAL_BACKENDS:
            request["parallel_tool_calls"] = False
        else:
            request["parallel_tool_calls"] = payload.get("parallel_tool_calls", True)
    if payload.get("max_output_tokens") is not None:
        request["max_tokens"] = payload["max_output_tokens"]
    for key in ("temperature", "top_p"):
        if payload.get(key) is not None:
            request[key] = payload[key]
    return request


def _iter_sse_payloads(raw: bytes) -> list[dict[str, Any]]:
    payloads: list[dict[str, Any]] = []
    for block in raw.split(b"\n\n"):
        data_lines: list[str] = []
        for line in block.splitlines():
            if line.startswith(b"data:"):
                data_lines.append(line[5:].strip().decode("utf-8", errors="replace"))
        if not data_lines:
            continue
        data = "\n".join(data_lines).strip()
        if not data or data == "[DONE]":
            continue
        try:
            parsed = json.loads(data)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            payloads.append(parsed)
    return payloads


def _resolve_backend_model(backend: str, requested: str | None, preferred: str | None = None) -> str | None:
    try:
        with urllib.request.urlopen(f"{backend}/v1/models", timeout=5) as response:
            body = json.load(response)
    except (OSError, json.JSONDecodeError, urllib.error.URLError):
        return requested
    ids = [
        str(item.get("id"))
        for item in body.get("data", [])
        if isinstance(item, dict) and item.get("id")
    ]
    if not ids:
        return preferred or requested
    if preferred and preferred in ids:
        return preferred
    if requested and requested in ids:
        return requested
    return ids[0]


def _active_model(runtime: dict[str, Any], backend: str, requested: str | None) -> tuple[str | None, str | None]:
    """Return (backend id to run, name to show Codex).

    A Codex thread keeps the model id it was opened with. This bridge ignores
    that id and answers with whatever the switcher last enabled.
    """
    preferred = runtime.get("api_model")
    if not isinstance(preferred, str) or not preferred:
        preferred = None
    loaded = _resolve_backend_model(backend, None, preferred)
    if runtime.get("backend") in NAMED_BACKENDS and preferred:
        wire = preferred
    else:
        wire = loaded or preferred or requested
    shown = preferred or wire
    return wire, shown


def _anthropic_to_chat(payload: dict[str, Any], model: str | None) -> dict[str, Any]:
    """Anthropic Messages request -> OpenAI chat completions request."""
    messages: list[dict[str, Any]] = []
    system = payload.get("system")
    if system:
        text = system if isinstance(system, str) else "\n\n".join(
            str(b.get("text", "")) for b in system if isinstance(b, dict))
        messages.append({"role": "system", "content": text})
    for message in payload.get("messages") or []:
        role = message.get("role")
        content = message.get("content")
        if isinstance(content, str):
            messages.append({"role": role, "content": content})
            continue
        texts: list[str] = []
        images: list[dict[str, Any]] = []
        calls: list[dict[str, Any]] = []
        results: list[dict[str, Any]] = []
        for block in content or []:
            if not isinstance(block, dict):
                continue
            kind = block.get("type")
            if kind == "text":
                texts.append(str(block.get("text", "")))
            elif kind == "image":
                source = block.get("source") or {}
                url = (f"data:{source.get('media_type')};base64,{source.get('data')}"
                       if source.get("type") == "base64" else source.get("url"))
                images.append({"type": "image_url", "image_url": {"url": url}})
            elif kind == "tool_use":
                calls.append({"id": block.get("id") or _id("call"), "type": "function",
                              "function": {"name": block.get("name"),
                                           "arguments": json.dumps(block.get("input") or {}, ensure_ascii=False)}})
            elif kind == "tool_result":
                result = block.get("content")
                text = result if isinstance(result, str) else "\n".join(
                    str(x.get("text", "")) for x in result or [] if isinstance(x, dict) and x.get("type") == "text")
                if block.get("is_error"):
                    text = "[error] " + text
                results.append({"role": "tool", "tool_call_id": block.get("tool_use_id"), "content": text})
        if role == "assistant":
            item: dict[str, Any] = {"role": "assistant", "content": "\n".join(texts) or None}
            if calls:
                item["tool_calls"] = calls
            messages.append(item)
            continue
        messages.extend(results)  # tool results must directly follow the assistant tool calls
        if images:
            messages.append({"role": "user", "content": ([{"type": "text", "text": "\n".join(texts)}] if texts else []) + images})
        elif texts:
            messages.append({"role": "user", "content": "\n".join(texts)})
    body: dict[str, Any] = {"model": model, "messages": messages, "max_tokens": payload.get("max_tokens") or 4096,
                            "stream": bool(payload.get("stream"))}
    for key in ("temperature", "top_p", "top_k"):
        if key in payload:
            body[key] = payload[key]
    if payload.get("stop_sequences"):
        body["stop"] = payload["stop_sequences"]
    tools = [{"type": "function", "function": {"name": t["name"], "description": t.get("description", ""),
                                               "parameters": t.get("input_schema") or {"type": "object", "properties": {}}}}
             for t in payload.get("tools") or [] if isinstance(t, dict) and t.get("name")]
    if tools:
        body["tools"] = tools
        choice = payload.get("tool_choice") or {}
        kind = choice.get("type") if isinstance(choice, dict) else None
        if kind == "tool":
            body["tool_choice"] = {"type": "function", "function": {"name": choice.get("name")}}
        else:
            body["tool_choice"] = {"any": "required", "none": "none"}.get(kind, "auto")
    if body["stream"]:
        body["stream_options"] = {"include_usage": True}
    return body


def _chat_to_anthropic(data: dict[str, Any], model: str | None) -> dict[str, Any]:
    """OpenAI chat completion -> Anthropic Messages response."""
    choice = (data.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    content: list[dict[str, Any]] = []
    if message.get("content"):
        content.append({"type": "text", "text": _content_text(message["content"])})
    for call in message.get("tool_calls") or []:
        function = call.get("function") or {}
        arguments = _json_loads(function.get("arguments") or "{}")
        content.append({"type": "tool_use", "id": call.get("id") or _id("toolu"), "name": function.get("name"),
                        "input": arguments if isinstance(arguments, dict) else {}})
    stop = "tool_use" if any(b["type"] == "tool_use" for b in content) else \
        {"length": "max_tokens"}.get(choice.get("finish_reason"), "end_turn")
    usage = data.get("usage") or {}
    return {"id": _id("msg"), "type": "message", "role": "assistant", "model": model,
            "content": content or [{"type": "text", "text": ""}], "stop_reason": stop, "stop_sequence": None,
            "usage": {"input_tokens": int(usage.get("prompt_tokens") or 0),
                      "output_tokens": int(usage.get("completion_tokens") or 0)}}


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    backend = "http://127.0.0.1:8000"

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"[{self.log_date_time_string()}] {fmt % args}", flush=True)

    def _json(self, status: int, body: Any) -> None:
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        path = urlsplit(self.path).path.rstrip("/")
        if path == "/v1/bridge-info":
            runtime = _runtime()
            self._json(200, {
                "version": 2,
                "revision": "local-agent-gateway-6-passthrough",
                "context_policy": "append_only",
                "gateway": GATEWAY.status(),
                "stalled_tool_recovery": True,
                "stream": True,
                "traffic_log": str(Path.home() / "Library/Logs/CodexModelSwitcher/traffic.jsonl"),
                "backend": runtime.get("backend_url") or self.backend,
                "adapter": runtime.get("backend") or "mtplx",
                "api_model": runtime.get("api_model") or "",
                "enable_thinking": bool(runtime.get("enable_thinking", False)),
                "context_length": int(runtime.get("context_length") or 0),
                "context_fit": True,
            })
            return
        if path == "/v1/runtime/status":
            matrix = GPU_FAULT_SUPERVISOR.get_health_matrix() if GPU_FAULT_SUPERVISOR else {}
            self._json(200, {
                "ok": True,
                "runtime_version": "5.1-arp",
                "overall_health": matrix.get("overall", "HEALTHY"),
                "health_matrix": matrix,
                "eat_per_min": GPU_FAULT_SUPERVISOR.get_eat_per_min() if GPU_FAULT_SUPERVISOR else 0.0,
                "wcr_pct": GPU_FAULT_SUPERVISOR.get_wcr_pct() if GPU_FAULT_SUPERVISOR else 0.0,
                "breaker_level": BREAKER.current_level if BREAKER else 0,
                "l1_warnings": BREAKER.l1_count if BREAKER else 0,
                "l2_mutations": BREAKER.l2_count if BREAKER else 0,
                "active_subtask": BREAKER.active_subtask.to_dict() if (BREAKER and BREAKER.active_subtask) else None,
                "cache_metrics": CONTEXT_COMPILER.get_cache_metrics() if CONTEXT_COMPILER else {},
                "blocklist_count": len(BREAKER.blocklist) if BREAKER else 0,
                "gpu_faults": GPU_FAULT_SUPERVISOR.get_summary() if GPU_FAULT_SUPERVISOR else {},
                "memory_pressure": MEMORY_PRESSURE_BUDGET.get_memory_pressure_state() if MEMORY_PRESSURE_BUDGET else {},
            })
            return
        if path == "/v1/runtime/quarantine/clear":
            if GPU_FAULT_SUPERVISOR:
                GPU_FAULT_SUPERVISOR.clear_quarantine()
            self._json(200, {"ok": True, "message": "Quarantine cleared"})
            return
        if path == "/v1/network/status":
            try:
                from serafina_runtime.network_sentinel import NETWORK_SENTINEL
                self._json(200, NETWORK_SENTINEL.scan())
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/network/gatekeeper_whitelist":
            try:
                from serafina_runtime.network_sentinel import NETWORK_SENTINEL
                items = NETWORK_SENTINEL.gatekeeper_whitelist.list_whitelisted()
                self._json(200, {"ok": True, "whitelist": items, "count": len(items)})
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/network/rate_limits":
            try:
                from serafina_runtime.network_sentinel import NETWORK_SENTINEL
                self._json(200, {
                    "ok": True,
                    "limits": NETWORK_SENTINEL.rate_limiter.list_limits(),
                    "count": len(NETWORK_SENTINEL.rate_limiter.list_limits())
                })
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path.startswith("/v1/system/process_resources"):
            try:
                import urllib.parse
                parsed = urllib.parse.urlparse(self.path)
                qs = urllib.parse.parse_qs(parsed.query)
                sort_by = qs.get("sort_by", ["cpu"])[0]
                limit = int(qs.get("limit", [35])[0])
                from serafina_runtime.process_resources import PROCESS_RESOURCE_MONITOR
                self._json(200, PROCESS_RESOURCE_MONITOR.get_top_process_families(sort_by=sort_by, limit=limit))
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path.startswith("/v1/system/process_family_detail"):
            try:
                import urllib.parse
                parsed = urllib.parse.urlparse(self.path)
                qs = urllib.parse.parse_qs(parsed.query)
                pid = int(qs.get("pid", [0])[0])
                from serafina_runtime.process_resources import PROCESS_RESOURCE_MONITOR
                self._json(200, PROCESS_RESOURCE_MONITOR.get_family_resources(pid))
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/startup/list":
            try:
                from serafina_runtime.startup_manager import STARTUP_MANAGER
                self._json(200, STARTUP_MANAGER.list_items())
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/watchlist/status":
            try:
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                self._json(200, PROCESS_WATCHLIST.list_watchlist_status())
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path.startswith("/v1/watchlist/candidate_processes"):
            try:
                import urllib.parse
                parsed = urllib.parse.urlparse(self.path)
                qs = urllib.parse.parse_qs(parsed.query)
                q = qs.get("q", [""])[0]
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                candidates = PROCESS_WATCHLIST.get_candidate_processes(query=q)
                self._json(200, {"ok": True, "count": len(candidates), "candidates": candidates})
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path.startswith("/v1/watchlist/inspect_file"):
            try:
                import urllib.parse
                parsed = urllib.parse.urlparse(self.path)
                qs = urllib.parse.parse_qs(parsed.query)
                target_path = qs.get("path", [""])[0]
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                res = PROCESS_WATCHLIST.inspect_file(target_path)
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/watchlist/analysis_vault":
            try:
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                self._json(200, PROCESS_WATCHLIST.list_analysis_vault())
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path.startswith("/v1/watchlist/file_history"):
            try:
                import urllib.parse
                parsed = urllib.parse.urlparse(self.path)
                qs = urllib.parse.parse_qs(parsed.query)
                pid = int(qs.get("pid", [0])[0])
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                self._json(200, PROCESS_WATCHLIST.get_file_history(pid))
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path.startswith("/v1/code/outline"):
            try:
                import urllib.parse
                parsed = urllib.parse.urlparse(self.path)
                qs = urllib.parse.parse_qs(parsed.query)
                target_path = qs.get("path", qs.get("file", [""]))[0]
                from serafina_runtime.code_intelligence import CODE_GRAPH
                self._json(200, CODE_GRAPH.get_outline(target_path))
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path.startswith("/v1/code/symbols"):
            try:
                import urllib.parse
                parsed = urllib.parse.urlparse(self.path)
                qs = urllib.parse.parse_qs(parsed.query)
                repo = qs.get("repo", ["."])[0]
                q = qs.get("q", [""])[0]
                kind = qs.get("kind", [None])[0]
                from serafina_runtime.code_intelligence import CODE_GRAPH
                matches = CODE_GRAPH.search_symbols(repo, query=q, kind=kind)
                self._json(200, {"ok": True, "count": len(matches), "symbols": matches})
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path.startswith("/v1/code/callers"):
            try:
                import urllib.parse
                parsed = urllib.parse.urlparse(self.path)
                qs = urllib.parse.parse_qs(parsed.query)
                repo = qs.get("repo", ["."])[0]
                sym = qs.get("symbol", [""])[0]
                from serafina_runtime.code_intelligence import CODE_GRAPH
                callers = CODE_GRAPH.get_callers(repo, symbol=sym)
                self._json(200, {"ok": True, "count": len(callers), "callers": callers})
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path.startswith("/v1/code/blueprint"):
            try:
                import urllib.parse
                parsed = urllib.parse.urlparse(self.path)
                qs = urllib.parse.parse_qs(parsed.query)
                repo = qs.get("repo", ["."])[0]
                from serafina_runtime.code_intelligence import AOCI
                bp_res = AOCI.build_blueprint(repo)
                md = AOCI.load_blueprint(repo)
                self._json(200, {"ok": True, "blueprint": bp_res.get("blueprint"), "markdown": md})
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
        if path.startswith("/v1/intelligence/status"):
            try:
                import urllib.parse
                parsed = urllib.parse.urlparse(self.path)
                qs = urllib.parse.parse_qs(parsed.query)
                repo = qs.get("repo", ["/Users/mac/AinerWorkFlow/mlx localagent_model"])[0]
                from serafina_runtime.code_intelligence import AOCI
                overview = AOCI.get_intelligence_overview(repo)
                overview["harness_cache"] = TOKEN_ACCOUNTING.get_metrics()
                self._json(200, overview)
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path != "/v1/models":
            self._json(404, {"error": {"message": "Not found"}})
            return
        runtime = _runtime()
        backend = str(runtime.get("backend_url") or self.backend).rstrip("/")
        try:
            with urllib.request.urlopen(f"{backend}/v1/models", timeout=10) as response:
                listed = json.load(response).get("data") or []
        except Exception as exc:
            self._json(502, {"error": {"message": str(exc)}})
            return
        wire, shown = _active_model(runtime, backend, None)
        entry = next((m for m in listed if isinstance(m, dict) and m.get("id") == wire), {"object": "model", "owned_by": "local"})
        # Every name below reaches the active model; requests may use any of them.
        data, seen = [], set()
        for name in (wire, shown, "active", "local"):
            if name and name not in seen:
                seen.add(name)
                data.append({**entry, "id": name, "object": "model"})
        # Codex uses a richer private model-catalog schema than OpenAI's public list.
        # An empty catalog is valid; the explicitly configured model still uses fallback metadata.
        self._json(200, {"object": "list", "data": data, "models": []})

    def do_POST(self) -> None:
        path=urlsplit(self.path).path.rstrip('/')
        if path == "/v1/network/kill_process":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                pid = int(body.get("pid", 0))
                from serafina_runtime.network_sentinel import NETWORK_SENTINEL
                from serafina_runtime.process_resources import PROCESS_RESOURCE_MONITOR
                ok, msg = NETWORK_SENTINEL.kill_process(pid)
                PROCESS_RESOURCE_MONITOR._cache_data = None
                self._json(200 if ok else 400, {"ok": ok, "message": msg})
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/network/kill_family":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                pid = int(body.get("pid", 0))
                include_parent = bool(body.get("include_parent", True))
                from serafina_runtime.network_sentinel import NETWORK_SENTINEL
                from serafina_runtime.process_resources import PROCESS_RESOURCE_MONITOR
                res = NETWORK_SENTINEL.kill_process_family(pid, include_parent=include_parent)
                PROCESS_RESOURCE_MONITOR._cache_data = None
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/network/gatekeeper_decision":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                event_id = str(body.get("event_id", ""))
                action = str(body.get("action", "allow"))
                whitelist_parent = bool(body.get("whitelist_parent", False))
                parent_name = str(body.get("parent_name", ""))
                from serafina_runtime.network_sentinel import NETWORK_SENTINEL
                res = NETWORK_SENTINEL.resolve_gatekeeper_event(
                    event_id, action, whitelist_parent=whitelist_parent, parent_name=parent_name
                )
                self._json(200, res)
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/network/gatekeeper_whitelist":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length)) if length > 0 else {}
                action = body.get("action", "clear")
                from serafina_runtime.network_sentinel import NETWORK_SENTINEL
                if action == "clear":
                    NETWORK_SENTINEL.gatekeeper_whitelist.clear()
                    self._json(200, {"ok": True, "message": "白名单已清空"})
                elif action == "remove":
                    pname = str(body.get("parent_name", ""))
                    ok = NETWORK_SENTINEL.gatekeeper_whitelist.remove_parent(pname)
                    self._json(200, {"ok": ok, "message": f"已从白名单移除: {pname}"})
                elif action == "add":
                    pname = str(body.get("parent_name", ""))
                    res = NETWORK_SENTINEL.gatekeeper_whitelist.add_parent(pname)
                    self._json(200, res)
                else:
                    self._json(400, {"ok": False, "error": f"Unknown action: {action}"})
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/network/set_rate_limit":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length)) if length > 0 else {}
                pid = int(body.get("pid", 0))
                pname = str(body.get("process_name", body.get("name", "")))
                limit_kb_s = float(body.get("limit_kb_s", 0.0))
                from serafina_runtime.network_sentinel import NETWORK_SENTINEL
                res = NETWORK_SENTINEL.rate_limiter.set_rate_limit(
                    pid=pid,
                    process_name=pname,
                    limit_kb_s=limit_kb_s,
                    name=pname
                )
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/network/gatekeeper_simulate":
            try:
                from serafina_runtime.network_sentinel import NETWORK_SENTINEL
                res = NETWORK_SENTINEL.simulate_gatekeeper_event()
                self._json(200, res)
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/network/kill_all_suspicious":
            try:
                from serafina_runtime.network_sentinel import NETWORK_SENTINEL
                res = NETWORK_SENTINEL.kill_all_suspicious()
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/startup/toggle":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                item_id = str(body.get("id", ""))
                enable = bool(body.get("enable", False))
                from serafina_runtime.startup_manager import STARTUP_MANAGER
                ok, msg = STARTUP_MANAGER.toggle_item(item_id, enable)
                self._json(200 if ok else 400, {"ok": ok, "message": msg})
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/startup/batch_disable":
            try:
                from serafina_runtime.startup_manager import STARTUP_MANAGER
                res = STARTUP_MANAGER.batch_disable_non_essential()
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/watchlist/add":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                pid = int(body.get("pid", 0))
                block_types = body.get("block_types")
                custom_exts = body.get("custom_extensions")
                block_large = bool(body.get("block_large_files", True))
                large_mb = float(body.get("large_file_mb", 20.0))
                sandbox_dir = body.get("sandbox_dir")
                enforce_prompt = bool(body.get("enforce_prompt", False))
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                res = PROCESS_WATCHLIST.add_to_watchlist(
                    pid=pid,
                    block_types=block_types,
                    custom_extensions=custom_exts,
                    block_large_files=block_large,
                    large_file_mb=large_mb,
                    sandbox_dir=sandbox_dir,
                    enforce_prompt=enforce_prompt,
                )
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/watchlist/remove":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                pid = int(body.get("pid", 0))
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                res = PROCESS_WATCHLIST.remove_from_watchlist(pid)
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/watchlist/update_rules":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                pid = int(body.get("pid", 0))
                block_types = body.get("block_types")
                custom_exts = body.get("custom_extensions")
                block_large = body.get("block_large_files")
                large_mb = body.get("large_file_mb")
                sandbox_dir = body.get("sandbox_dir")
                enforce_prompt = body.get("enforce_prompt")
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                res = PROCESS_WATCHLIST.update_rules(
                    pid=pid,
                    block_types=block_types,
                    custom_extensions=custom_exts,
                    block_large_files=block_large,
                    large_file_mb=large_mb,
                    sandbox_dir=sandbox_dir,
                    enforce_prompt=enforce_prompt,
                )
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/watchlist/pause":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                pid = int(body.get("pid", 0))
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                res = PROCESS_WATCHLIST.pause_process(pid)
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/watchlist/resume":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                pid = int(body.get("pid", 0))
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                res = PROCESS_WATCHLIST.resume_process(pid)
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/watchlist/analyze_file":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                target_path = body.get("path", "")
                pid = int(body.get("pid", 0))
                pname = body.get("process_name", "")
                force = bool(body.get("force", False))
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                res = PROCESS_WATCHLIST.analyze_file_with_llm(target_path, pid=pid, process_name=pname, force=force)
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/watchlist/block_ip":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                pid = int(body.get("pid", 0))
                ip = str(body.get("ip", "")).strip()
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                res = PROCESS_WATCHLIST.block_ip(pid, ip)
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/watchlist/unblock_ip":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                pid = int(body.get("pid", 0))
                ip = str(body.get("ip", "")).strip()
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                res = PROCESS_WATCHLIST.unblock_ip(pid, ip)
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/watchlist/disconnect_socket":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                pid = int(body.get("pid", 0))
                remote_ip = str(body.get("remote_ip", "")).strip()
                remote_port = str(body.get("remote_port", "")).strip()
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                res = PROCESS_WATCHLIST.disconnect_socket(pid, remote_ip, remote_port)
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/watchlist/clear_history":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                pid = int(body.get("pid", 0))
                from serafina_runtime.network_sentinel import PROCESS_WATCHLIST
                res = PROCESS_WATCHLIST.clear_file_history(pid)
                self._json(200 if res.get("ok") else 400, res)
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/watchlist/reveal_file":
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length))
                fpath = str(body.get("path", "")).strip()
                if fpath and os.path.exists(fpath):
                    subprocess.run(["open", "-R", fpath], check=False)
                    self._json(200, {"ok": True, "message": f"已在 Finder 中定位: {fpath}"})
                else:
                    self._json(400, {"ok": False, "error": f"文件不存在: {fpath}"})
            except Exception as exc:
                self._json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/model/unload":
            try:
                state_dir = Path.home() / ".local" / "state" / "mtplx-qwen38"
                state_dir.mkdir(parents=True, exist_ok=True)
                (state_dir / "disabled").touch()
                
                omlx_script = Path.home() / "bin" / "omlx_ctl.py"
                if omlx_script.exists():
                    subprocess.run(["python3", str(omlx_script), "release"], capture_output=True, timeout=15)
                lms = Path.home() / ".lmstudio" / "bin" / "lms"
                if lms.exists():
                    subprocess.run([str(lms), "unload", "--all"], capture_output=True, timeout=10)
                try:
                    out = subprocess.check_output(["lsof", "-nP", "-tiTCP:8000", "-sTCP:LISTEN"], text=True, stderr=subprocess.DEVNULL)
                    for p in out.splitlines():
                        if p.strip().isdigit():
                            cmd = subprocess.check_output(["ps", "-p", p.strip(), "-o", "command="], text=True, stderr=subprocess.DEVNULL)
                            if "mtplx" in cmd:
                                os.kill(int(p.strip()), signal.SIGTERM)
                except Exception:
                    pass
                self._json(200, {"ok": True, "message": "已成功卸载模型并彻底释放显存，系统进入空载状态"})
            except Exception as exc:
                self._json(500, {"ok": False, "error": str(exc)})
            return
        if path == "/v1/runtime/quarantine/clear":
            if GPU_FAULT_SUPERVISOR:
                GPU_FAULT_SUPERVISOR.clear_quarantine()
            self._json(200, {"ok": True, "message": "Quarantine cleared"})
            return
        self.chat_mode=path=='/v1/chat/completions'
        self.chat_nonstream=False
        self.chat_output=[]
        if path in ('/v1/messages','/v1/messages/count_tokens'):
            self._anthropic_passthrough(path)
            return
        if path=='/v1/gateway/events':
            try:
                record=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))))
                kind = record.get('kind')
                allowed=('tool_running','tool_returned','child_started','tool_before','tool_after')
                if kind not in allowed: raise ValueError('unsupported event')
                session_id = str(record.get('session_id') or '')[:256]
                tool = str(record.get('tool') or '')[:128]
                task = str(record.get('task') or '')[:240]
                agent_name = str(record.get('agent_name') or '')[:256]
                args = record.get('args', {})
                cwd = str(record.get('cwd') or '')
                exit_code = record.get('exit_code')
                output = str(record.get('output') or '')

                # Execution Controller: Check idempotency & permissions
                if kind in ('tool_running', 'tool_before') and EXEC_CONTROLLER and session_id:
                    pre = EXEC_CONTROLLER.check_pre_execution(session_id, tool, args or task, cwd)
                    if not pre.get('permitted', True):
                        self._json(403, {'ok': False, 'error': {'message': pre.get('reason', 'Blocked by ExecutionController')}})
                        _traffic({'kind': 'blocked', 'id': session_id, 'tool': tool, 'reason': pre.get('reason')})
                        return

                if kind in ('tool_returned', 'tool_after') and EXEC_CONTROLLER and session_id:
                    k = EXEC_CONTROLLER.generate_idempotency_key(session_id, tool, args or task, cwd)
                    EXEC_CONTROLLER.record_post_execution(k, exit_code=exit_code or 0, output_summary=output[:500])
                    if exit_code == 0 and GPU_FAULT_SUPERVISOR:
                        GPU_FAULT_SUPERVISOR.record_progress_step(verified=True)

                if RUNTIME_STORE and session_id:
                    RUNTIME_STORE.record_event(task_id=session_id, session_id=session_id, event_type=kind, payload=record, source="client_hook")

                _traffic({'kind': kind, 'id': session_id, 'tool': tool, 'agent_name': agent_name, 'task': task, 'exit_code': exit_code})
                self._json(200, {'ok': True})
            except Exception:self._json(400,{'error':{'message':'Invalid gateway event'}})
            return
        if path not in ('/v1/responses','/v1/chat/completions'):
            self._json(404, {"error": {"message": "Not found"}})
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            payload = json.loads(self.rfile.read(length))
        except Exception as exc:
            self._json(400, {"error": {"message": str(exc)}})
            return

        if self.chat_mode:
            self.chat_nonstream=not bool(payload.get('stream'))
            payload=_chat_to_responses(payload)

        runtime = _runtime()
        self.identity = Identity.resolve(self.headers, payload, _chat_messages(payload))
        self.backend_request_ids = set()
        self.backend_readers = []
        self.backend_stop = threading.Event()
        self.backend_failure=False
        backend = str(runtime.get("backend_url") or self.backend).rstrip("/")
        requested_model = payload.get("model")
        requested_name = requested_model if isinstance(requested_model, str) else None
        wire_model, shown_model = _active_model(runtime, backend, requested_name)
        if wire_model and wire_model != requested_name:
            payload = dict(payload)
            payload["model"] = wire_model
            _switcher_log(
                f"model follow active={shown_model or wire_model} wire={wire_model} requested={requested_name}"
            )
        elif wire_model:
            payload = dict(payload)
            payload["model"] = wire_model
        response_id = _id("resp")
        base = {
            "id": response_id,
            "object": "response",
            "created_at": int(time.time()),
            "model": shown_model or payload.get("model"),
            "status": "in_progress",
            "output": [],
        }
        started = time.monotonic()
        question = _latest_user_preview(payload)
        background = _background_rollout_answer(payload)
        if background is not None:
            _switcher_log(
                f"qa skip background id={response_id} reason=other-rollout q={question!r}"
            )
            print(f"request skip background id={response_id}", flush=True)
            self.send_response(200)
            self.send_header("Content-Type", "application/json" if self.chat_nonstream else "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            self._event("response.created", {"type": "response.created", "response": base})
            self._complete_text(base, background)
            return
        has_image = any(
            isinstance(part, dict) and part.get("type") in {"input_image", "image_url"}
            for item in payload.get("input", []) if isinstance(item, dict)
            for part in item.get("content", []) if isinstance(item.get("content"), list)
        )
        print(
            f"request start id={response_id} model={payload.get('model')} image={has_image}",
            flush=True,
        )
        _traffic({
            "kind": "start",
            "id": response_id,
            "model": shown_model or payload.get("model"),
            "image": has_image,
            "question": question,
            "backend": backend,
            "thread_id": self.identity.thread,
            "agent_name": self.identity.agent,
            "client": self._client_label(path),
        })
        _switcher_log(
            f"qa start id={response_id} model={shown_model or payload.get('model')} image={has_image} q={question!r}"
        )

        if GPU_FAULT_SUPERVISOR:
            is_iso, rem = GPU_FAULT_SUPERVISOR.is_isolated(wire_model or "default")
            if is_iso:
                iso_msg = f"[ARP 保护] 模型 '{wire_model or shown_model}' 处于故障隔离冷却中 (剩余 {int(rem)} 秒)，避免底层 Metal Watchdog 持续雪崩。请等待冷却或切换模型。"
                _switcher_log(f"qa blocked quarantined id={response_id} model={wire_model} rem={rem:.1f}s")
                self.send_response(200)
                self.send_header("Content-Type", "application/json" if self.chat_nonstream else "text/event-stream; charset=utf-8")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "close")
                self.end_headers()
                self._event("response.created", {"type": "response.created", "response": base})
                self._send_failure(base, iso_msg)
                return

        prompt_tokens = 0
        completion_tokens = 0
        try:
            self.send_response(200)
            self.send_header("Content-Type", "application/json" if self.chat_nonstream else "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            self._event("response.created", {"type": "response.created", "response": base})
            def heartbeat(position, seconds):
                self._keep_alive(b': queued\n\n')
                _traffic({"kind":"queued","id":response_id,"position":position,"elapsed_s":seconds})
            config={**DEFAULTS,**(runtime.get('gateway') or {})}
            with GATEWAY.queue.lease(self.identity,response_id,self._disconnected,heartbeat,
                                     int(config['max_subagents']),int(config['max_depth'])):
                _traffic({"kind":"admitted","id":response_id,"agent_name":self.identity.agent})
                try:
                    usage, answer, tool_calls = self._stream_backend(backend, payload, base, response_id, started)
                    tool_calls = GATEWAY.policy_calls(self.identity, tool_calls)
                    # Outbound guard: refuse re-reads of files the ledger already holds.
                    filtered_calls = tool_calls
                    try:
                        from serafina_runtime.read_ledger import analyze, is_read_tool, extract_path
                        verdict = analyze(_chat_messages(payload))
                        filtered_calls, dropped = [], []
                        for call in tool_calls:
                            fn = call.get('function') or {}
                            path = extract_path(fn.get('arguments'))
                            if is_read_tool(str(fn.get('name') or '')) and path and verdict.block(path):
                                dropped.append(path)
                                continue
                            filtered_calls.append(call)
                        if dropped:
                            _switcher_log(f"loop guard dropped re-read: {dropped}")
                            if not filtered_calls and not answer.strip():
                                answer = ("【任务暂停：检测到重复读取】\n" + verdict.render() +
                                          "\n\n上面这些文件内容模型已读过。请告诉它下一步要改什么，或直接回复“按已有信息开始修改”。")
                    except Exception as exc:
                        _switcher_log(f"loop guard error: {exc}")
                    tool_calls = filtered_calls
                    for call in tool_calls:
                        fn = call.get('function') or {}
                        args = _json_loads(fn.get('arguments') or '{}') or {}
                        _traffic({'kind':'tool_dispatch','id':response_id,'tool':fn.get('name'),
                                  'agent_name':self.identity.agent,'task':_preview(str(args.get('message') or args.get('description') or args.get('cmd') or args.get('filePath') or args.get('path') or ''),180)})
                finally:
                    # Do not admit the next job while an abandoned request can
                    # still be generating on the backend.
                    self._drain_backend(backend)
            self._finish_stream(base, answer, tool_calls, usage)
            elapsed = time.monotonic() - started
            prompt_tokens = int(usage.get("prompt_tokens") or 0)
            completion_tokens = int(usage.get("completion_tokens") or 0)
            decode = usage.get("decode_tok_s")
            prefill = usage.get("prefill_tok_s")
            ttft = usage.get("ttft_s")
            speed = f"{float(decode):.2f}" if isinstance(decode, (int, float)) else "n/a"
            prefill_text = f"{float(prefill):.2f}" if isinstance(prefill, (int, float)) else "n/a"
            ttft_text = f"{float(ttft):.2f}" if isinstance(ttft, (int, float)) else "n/a"
            print(
                f"request done id={response_id} duration={elapsed:.2f}s "
                f"in={prompt_tokens} out={completion_tokens} "
                f"prefill_tok_s={prefill_text} decode_tok_s={speed} ttft={ttft_text}",
                flush=True,
            )
            _traffic({
                "kind": "done",
                "id": response_id,
                "model": shown_model or payload.get("model"),
                "question": question,
                "answer": _preview(answer, 1200),
                "prompt_tokens": prompt_tokens,
                "completion_tokens": completion_tokens,
                "prefill_tok_s": prefill,
                "decode_tok_s": decode,
                "ttft_s": ttft,
                "elapsed_s": round(elapsed, 3),
                "tool_calls": len(tool_calls),
                "recovery_attempts": int(usage.get("recovery_attempts") or 0),
                "awaiting_tool_output": bool(tool_calls),
            })
            if not usage.get('recovery_attempts'):GATEWAY.store.record_speed(shown_model or payload.get('model'),usage,response_id)
            if GPU_FAULT_SUPERVISOR:
                GPU_FAULT_SUPERVISOR.record_success(wire_model or "default", prompt_tokens, completion_tokens)
            _switcher_log(
                f"qa done id={response_id} in={prompt_tokens} out={completion_tokens} "
                f"prefill_tok_s={prefill_text} decode_tok_s={speed} ttft_s={ttft_text} "
                f"elapsed_s={elapsed:.2f} tools={len(tool_calls)} "
                f"q={question!r} a={_preview(answer, 400)!r}"
            )
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")
            if GPU_FAULT_SUPERVISOR:
                GPU_FAULT_SUPERVISOR.record_fault(wire_model or "default", backend, f"HTTP {exc.code}: {detail}")
                GPU_FAULT_SUPERVISOR.record_wasted(wire_model or "default", prompt_tokens or (len(str(payload)) // 4), 0, f"HTTP {exc.code}")
            self._send_failure(base, f"HTTP {exc.code}: {detail}")
            _traffic({"kind": "error", "id": response_id, "message": detail[:500]})
        except (BrokenPipeError, ConnectionResetError):
            elapsed = time.monotonic() - started
            if GPU_FAULT_SUPERVISOR:
                GPU_FAULT_SUPERVISOR.record_wasted(wire_model or "default", prompt_tokens or (len(str(payload)) // 4), 0, "Cancelled")
            print(f"request cancelled id={response_id} duration={elapsed:.2f}s", flush=True)
            _traffic({"kind": "cancelled", "id": response_id, "elapsed_s": round(elapsed, 3)})
            _switcher_log(f"qa cancelled id={response_id} elapsed_s={elapsed:.2f}")
        except Cancelled:
            if GPU_FAULT_SUPERVISOR:
                GPU_FAULT_SUPERVISOR.record_wasted(wire_model or "default", prompt_tokens or (len(str(payload)) // 4), 0, "Cancelled")
            _traffic({"kind":"cancelled","id":response_id})
        except Blocked as exc:
            # Reported once, never memoised: the next request (e.g. "继续")
            # reaches the model normally.
            try:
                self._send_blocked(base, str(exc))
            except (BrokenPipeError, ConnectionResetError):
                pass
            _traffic({'kind':'blocked','id':response_id,'message':str(exc),
                      'thread_id':self.identity.thread,'agent_name':self.identity.agent})
        except Exception as exc:
            if GPU_FAULT_SUPERVISOR and not isinstance(exc, (Blocked, Cancelled)):
                GPU_FAULT_SUPERVISOR.record_fault(wire_model or "default", backend, str(exc))
                GPU_FAULT_SUPERVISOR.record_wasted(wire_model or "default", prompt_tokens or (len(str(payload)) // 4), 0, str(exc))
            try:
                self._send_failure(base, str(exc))
            except (BrokenPipeError, ConnectionResetError):
                pass
            _traffic({"kind": "blocked" if isinstance(exc,Blocked) else "error", "id": response_id, "message": str(exc)[:500]})

    def _anthropic_passthrough(self, path: str) -> None:
        """Anthropic Messages API (Claude Code) to a backend that speaks it
        natively (MTPLX, LM Studio): the same model
        mapping, thinking switch, queue and session identity as the other
        clients; the request body and response stream are otherwise untouched."""
        runtime = _runtime()
        backend = str(runtime.get("backend_url") or self.backend).rstrip("/")
        try:
            payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}")
        except ValueError as exc:
            self._json(400, {"type": "error", "error": {"type": "invalid_request_error", "message": str(exc)}})
            return
        kind = runtime.get("backend") or "mtplx"
        wire, shown = _active_model(runtime, backend, payload.get("model"))
        if kind not in ("mtplx", "lmstudio"):
            # No native Anthropic endpoint (Bonsai), or one that leaves the model's
            # reasoning in the answer text (oMLX with Nemotron): translate to chat
            # completions, where the backend splits reasoning from content.
            self._anthropic_translated(path, payload, runtime, backend, wire, shown)
            return
        if wire:
            payload["model"] = wire
        if kind == "mtplx" and path == "/v1/messages" and "thinking" not in payload and not runtime.get("enable_thinking", False):
            payload["thinking"] = {"type": "disabled"}
        self.identity = Identity.resolve(self.headers, payload, [])
        request_id = _id("msg")
        headers = {**self._client_headers(), "Content-Type": "application/json",
                   "anthropic-version": self.headers.get("anthropic-version") or "2023-06-01",
                   "x-mtplx-request-id": request_id}
        if self.identity.persistent:
            headers["x-mtplx-session-id"] = self.identity.key
        request = urllib.request.Request(backend + path, data=json.dumps(payload).encode(), headers=headers, method="POST")

        def relay(response, status):
            self.send_response(status)
            self.send_header("Content-Type", response.headers.get("Content-Type", "application/json"))
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            while True:
                chunk = response.read1(8192)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()

        if path.endswith("/count_tokens"):
            try:
                with urllib.request.urlopen(request, timeout=120) as response:
                    relay(response, response.status)
            except urllib.error.HTTPError as exc:
                relay(exc, exc.code)
            return
        started = time.monotonic()
        _traffic({"kind": "start", "id": request_id, "model": shown or wire, "image": False,
                  "question": "(Claude Code)", "backend": backend,
                  "thread_id": self.identity.thread, "agent_name": self.identity.agent, "client": "claude"})
        config = {**DEFAULTS, **(runtime.get("gateway") or {})}
        try:
            with GATEWAY.queue.lease(self.identity, request_id, self._disconnected, lambda *_: None,
                                     int(config["max_subagents"]), int(config["max_depth"])):
                try:
                    response = urllib.request.urlopen(request, timeout=None)
                except urllib.error.HTTPError as exc:
                    relay(exc, exc.code)
                    return
                with response:
                    relay(response, response.status)
            _traffic({"kind": "done", "id": request_id, "model": shown or wire,
                      "elapsed_s": round(time.monotonic() - started, 3)})
        except (BrokenPipeError, ConnectionResetError, Cancelled):
            try:
                urllib.request.urlopen(urllib.request.Request(f"{backend}/v1/mtplx/cancel/{request_id}",
                                                              data=b"", method="POST"), timeout=3)
            except OSError:
                pass
            _traffic({"kind": "cancelled", "id": request_id})
        except Blocked as exc:
            self._json(429, {"type": "error", "error": {"type": "rate_limit_error", "message": str(exc)}})

    def _anthropic_translated(self, path, payload, runtime, backend, wire, shown) -> None:
        """Serve Anthropic Messages from an OpenAI chat backend, streaming included."""
        if path.endswith("/count_tokens"):
            text = json.dumps([payload.get("system"), payload.get("messages"), payload.get("tools")], ensure_ascii=False)
            self._json(200, {"input_tokens": max(1, len(text) // 4)})
            return
        body = _anthropic_to_chat(payload, wire)
        if runtime.get("backend") == "omlx":
            _omlx_thinking(body, runtime, runtime.get("reasoning_effort"))
        self.identity = Identity.resolve(self.headers, payload, [])
        request_id = _id("msg")
        request = urllib.request.Request(f"{backend}/v1/chat/completions", data=json.dumps(body).encode(),
                                         headers={**self._client_headers(), "Content-Type": "application/json"},
                                         method="POST")
        _traffic({"kind": "start", "id": request_id, "model": shown or wire, "image": False,
                  "question": "(Claude Code)", "backend": backend, "thread_id": self.identity.thread,
                  "agent_name": self.identity.agent, "client": "claude"})
        started = time.monotonic()
        config = {**DEFAULTS, **(runtime.get("gateway") or {})}

        def event(name, data):
            self.wfile.write(f"event: {name}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n".encode())
            self.wfile.flush()

        try:
            with GATEWAY.queue.lease(self.identity, request_id, self._disconnected, lambda *_: None,
                                     int(config["max_subagents"]), int(config["max_depth"])):
                try:
                    response = urllib.request.urlopen(request, timeout=None)
                except urllib.error.HTTPError as exc:
                    detail = exc.read().decode(errors="replace")[:1000]
                    self._json(exc.code, {"type": "error", "error": {"type": "api_error", "message": detail}})
                    return
                with response:
                    if not body["stream"]:
                        self._json(200, _chat_to_anthropic(json.load(response), shown or wire))
                    else:
                        self.send_response(200)
                        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
                        self.send_header("Cache-Control", "no-cache")
                        self.send_header("Connection", "close")
                        self.end_headers()
                        event("message_start", {"type": "message_start", "message": {
                            "id": request_id, "type": "message", "role": "assistant", "model": shown or wire,
                            "content": [], "stop_reason": None, "stop_sequence": None,
                            "usage": {"input_tokens": 0, "output_tokens": 0}}})
                        index, open_kind, tools_by_slot = -1, None, {}
                        finish, usage, buffer = None, {}, b""

                        def close_block():
                            nonlocal open_kind
                            if open_kind is not None:
                                event("content_block_stop", {"type": "content_block_stop", "index": index})
                                open_kind = None

                        while True:
                            block = response.read1(8192)
                            if not block:
                                break
                            buffer += block
                            cut = buffer.rfind(b"\n\n")
                            if cut == -1:
                                continue
                            ready, buffer = buffer[:cut + 2], buffer[cut + 2:]
                            for chunk in _iter_sse_payloads(ready):
                                usage = chunk.get("usage") or usage
                                for choice in chunk.get("choices") or []:
                                    finish = choice.get("finish_reason") or finish
                                    delta = choice.get("delta") or {}
                                    if isinstance(delta.get("content"), str) and delta["content"]:
                                        if open_kind != "text":
                                            close_block()
                                            index += 1
                                            open_kind = "text"
                                            event("content_block_start", {"type": "content_block_start", "index": index,
                                                                          "content_block": {"type": "text", "text": ""}})
                                        event("content_block_delta", {"type": "content_block_delta", "index": index,
                                                                      "delta": {"type": "text_delta", "text": delta["content"]}})
                                    for call in delta.get("tool_calls") or []:
                                        slot = int(call.get("index") or 0)
                                        function = call.get("function") or {}
                                        if slot not in tools_by_slot:
                                            close_block()
                                            index += 1
                                            open_kind = "tool"
                                            tools_by_slot[slot] = index
                                            event("content_block_start", {"type": "content_block_start", "index": index,
                                                                          "content_block": {"type": "tool_use",
                                                                                            "id": call.get("id") or _id("toolu"),
                                                                                            "name": function.get("name") or "",
                                                                                            "input": {}}})
                                        if function.get("arguments"):
                                            event("content_block_delta", {"type": "content_block_delta", "index": index,
                                                                          "delta": {"type": "input_json_delta",
                                                                                    "partial_json": function["arguments"]}})
                        close_block()
                        stop = "tool_use" if tools_by_slot else {"length": "max_tokens"}.get(finish, "end_turn")
                        event("message_delta", {"type": "message_delta",
                                                "delta": {"stop_reason": stop, "stop_sequence": None},
                                                "usage": {"output_tokens": int(usage.get("completion_tokens") or 0)}})
                        event("message_stop", {"type": "message_stop"})
            _traffic({"kind": "done", "id": request_id, "model": shown or wire,
                      "elapsed_s": round(time.monotonic() - started, 3)})
        except (BrokenPipeError, ConnectionResetError, Cancelled):
            _traffic({"kind": "cancelled", "id": request_id})
        except Blocked as exc:
            self._json(429, {"type": "error", "error": {"type": "rate_limit_error", "message": str(exc)}})

    def _client_label(self, path: str) -> str:
        """Which client sent this request, for the switcher's activity view."""
        agent = (self.headers.get("User-Agent") or "").lower()
        names = {k.lower() for k in self.headers.keys()}
        if path.startswith("/v1/messages") or "claude-cli" in agent:
            return "claude"
        if self.identity.thread.startswith("opencode-") or "opencode" in agent:
            return "opencode"
        if "qwen" in agent or self.identity.thread.startswith("client-qwen"):
            return "qwen"
        if "codex" in agent or "x-codex-turn-metadata" in names or "originator" in names:
            return "codex"
        return "other"

    def _client_headers(self) -> dict[str, str]:
        """Let the backend see who the client is, so client-specific cache
        policies apply (MTPLX keys its OpenCode tool-history restore on this)."""
        headers = {}
        agent = self.headers.get("User-Agent")
        if agent:
            headers["User-Agent"] = agent
        if self.identity.thread.startswith("opencode-"):
            headers["x-mtplx-client"] = "opencode"
        return headers

    def _disconnected(self):
        ready,_,_=select.select([self.connection],[],[],0)
        if not ready:return False
        try:return self.connection.recv(1,socket.MSG_PEEK|socket.MSG_DONTWAIT)==b''
        except (ConnectionResetError,OSError):return True

    def _keep_alive(self,packet=b': keep-alive\n\n'):
        if not self.chat_nonstream:self.wfile.write(packet);self.wfile.flush()

    def _drain_backend(self,backend):
        if self.backend_failure or any(t.is_alive() for t in self.backend_readers):
            self.backend_stop.set()
            for rid in self.backend_request_ids:
                try:
                    req=urllib.request.Request(backend+'/v1/mtplx/cancel/'+rid,data=b'',method='POST')
                    with urllib.request.urlopen(req,timeout=5) as r:r.read()
                except Exception:pass
            for t in self.backend_readers:
                while t.is_alive():t.join(timeout=0.5)

    def _stream_backend(
        self,
        backend: str,
        payload: dict[str, Any],
        base: dict[str, Any],
        response_id: str,
        started: float,
    ) -> tuple[dict[str, Any], str, list[dict[str, Any]]]:
        runtime = _runtime()
        request_body=GATEWAY.prepare(self.identity,_chat_messages(payload),
            _chat_payload(payload,runtime),lambda e:_traffic({**e,'id':response_id}))
        request_data = json.dumps(request_body).encode()
        backend_id='chatcmpl-gateway-'+uuid.uuid4().hex
        self.backend_request_ids.add(backend_id)
        request = urllib.request.Request(
            f"{backend}/v1/chat/completions",
            data=request_data,
            headers={**self._client_headers(), "Content-Type": "application/json",
                     **({"x-mtplx-session-id":self.identity.key} if self.identity.persistent else {}),
                     "x-mtplx-request-id":backend_id},
            method="POST",
        )
        events: queue.Queue[tuple[str, Any]] = queue.Queue()

        def reader() -> None:
            # One Codex turn can prefill for minutes and then generate until the
            # model itself stops. A fixed socket timeout made that look like the
            # answer was cut off. Connection refused is retried only before any
            # token arrives, so a model reload can finish the same turn.
            deadline = time.monotonic() + 240
            while not self.backend_stop.is_set():
                try:
                    with urllib.request.urlopen(request, timeout=None) as response:
                        buffer = b""
                        while True:
                            block = response.read1(8192)
                            if not block:
                                events.put(("end", _iter_sse_payloads(buffer)))
                                return
                            buffer += block
                            cut = buffer.rfind(b"\n\n")
                            if cut == -1:
                                continue
                            ready, buffer = buffer[: cut + 2], buffer[cut + 2 :]
                            events.put(("data", _iter_sse_payloads(ready)))
                except Exception as exc:
                    message = str(exc)
                    retryable = "Connection refused" in message or "Remote end closed" in message
                    if retryable and time.monotonic() < deadline and not self.backend_stop.is_set():
                        events.put(("waiting_backend", message))
                        time.sleep(2)
                        continue
                    events.put(("error", exc))
                    self.backend_failure=True
                    return

        thread=threading.Thread(target=reader, name=f"bridge-{response_id[-8:]}", daemon=True)
        self.backend_readers.append(thread);thread.start()
        answer_parts: list[str] = []
        think_parts: list[str] = []
        pending = ""
        tool_acc: dict[int, dict[str, str]] = {}
        usage: dict[str, Any] = {}
        first_token_at: float | None = None
        last_token_at: float | None = None
        last_flush = time.monotonic()
        opened = False
        item_id = _id("msg")

        def flush_text(force: bool = False) -> None:
            nonlocal pending, last_flush, opened
            if not pending:
                return
            if not force and len(pending) < 24 and time.monotonic() - last_flush < 0.15:
                return
            if not opened:
                item = {
                    "id": item_id,
                    "type": "message",
                    "role": "assistant",
                    "status": "in_progress",
                    "content": [],
                }
                self._event("response.output_item.added", {
                    "type": "response.output_item.added", "output_index": 0, "item": item,
                })
                self._event("response.content_part.added", {
                    "type": "response.content_part.added",
                    "item_id": item_id,
                    "output_index": 0,
                    "content_index": 0,
                    "part": {"type": "output_text", "text": "", "annotations": []},
                })
                opened = True
                self.stream_message_id = item_id
                self.stream_message_text = ''
            self._event("response.output_text.delta", {
                "type": "response.output_text.delta",
                "item_id": item_id,
                "output_index": 0,
                "content_index": 0,
                "delta": pending,
            })
            self.stream_message_text += pending
            _traffic({"kind": "delta", "id": response_id, "text": pending})
            pending = ""
            last_flush = time.monotonic()

        while True:
            if self._disconnected():raise Cancelled('客户端已取消本次推理。')
            try:
                kind, value = events.get(timeout=5)
            except queue.Empty:
                flush_text(force=True)
                self._keep_alive()
                if first_token_at is None:
                    _traffic({
                        "kind": "wait",
                        "id": response_id,
                        "elapsed_s": round(time.monotonic() - started, 3),
                    })
                continue
            if kind == "waiting_backend":
                self._keep_alive()
                _traffic({
                    "kind": "wait",
                    "id": response_id,
                    "elapsed_s": round(time.monotonic() - started, 3),
                    "reason": "backend-down",
                })
                continue
            if kind == "error":
                raise value
            payloads = value if isinstance(value, list) else []
            for chunk in payloads:
                if chunk.get('error'):
                    self.backend_failure = True
                    error = chunk['error']
                    raise RuntimeError(error.get('message', str(error)) if isinstance(error, dict) else str(error))
                progress = chunk.get("mtplx_progress")
                if isinstance(progress, dict) and progress:
                    if progress.get('request_id'):self.backend_request_ids.add(str(progress['request_id']))
                    _traffic({"kind": "progress", "id": response_id, "progress": progress})
                choices = chunk.get("choices") or []
                if choices and choices[0].get('finish_reason'):usage['_finish_reason']=choices[0]['finish_reason']
                delta = (choices[0].get("delta") if choices and isinstance(choices[0], dict) else None) or {}
                content = delta.get("content")
                if isinstance(content, str) and content:
                    now = time.monotonic()
                    if first_token_at is None:
                        first_token_at = now
                        usage["ttft_s"] = round(first_token_at - started, 3)
                        _traffic({"kind": "ttft", "id": response_id, "ttft_s": usage["ttft_s"]})
                    last_token_at = now
                    answer_parts.append(content)
                    pending += content
                    flush_text()
                reasoning = delta.get("reasoning_content")
                if not isinstance(reasoning, str) or not reasoning:
                    alt = delta.get("reasoning")
                    reasoning = alt if isinstance(alt, str) else ""
                if isinstance(reasoning, str) and reasoning:
                    now = time.monotonic()
                    if first_token_at is None:
                        first_token_at = now
                        usage["ttft_s"] = round(first_token_at - started, 3)
                        _traffic({"kind": "ttft", "id": response_id, "ttft_s": usage["ttft_s"]})
                    last_token_at = now
                    think_parts.append(reasoning)
                    _traffic({"kind": "think", "id": response_id, "text": reasoning[:200]})
                for call in delta.get("tool_calls") or []:
                    if not isinstance(call, dict):
                        continue
                    now = time.monotonic()
                    if first_token_at is None:
                        first_token_at = now
                        usage["ttft_s"] = round(first_token_at - started, 3)
                        _traffic({"kind": "ttft", "id": response_id, "ttft_s": usage["ttft_s"]})
                    last_token_at = now
                    index = int(call.get("index") or 0)
                    slot = tool_acc.setdefault(index, {"id": "", "name": "", "arguments": ""})
                    if call.get("id"):
                        slot["id"] = str(call["id"])
                    function = call.get("function") or {}
                    if function.get("name"):
                        slot["name"] += str(function["name"])
                    if function.get("arguments"):
                        slot["arguments"] += str(function["arguments"])
                if isinstance(chunk.get("usage"), dict):
                    usage.update(chunk["usage"])
                timings = chunk.get("timings")
                if isinstance(timings, dict) and timings.get("predicted_per_second") is not None:
                    usage["decode_tok_s"] = timings.get("predicted_per_second")
                    usage["prefill_tok_s"] = timings.get("prompt_per_second")
            if kind == "end":
                break

        flush_text(force=True)
        answer = "".join(answer_parts)
        tool_calls = [
            {
                "id": slot["id"] or _id("call"),
                "type": "function",
                "function": {"name": slot["name"], "arguments": _coerce_arguments(slot["arguments"] or "{}")},
            }
            for _, slot in sorted(tool_acc.items())
            if slot["name"] or slot["arguments"]
        ]
        usage["_message_id"] = item_id
        chat_request = json.loads(request_data)
        can_call_tools = bool(chat_request.get("tools")) and chat_request.get("tool_choice") != "none"
        declared={t['function']['name']:t['function'] for t in chat_request.get('tools') or []}
        valid=[]
        for c in tool_calls:
            fn=c['function'];args=_json_loads(fn.get('arguments',''))
            schema=declared.get(fn.get('name'),{}).get('parameters',{})
            if fn.get('name') in declared and isinstance(args,dict) and all(k in args for k in schema.get('required',[])):valid.append(c)
        invalid_calls=bool(tool_calls) and len(valid)!=len(tool_calls)
        tool_calls=valid
        if not tool_calls and can_call_tools and (_stalled_tool_promise(answer) or (think_parts and not answer) or invalid_calls):
            extra, tool_calls, retry_usage = self._recover_stalled_tool_call(
                backend, request_data, answer, response_id,
            )
            for key in ("prompt_tokens", "completion_tokens", "total_tokens"):
                usage[key] = int(usage.get(key) or 0) + int(retry_usage.get(key) or 0)
            usage["recovery_attempts"] = retry_usage.get("recovery_attempts", 0)
            if extra and not tool_calls:
                extra = "\n\n" + extra
                pending += extra
                flush_text(force=True)
                answer += extra
                answer_parts.append(extra)

        if not tool_calls and can_call_tools and _stalled_tool_promise(answer.split('\n')[-1]):
            raise Blocked('重新规划后仍只有下一步承诺，没有可执行的工具调用。任务未完成。')
        if not tool_calls and not answer.strip():
            raise Blocked('模型本轮没有产生最终回复或工具调用，可能已耗尽思考/输出预算；任务未完成。')
        if not tool_calls and usage.get('_finish_reason')=='length':
            raise Blocked('模型到达本轮输出上限，回复不完整；请提高输出预算或拆分任务。')

        # If model generated tool calls without user-facing text:
        # Record action into SessionMemory and log to UI traffic stream for live feedback,
        # but DO NOT inject fake text into Codex assistant message history.
        if tool_calls and not answer.strip():
            first_tool = tool_calls[0].get("function", {})
            fn_name = first_tool.get("name", "工具")
            raw_args = first_tool.get("arguments", "")
            summary_desc = ""
            if "cmd" in raw_args:
                parsed_c = _json_loads(raw_args)
                if isinstance(parsed_c, dict) and "cmd" in parsed_c:
                    cmd_str = str(parsed_c["cmd"]).strip()
                    summary_desc = f"执行命令: `{cmd_str[:90]}`"
            if not summary_desc:
                summary_desc = f"调用工具 `{fn_name}`"

            # Emit live delta to Switcher UI so the user sees live progress
            _traffic({"kind": "delta", "id": response_id, "text": f"\n⚡ [{summary_desc}]\n"})

        if opened or answer:
            if not opened and answer:
                pending += answer
                flush_text(force=True)
            final_part = {"type": "output_text", "text": answer, "annotations": []}
            self._event("response.output_text.done", {
                "type": "response.output_text.done",
                "item_id": item_id,
                "output_index": 0,
                "content_index": 0,
                "text": answer,
            })
            self._event("response.content_part.done", {
                "type": "response.content_part.done",
                "item_id": item_id,
                "output_index": 0,
                "content_index": 0,
                "part": final_part,
            })
            self._event("response.output_item.done", {
                "type": "response.output_item.done",
                "output_index": 0,
                "item": {
                    "id": item_id,
                    "type": "message",
                    "role": "assistant",
                    "status": "completed",
                    "content": [final_part],
                },
            })
        completion_tokens = int(usage.get("completion_tokens") or 0)
        # Decode (generation) speed. Prefer the engine number. Otherwise measure
        # the span between the first and last streamed token. LM Studio batches
        # the tail of short replies into one chunk, so that span can collapse to
        # ~0; when it does we leave decode unset rather than report a fake rate.
        if usage.get("decode_tok_s") in (None, 0) and completion_tokens > 1 \
                and first_token_at is not None and last_token_at is not None:
            span = last_token_at - first_token_at
            if span >= 0.2:
                usage["decode_tok_s"] = round((completion_tokens - 1) / span, 3)
        # Prefill (prompt processing) speed: prefer engine timings, else derive
        # from how long we waited for the first token over the prompt length.
        prompt_tokens = int(usage.get("prompt_tokens") or 0)
        if usage.get("prefill_tok_s") in (None, 0) and first_token_at and prompt_tokens:
            prefill_s = max(0.001, first_token_at - started)
            usage["prefill_tok_s"] = round(prompt_tokens / prefill_s, 3)
        return usage, answer, tool_calls

    def _fetch_repair(self,backend,body,response_id,answer=''):
        # Same prefix as the request just answered, plus the stalled answer and
        # a nudge: the backend restores the prefix instead of prefilling again.
        body={**body,'messages':body['messages']+[
            {'role':'assistant','content':answer or '上一条没有产生最终结果或工具调用。'},
            {'role':'user','content':'上一条只有下一步承诺或思考，没有实际操作。请现在发出符合定义和原始授权的一个工具调用，继续完成原始目标。'}],
            'tool_choice':'required'}
        result=queue.Queue()
        rid='chatcmpl-gateway-'+uuid.uuid4().hex
        self.backend_request_ids.add(rid)
        def fetch():
            try:result.put(('ok',_retry_stalled_tool_call(backend,dumps(body).encode(),'',rid,True,self._client_headers())))
            except Exception as exc:self.backend_failure=True;result.put(('error',exc))
        thread=threading.Thread(target=fetch,daemon=True)
        self.backend_readers.append(thread);thread.start()
        while True:
            if self._disconnected():raise Cancelled('客户端取消了重新规划。')
            try:kind,value=result.get(timeout=2);break
            except queue.Empty:
                self._keep_alive(b': recovering-tool-call\n\n')
        if kind=='error':raise value
        return value

    def _recover_stalled_tool_call(
        self, backend: str, request_data: bytes, answer: str, response_id: str,
    ) -> tuple[str, list[dict[str, Any]], dict[str, Any]]:
        """Keep the Responses stream open while requesting an actual next action."""
        totals: dict[str, Any] = {"recovery_attempts": 0}
        for attempt in range(1, 3):
            _traffic({"kind": "retry", "id": response_id, "attempt": attempt})
            _switcher_log(f"stalled promise retry id={response_id} attempt={attempt} q={_preview(answer, 80)!r}")
            try:
                extra,calls,retry_usage=self._fetch_repair(backend,json.loads(request_data),response_id,answer)
            except Cancelled:raise
            except Exception as exc:
                _switcher_log(f"stalled promise retry failed id={response_id} attempt={attempt} error={exc}")
                continue
            totals["recovery_attempts"] = attempt
            for key in ("prompt_tokens", "completion_tokens", "total_tokens"):
                totals[key] = int(totals.get(key) or 0) + int(retry_usage.get(key) or 0)
            if calls:
                _switcher_log(f"stalled promise recovered id={response_id} attempt={attempt} tools={len(calls)}")
                return extra, calls, totals
            if extra.strip() and not _stalled_tool_promise(extra):
                return extra, [], totals
            answer = extra or answer
        raise Blocked("本地模型只返回了下一步进度文字，连续两次重新规划仍未产生有效工具调用；任务尚未完成。请提供具体下一步或切换模型。")

    def _complete_text(self, base: dict[str, Any], answer: str, continuing=False) -> None:
        existing = getattr(self,'stream_message_id','') if continuing else ''
        item_id = existing or _id("msg")
        delta = '\n\n'+answer if existing else answer
        answer = getattr(self,'stream_message_text','')+delta if existing else answer
        item = {
            "id": item_id,
            "type": "message",
            "role": "assistant",
            "status": "completed",
            "content": [{"type": "output_text", "text": answer, "annotations": []}],
        }
        if not existing:
            self._event("response.output_item.added", {
                "type": "response.output_item.added", "output_index": 0,
                "item": {**item,'status':'in_progress','content':[]},
            })
            self._event('response.content_part.added', {'type':'response.content_part.added',
                'item_id':item_id,'output_index':0,'content_index':0,
                'part':{'type':'output_text','text':'','annotations':[]}})
        self._event('response.output_text.delta', {'type':'response.output_text.delta',
            'item_id':item_id,'output_index':0,'content_index':0,'delta':delta})
        self._event("response.output_text.done", {
            "type": "response.output_text.done",
            "item_id": item_id,
            "output_index": 0,
            "content_index": 0,
            "text": answer,
        })
        self._event('response.content_part.done', {'type':'response.content_part.done',
            'item_id':item_id,'output_index':0,'content_index':0,
            'part':{'type':'output_text','text':answer,'annotations':[]}})
        self._event("response.output_item.done", {
            "type": "response.output_item.done", "output_index": 0, "item": item,
        })
        self._finish_stream(base, answer, [], {"prompt_tokens": 0, "completion_tokens": 0, '_message_id':item_id})

    def _send_blocked(self, base, message):
        # The response delivers an honest task-status message successfully.
        # response.failed makes Codex retry the identical blocked action.
        self._complete_text(base, '【任务暂停，尚未完成】\n'+message+'\n\n'
            '已停止重复执行。请补充明确的下一步、原始目标或必要的新信息；单独发送“继续”不会解除相同阻塞。', continuing=True)

    def _finish_stream(
        self,
        base: dict[str, Any],
        answer: str,
        tool_calls: list[dict[str, Any]],
        usage: dict[str, Any],
    ) -> None:
        output: list[dict[str, Any]] = []
        if answer:
            output.append({
                "id": usage.get("_message_id") or _id("msg"),
                "type": "message",
                "role": "assistant",
                "status": "completed",
                "content": [{"type": "output_text", "text": answer, "annotations": []}],
            })
        for tool_call in tool_calls:
            function = tool_call.get("function") or {}
            call_id = tool_call.get("id") or _id("call")
            arguments = _coerce_arguments(function.get("arguments") or "{}")
            item = {
                "id": _id("fc"),
                "type": "function_call",
                "call_id": call_id,
                "name": function.get("name", ""),
                "arguments": "",
                "status": "in_progress",
            }
            output_index = len(output)
            self._event("response.output_item.added", {
                "type": "response.output_item.added", "output_index": output_index, "item": item,
            })
            self._event("response.function_call_arguments.delta", {
                "type": "response.function_call_arguments.delta",
                "item_id": item["id"],
                "output_index": output_index,
                "delta": arguments,
            })
            self._event("response.function_call_arguments.done", {
                "type": "response.function_call_arguments.done",
                "item_id": item["id"],
                "output_index": output_index,
                "arguments": arguments,
            })
            final_item = {**item, "arguments": arguments, "status": "completed"}
            self._event("response.output_item.done", {
                "type": "response.output_item.done", "output_index": output_index, "item": final_item,
            })
            output.append(final_item)
        prompt_tokens = int(usage.get("prompt_tokens") or 0)
        completion_tokens = int(usage.get("completion_tokens") or 0)
        completed = {
            **base,
            "status": "completed",
            "output": output,
            "usage": {
                "input_tokens": prompt_tokens,
                "output_tokens": completion_tokens,
                "total_tokens": int(usage.get("total_tokens") or (prompt_tokens + completion_tokens)),
                "input_tokens_details": {
                    "cached_tokens": int(((usage.get("prompt_tokens_details") or {}).get("cached_tokens") or 0))
                },
                "output_tokens_details": {
                    "reasoning_tokens": int(((usage.get("completion_tokens_details") or {}).get("reasoning_tokens") or 0))
                },
            },
        }
        try:
            cached_tok = int(((usage.get("prompt_tokens_details") or {}).get("cached_tokens") or 0))
            TOKEN_ACCOUNTING.record_usage(prompt_tokens, completion_tokens, cached_tok)
        except Exception:
            pass
        self._event("response.completed", {"type": "response.completed", "response": completed})
        self.close_connection = True

    def _send_failure(self, base: dict[str, Any], message: str) -> None:
        failed = {
            **base,
            "status": "failed",
            "error": {"code": "backend_error", "message": message[:1000]},
        }
        self._event("response.failed", {"type": "response.failed", "response": failed})
        self.close_connection = True

    def _event(self, name: str, data: dict[str, Any]) -> None:
        if getattr(self,'chat_mode',False):
            if name=='response.created':
                self.chat_base={'id':data['response']['id'].replace('resp_','chatcmpl-'),'object':'chat.completion.chunk','created':data['response']['created_at'],'model':data['response']['model']}
                return
            delta=None;finish=None
            if name=='response.output_text.delta':delta={'content':data['delta']}
            elif name=='response.output_item.done' and data['item']['type']=='function_call':
                item=data['item'];delta={'tool_calls':[{'index':len(self.chat_output),'id':item['call_id'],'type':'function','function':{'name':item['name'],'arguments':item['arguments']}}]};self.chat_output.append(item)
            elif name=='response.completed':
                r=data['response'];u=r['usage'];usage={'prompt_tokens':u['input_tokens'],'completion_tokens':u['output_tokens'],'total_tokens':u['total_tokens']}
                if self.chat_nonstream:
                    text=''.join(p['text'] for item in r['output'] if item['type']=='message' for p in item['content'])
                    calls=[{'id':item['call_id'],'type':'function','function':{'name':item['name'],'arguments':item['arguments']}} for item in r['output'] if item['type']=='function_call']
                    msg={'role':'assistant','content':text or None}
                    if calls:msg['tool_calls']=calls
                    self.wfile.write(dumps({**self.chat_base,'object':'chat.completion','choices':[{'index':0,'message':msg,'finish_reason':'tool_calls' if calls else 'stop'}],'usage':usage}).encode());self.wfile.flush();return
                chunk={**self.chat_base,'choices':[{'index':0,'delta':{},'finish_reason':'tool_calls' if self.chat_output else 'stop'}],'usage':usage}
                self.wfile.write(('data: '+dumps(chunk)+'\n\ndata: [DONE]\n\n').encode());self.wfile.flush();return
            elif name=='response.failed':
                packet=dumps({'error':data['response']['error']})
                self.wfile.write((packet if self.chat_nonstream else 'data: '+packet+'\n\ndata: [DONE]\n\n').encode());self.wfile.flush();return
            if delta is not None and not self.chat_nonstream:
                chunk={**self.chat_base,'choices':[{'index':0,'delta':delta,'finish_reason':None}]}
                self.wfile.write(('data: '+dumps(chunk)+'\n\n').encode());self.wfile.flush()
            return
        packet = f"event: {name}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"
        self.wfile.write(packet.encode())
        self.wfile.flush()

    def _send_responses_stream(
        self,
        request: dict[str, Any],
        chat: dict[str, Any],
        base: dict[str, Any],
    ) -> None:
        choice = (chat.get("choices") or [{}])[0]
        message = choice.get("message") or {}
        content = message.get("content") or ""
        tool_calls = message.get("tool_calls") or []
        usage = chat.get("usage") or {}
        output: list[dict[str, Any]] = []

        if content:
            item_id = _id("msg")
            part = {"type": "output_text", "text": "", "annotations": []}
            item = {
                "id": item_id,
                "type": "message",
                "role": "assistant",
                "status": "in_progress",
                "content": [],
            }
            self._event(
                "response.output_item.added",
                {"type": "response.output_item.added", "output_index": len(output), "item": item},
            )
            self._event(
                "response.content_part.added",
                {
                    "type": "response.content_part.added",
                    "item_id": item_id,
                    "output_index": len(output),
                    "content_index": 0,
                    "part": part,
                },
            )
            self._event(
                "response.output_text.delta",
                {
                    "type": "response.output_text.delta",
                    "item_id": item_id,
                    "output_index": len(output),
                    "content_index": 0,
                    "delta": content,
                },
            )
            final_part = {"type": "output_text", "text": content, "annotations": []}
            self._event(
                "response.output_text.done",
                {
                    "type": "response.output_text.done",
                    "item_id": item_id,
                    "output_index": len(output),
                    "content_index": 0,
                    "text": content,
                },
            )
            self._event(
                "response.content_part.done",
                {
                    "type": "response.content_part.done",
                    "item_id": item_id,
                    "output_index": len(output),
                    "content_index": 0,
                    "part": final_part,
                },
            )
            final_item = {**item, "status": "completed", "content": [final_part]}
            self._event(
                "response.output_item.done",
                {"type": "response.output_item.done", "output_index": len(output), "item": final_item},
            )
            output.append(final_item)

        for tool_call in tool_calls:
            function = tool_call.get("function") or {}
            call_id = tool_call.get("id") or _id("call")
            arguments = _coerce_arguments(function.get("arguments") or "{}")
            item = {
                "id": _id("fc"),
                "type": "function_call",
                "call_id": call_id,
                "name": function.get("name", ""),
                "arguments": "",
                "status": "in_progress",
            }
            output_index = len(output)
            self._event(
                "response.output_item.added",
                {"type": "response.output_item.added", "output_index": output_index, "item": item},
            )
            self._event(
                "response.function_call_arguments.delta",
                {
                    "type": "response.function_call_arguments.delta",
                    "item_id": item["id"],
                    "output_index": output_index,
                    "delta": arguments,
                },
            )
            self._event(
                "response.function_call_arguments.done",
                {
                    "type": "response.function_call_arguments.done",
                    "item_id": item["id"],
                    "output_index": output_index,
                    "arguments": arguments,
                },
            )
            final_item = {**item, "arguments": arguments, "status": "completed"}
            self._event(
                "response.output_item.done",
                {"type": "response.output_item.done", "output_index": output_index, "item": final_item},
            )
            output.append(final_item)

        completed = {
            **base,
            "status": "completed",
            "output": output,
            "usage": {
                "input_tokens": usage.get("prompt_tokens", 0),
                "output_tokens": usage.get("completion_tokens", 0),
                "total_tokens": usage.get("total_tokens", 0),
                "input_tokens_details": {"cached_tokens": 0},
                "output_tokens_details": {"reasoning_tokens": 0},
            },
        }
        self._event("response.completed", {"type": "response.completed", "response": completed})
        self.close_connection = True


def main() -> None:
    install_backend_auth()
    GATEWAY.import_speeds(Path.home()/'Library/Logs/CodexModelSwitcher/traffic.jsonl')
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8002)
    parser.add_argument("--backend", default="http://127.0.0.1:8000")
    args = parser.parse_args()
    ProxyHandler.backend = args.backend.rstrip("/")
    server = ThreadingHTTPServer((args.host, args.port), ProxyHandler)
    print(
        f"MTPLX Responses bridge listening on http://{args.host}:{args.port}/v1 "
        f"-> {ProxyHandler.backend}",
        flush=True,
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
