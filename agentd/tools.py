"""Worker tools: few, short schemas, bounded outputs, workspace-confined.

Control tools (finish, report_blocked, handoff) are declared here so the tool
list -- part of the cached prompt prefix -- is identical for every session;
the worker loop handles them instead of execute().
"""
from __future__ import annotations

import dataclasses
import difflib
import hashlib
import json
import os
import re
import signal
import subprocess
from pathlib import Path

SKIP_DIRS = {'.git', '__pycache__', 'node_modules', '.venv', 'venv', '.mypy_cache',
             '.pytest_cache', '.ruff_cache', 'dist', 'build', '.idea', '.tox', '.next'}
READ_LINES = 300
READ_CHARS = 20000
OUTPUT_HEAD = 2500
OUTPUT_TAIL = 6000
# A seatbelt against obvious accidents, not a security boundary.
DENY = re.compile(r'(^|[;&|]\s*)sudo\b|\bgit\s+push\b|\brm\s+-[a-zA-Z]*r[a-zA-Z]*\s+(/|~|\$HOME)(\s|$)')


def _fn(name, description, properties, required):
    return {'type': 'function', 'function': {
        'name': name, 'description': description,
        'parameters': {'type': 'object', 'properties': properties, 'required': required}}}


S = {'type': 'string'}
I = {'type': 'integer'}
SCHEMAS = [
    _fn('read_file', 'Read a text file with line numbers. Use start_line/end_line for large files.',
        {'path': S, 'start_line': I, 'end_line': I}, ['path']),
    _fn('list_files', 'List files under a directory (recursive) with line counts.',
        {'path': S}, []),
    _fn('search', 'Search file contents with a Python regex. Returns path:line: text.',
        {'pattern': S, 'path': S, 'glob': {'type': 'string', 'description': 'e.g. *.py'}}, ['pattern']),
    _fn('edit_file', 'Replace exact text in a file. old_text must match exactly once unless replace_all.',
        {'path': S, 'old_text': S, 'new_text': S, 'replace_all': {'type': 'boolean'}},
        ['path', 'old_text', 'new_text']),
    _fn('write_file', 'Create or overwrite a file with the given content.',
        {'path': S, 'content': S}, ['path', 'content']),
    _fn('run', 'Run a shell command in the workspace root. Returns exit code and output.',
        {'command': S, 'timeout': I}, ['command']),
    _fn('code_outline', 'Get AST outline (classes, functions, signatures, docstrings) of a file without implementation bodies. Saves 85-95% context tokens on large files.',
        {'path': S}, ['path']),
    _fn('code_search_symbol', 'Search symbol definitions (classes, functions, methods, structs) across the entire codebase.',
        {'name': S, 'kind': {'type': 'string', 'description': 'optional filter: class, function, struct, etc.'}}, ['name']),
    _fn('code_callers', 'Find all call sites and usages of a function or class across the workspace.',
        {'symbol': S}, ['symbol']),
    _fn('code_blueprint', 'Get the AOCI high-level architectural blueprint of the workspace (layers, entry points, invariants).',
        {}, []),
    _fn('finish', 'Declare the task complete. The system then runs the acceptance command.',
        {'summary': S, 'evidence': {'type': 'string', 'description': 'what you ran and saw'}},
        ['summary']),
    _fn('report_blocked', 'Stop because the task cannot proceed without outside help.',
        {'reason': S, 'need': S}, ['reason']),
    _fn('handoff', 'Record progress so a fresh session can continue. Only when asked to.',
        {'done': S, 'remaining': S, 'facts': {'type': 'string', 'description': 'confirmed findings, with file:line'},
         'next_step': S}, ['done', 'remaining', 'next_step']),
]
CONTROL = {'finish', 'report_blocked', 'handoff'}


@dataclasses.dataclass
class Result:
    text: str
    ok: bool = True
    changed: tuple = ()
    exit_code: int | None = None


class ToolError(Exception):
    pass


def file_digest(path: Path) -> str:
    try:
        return hashlib.sha1(path.read_bytes()).hexdigest()[:16]
    except OSError:
        return 'missing'


def iter_files(base: Path, glob: str | None = None, limit=20000):
    count = 0
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS and not d.endswith('.egg-info'))
        for name in sorted(filenames):
            path = Path(dirpath) / name
            if glob and not path.match(glob):
                continue
            yield path
            count += 1
            if count >= limit:
                return


def clip_output(text: str) -> str:
    if len(text) <= OUTPUT_HEAD + OUTPUT_TAIL:
        return text
    skipped = len(text) - OUTPUT_HEAD - OUTPUT_TAIL
    return text[:OUTPUT_HEAD] + f'\n[... {skipped} chars omitted ...]\n' + text[-OUTPUT_TAIL:]


class Toolbox:
    def __init__(self, root, run_timeout=180):
        self.root = Path(root).resolve()
        self.run_timeout = run_timeout

    # -- helpers -----------------------------------------------------------
    def path(self, value, must_exist=True) -> Path:
        if not isinstance(value, str) or not value.strip():
            raise ToolError('path is required')
        p = Path(value.strip())
        p = (p if p.is_absolute() else self.root / p).resolve()
        if p != self.root and self.root not in p.parents:
            raise ToolError(f'{value} is outside the workspace {self.root}')
        if must_exist and not p.exists():
            raise ToolError(f'{self.rel(p)} does not exist')
        return p

    def rel(self, p: Path) -> str:
        try:
            return str(p.relative_to(self.root)) or '.'
        except ValueError:
            return str(p)

    def fingerprint(self) -> str:
        """Cheap workspace version: paths, sizes and mtimes."""
        h = hashlib.sha1()
        for p in iter_files(self.root):
            try:
                st = p.stat()
            except OSError:
                continue
            h.update(f'{self.rel(p)}:{st.st_size}:{st.st_mtime_ns}\n'.encode())
        return h.hexdigest()[:16]

    def state_key(self, name, args) -> str | None:
        """What a call's result depends on; equal keys mean an equal result."""
        try:
            if name == 'read_file':
                return file_digest(self.path(args.get('path'), must_exist=False))
            if name in ('list_files', 'search', 'run'):
                return self.fingerprint()
        except ToolError:
            return 'invalid'
        return None  # edits and control tools are never duplicates

    # -- dispatch ----------------------------------------------------------
    def execute(self, name, args) -> Result:
        handler = getattr(self, 'tool_' + name, None)
        if handler is None or name in CONTROL:
            return Result(f'unknown tool {name}', ok=False)
        try:
            return handler(**args)
        except ToolError as exc:
            return Result(f'error: {exc}', ok=False)
        except TypeError as exc:
            return Result(f'error: bad arguments for {name}: {exc}', ok=False)

    # -- tools -------------------------------------------------------------
    def tool_read_file(self, path, start_line=None, end_line=None):
        p = self.path(path)
        if p.is_dir():
            raise ToolError(f'{self.rel(p)} is a directory; use list_files')
        data = p.read_bytes()
        if b'\0' in data[:4096]:
            raise ToolError(f'{self.rel(p)} looks binary')
        lines = data.decode(errors='replace').splitlines()
        total = len(lines)
        start = max(1, int(start_line or 1))
        end = min(total, int(end_line) if end_line else start + READ_LINES - 1)
        if start > max(total, 1):
            raise ToolError(f'start_line {start} is past the end ({total} lines)')
        out, size = [], 0
        for n in range(start, end + 1):
            line = f'{n:5}| {lines[n - 1]}'
            size += len(line) + 1
            if size > READ_CHARS:
                end = n - 1
                break
            out.append(line)
        header = f'{self.rel(p)} (lines {start}-{end} of {total})'
        more = f'\n[more: read_file start_line={end + 1}]' if end < total else ''
        return Result(header + '\n' + '\n'.join(out) + more)

    def tool_list_files(self, path='.'):
        base = self.path(path or '.')
        rows = []
        for p in iter_files(base, limit=400):
            try:
                size = p.stat().st_size
                count = p.read_bytes().count(b'\n') if size < 2_000_000 else None
            except OSError:
                continue
            rows.append(f'{self.rel(p)}  ({count} lines)' if count is not None else f'{self.rel(p)}  ({size} bytes)')
        if not rows:
            return Result(f'{self.rel(base)}: no files')
        more = '\n[listing truncated at 400 files]' if len(rows) >= 400 else ''
        return Result('\n'.join(rows) + more)

    def tool_search(self, pattern, path='.', glob=None):
        try:
            regex = re.compile(pattern)
        except re.error as exc:
            raise ToolError(f'invalid regex: {exc}')
        base = self.path(path or '.')
        files = [base] if base.is_file() else iter_files(base, glob)
        hits = []
        for p in files:
            try:
                if p.stat().st_size > 2_000_000:
                    continue
                text = p.read_text(errors='replace')
            except OSError:
                continue
            for n, line in enumerate(text.splitlines(), 1):
                if regex.search(line):
                    hits.append(f'{self.rel(p)}:{n}: {line.strip()[:200]}')
                    if len(hits) >= 100:
                        return Result('\n'.join(hits) + '\n[first 100 matches only; narrow the search]')
        return Result('\n'.join(hits) if hits else 'no matches')

    def tool_edit_file(self, path, old_text, new_text, replace_all=False):
        p = self.path(path)
        text = p.read_text()
        count = text.count(old_text) if old_text else 0
        if count == 0:
            hint = ''
            first = old_text.strip().splitlines()[0] if old_text.strip() else ''
            if first:
                lines = text.splitlines()
                close = difflib.get_close_matches(first, lines, n=3, cutoff=0.6)
                if close:
                    where = [f'{lines.index(c) + 1}| {c}' for c in close]
                    hint = '\nclosest lines:\n' + '\n'.join(where)
            raise ToolError(f'old_text not found in {self.rel(p)}; read the exact current text first.{hint}')
        if count > 1 and not replace_all:
            at = [text[:m.start()].count('\n') + 1 for m in re.finditer(re.escape(old_text), text)]
            raise ToolError(f'old_text matches {count} times (lines {at[:10]}); add context or set replace_all')
        p.write_text(text.replace(old_text, new_text) if replace_all else text.replace(old_text, new_text, 1))
        start = text[:text.index(old_text)].count('\n') + 1
        return Result(f'edited {self.rel(p)} ({count if replace_all else 1} replacement, starting line {start})',
                      changed=(self.rel(p),))

    def tool_write_file(self, path, content):
        p = self.path(path, must_exist=False)
        p.parent.mkdir(parents=True, exist_ok=True)
        existed = p.exists()
        p.write_text(content)
        lines = content.count('\n') + (0 if content.endswith('\n') or not content else 1)
        return Result(f'{"overwrote" if existed else "created"} {self.rel(p)} ({lines} lines)', changed=(self.rel(p),))

    def tool_run(self, command, timeout=None):
        if not isinstance(command, str) or not command.strip():
            raise ToolError('command is required')
        if DENY.search(command):
            raise ToolError('command refused by the local safety rules (sudo, git push, rm -r of / or ~)')
        limit = min(int(timeout or self.run_timeout), 1800)
        before = self.fingerprint()
        env = {**os.environ, 'PYTHONDONTWRITEBYTECODE': '1', 'GIT_PAGER': 'cat', 'PAGER': 'cat'}
        proc = subprocess.Popen(['/bin/bash', '-c', command], cwd=self.root, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env,
                                start_new_session=True)
        try:
            output, _ = proc.communicate(timeout=limit)
            code = proc.returncode
            note = ''
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            output, _ = proc.communicate()
            code, note = -9, f'\n[timed out after {limit}s]'
        text = clip_output(output.decode(errors='replace'))
        changed = ('*',) if self.fingerprint() != before else ()
        return Result(f'exit_code: {code}{note}\n{text}'.rstrip(), ok=code == 0, changed=changed, exit_code=code)

    def tool_code_outline(self, path):
        from serafina_runtime.code_intelligence import CODE_GRAPH
        p = self.path(path)
        res = CODE_GRAPH.get_outline(str(p))
        if not res.get('ok'):
            raise ToolError(res.get('error', 'failed to parse outline'))
        return Result(res['outline'])

    def tool_code_search_symbol(self, name, kind=None):
        from serafina_runtime.code_intelligence import CODE_GRAPH
        matches = CODE_GRAPH.search_symbols(str(self.root), query=name, kind=kind)
        if not matches:
            return Result(f'no symbols found matching "{name}"')
        lines = [f'Found {len(matches)} symbols:']
        for m in matches:
            parent = f' (in {m["parent"]})' if m.get('parent') else ''
            lines.append(f"  • {m['file']}:{m['line']} [{m['kind']}] {m['name']}{parent} -> {m['signature']}")
        return Result('\n'.join(lines))

    def tool_code_callers(self, symbol):
        from serafina_runtime.code_intelligence import CODE_GRAPH
        callers = CODE_GRAPH.get_callers(str(self.root), symbol=symbol)
        if not callers:
            return Result(f'no call sites found for "{symbol}"')
        lines = [f'Found {len(callers)} call sites for "{symbol}":']
        for c in callers:
            lines.append(f"  • {c['file']}:{c['line']}: {c['code']}")
        return Result('\n'.join(lines))

    def tool_code_blueprint(self):
        from serafina_runtime.code_intelligence import AOCI
        text = AOCI.load_blueprint(str(self.root))
        return Result(text)


def parse_arguments(raw):
    if isinstance(raw, dict):
        return raw
    try:
        value = json.loads(raw or '{}')
    except (TypeError, ValueError) as exc:
        raise ToolError(f'arguments are not valid JSON: {exc}')
    if not isinstance(value, dict):
        raise ToolError('arguments must be a JSON object')
    return value
