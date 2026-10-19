"""Model gateway core: client identity, single-lane scheduling, speed stats.

The gateway is a pass-through. It never rewrites, compacts or reorders the
client's history, never injects evidence and never memoises a refusal: the
backend session bank can only reuse an exact token prefix (the hybrid Qwen
models cannot roll a recurrent state back), so any rewrite turns the next
request into a full prefill. Context limits are the client's job (Codex
auto-compact); long autonomous work belongs to agentd, which owns its loop.
"""
from __future__ import annotations
import contextlib
import fcntl
import dataclasses
import hashlib
import json
import os
import re
import sqlite3
import threading
import time
import uuid
from pathlib import Path

ROOT = Path.home() / '.local/share/codex-local-gateway'
DEFAULTS = dict(context_length=131072, max_subagents=2, max_depth=1)


def dumps(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))


def digest(value):
    return hashlib.sha256((value if isinstance(value, str) else dumps(value)).encode()).hexdigest()


def plain(value):
    if isinstance(value, str): return value
    if isinstance(value, list):
        return '\n'.join(str(x.get('text', '')) if isinstance(x, dict) else str(x) for x in value)
    return dumps(value)


def cwd_from(messages):
    for m in messages:
        txt = plain(m.get('content', ''))
        match = re.search(r'<cwd>([^<]+)</cwd>', txt)
        if match and Path(match[1]).is_absolute(): return str(Path(match[1]).resolve())
    return ''


def tool_ok(content):
    text = plain(content)
    for pattern in [r'Process exited with code\s+(-?\d+)', r'(?:Exit|exit) code:\s*(-?\d+)']:
        match = re.search(pattern, text)
        if match: return int(match[1]) == 0
    try:
        value = json.loads(text)
        if isinstance(value, dict) and 'exit_code' in value: return value['exit_code'] == 0
    except ValueError: pass
    return None


@dataclasses.dataclass(frozen=True)
class Identity:
    thread: str
    agent: str = '/root'
    turn: str = ''
    cwd: str = ''
    persistent: bool = True

    @property
    def key(self): return digest([self.thread, self.agent])[:32]
    @property
    def child(self): return len(self.agent.strip('/').split('/')) > 1
    @property
    def depth(self): return max(0, len(self.agent.strip('/').split('/')) - 1)

    @classmethod
    def resolve(cls, headers, payload, messages):
        hdr = {k.lower(): v for k, v in headers.items()}
        try: meta = json.loads(hdr.get('x-codex-turn-metadata', '{}'))
        except (ValueError, TypeError): meta = {}
        if not isinstance(meta, dict): meta = {}
        thread = hdr.get('thread-id') or meta.get('thread_id') or hdr.get('session-id') or meta.get('session_id')
        if hdr.get('x-opencode-session'):thread='opencode-'+hdr['x-opencode-session']
        # Explicit application registration is also supported. Never use prompt hashes.
        registered = payload.get('gateway_task') or {}
        if not isinstance(registered, dict): registered = {}
        thread = thread or registered.get('thread_id')
        if not thread:
            # Generic per-session keys: Qwen Code sends prompt_cache_key,
            # other clients an x-session-id style header.
            key = hdr.get('x-session-id') or hdr.get('x-session-affinity') or payload.get('prompt_cache_key')
            # Claude Code: metadata.user_id = "user_<id>_account_<id>_session_<uuid>".
            user = (payload.get('metadata') or {}).get('user_id') if isinstance(payload.get('metadata'), dict) else None
            match = re.search(r'_session_([\w-]+)$', user) if isinstance(user, str) else None
            key = key or (match[1] if match else None)
            if isinstance(key, str) and key.strip(): thread = 'client-' + key.strip()
        actor = hdr.get('x-local-agent-name') or meta.get('agent_name') or registered.get('agent_name') or '/root'
        if not isinstance(actor, str) or len(actor) > 256: actor = '/root'
        persistent = isinstance(thread, str) and bool(thread) and len(thread) <= 256
        return cls(thread if persistent else 'ephemeral-' + uuid.uuid4().hex,
                   actor, str(meta.get('root_turn_id') or meta.get('turn_id') or ''),
                   hdr.get('x-local-cwd') or cwd_from(messages), persistent)


OMLX_SETTINGS = Path.home() / '.omlx/settings.json'
_omlx_cache = {'mtime': None, 'port': 7777, 'key': ''}


def omlx_endpoint():
    """(port, api key) of the local oMLX server, re-read when its settings change.

    The key stays in oMLX's own 0600 settings file; nothing here copies or logs it.
    """
    try:
        mtime = OMLX_SETTINGS.stat().st_mtime
    except OSError:
        return _omlx_cache['port'], ''
    if mtime != _omlx_cache['mtime']:
        try:
            data = json.loads(OMLX_SETTINGS.read_text(encoding='utf-8'))
            _omlx_cache.update(mtime=mtime, port=int((data.get('server') or {}).get('port') or 7777),
                               key=str((data.get('auth') or {}).get('api_key') or ''))
        except (OSError, ValueError):
            _omlx_cache.update(mtime=mtime, key='')
    return _omlx_cache['port'], _omlx_cache['key']


def install_backend_auth():
    """Make every urllib request to the local oMLX server carry its API key.

    oMLX refuses unauthenticated inference; MTPLX, LM Studio and Bonsai need no
    key, so the handler only touches requests addressed to oMLX's loopback port.
    """
    import urllib.request
    from urllib.parse import urlsplit

    class OmlxAuth(urllib.request.BaseHandler):
        handler_order = 400

        def http_request(self, request):
            port, key = omlx_endpoint()
            url = urlsplit(request.full_url)
            if key and url.hostname in ('127.0.0.1', 'localhost') and url.port == port \
                    and not request.has_header('Authorization'):
                request.add_unredirected_header('Authorization', 'Bearer ' + key)
            return request

        https_request = http_request

    urllib.request.install_opener(urllib.request.build_opener(OmlxAuth()))


class Blocked(RuntimeError): pass
class Cancelled(RuntimeError): pass


@contextlib.contextmanager
def gpu_lease(cancelled=lambda: False, waiting=lambda: None):
    """One inference across gateway and agentd processes; tools hold no lock."""
    path = Path.home() / '.local/state/codex-local-gateway/gpu.lock'
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a') as lock:
        while True:
            if cancelled(): raise Cancelled('GPU queue cancelled')
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                waiting()
                time.sleep(0.1)
        try: yield
        finally: fcntl.flock(lock, fcntl.LOCK_UN)


class SerialQueue:
    """FIFO at request boundaries; no speculative GPU batch or unsafe preemption."""
    def __init__(self):
        self.cv = threading.Condition()
        self.waiting = []
        self.active = None
        self.peak = 0
        self.completed = 0

    def snapshot(self):
        with self.cv:
            return {'active': int(self.active is not None), 'queued': len(self.waiting),
                    'peak_active': self.peak, 'completed': self.completed,
                    'max_active': 1}

    @contextlib.contextmanager
    def lease(self, identity, request_id, cancelled, heartbeat, max_children=2, max_depth=1):
        job = {'id': request_id, 'thread': identity.thread, 'agent': identity.agent, 'child': identity.child}
        if identity.depth > max_depth:
            raise Blocked('子任务嵌套超过配置上限，需由主任务重新分配。')
        admitted = False
        acquired = False
        start = time.monotonic()
        try:
            with self.cv:
                jobs = self.waiting + ([self.active] if self.active else [])
                agents = {(j['thread'],j['agent']) for j in jobs if j['child']}
                if identity.child and (identity.thread,identity.agent) not in agents and len(agents) >= max_children:
                    raise Blocked('同时活跃的本地子任务已达到上限。')
                self.waiting.append(job); admitted = True
            while True:
                if cancelled(): raise Cancelled('排队任务已取消。')
                with self.cv:
                    if self.active is None and self.waiting and self.waiting[0] is job:
                        self.waiting.pop(0); self.active = job; acquired = True
                        self.peak = max(self.peak, 1)
                        break
                    position = self.waiting.index(job) + 1
                    self.cv.wait(timeout=0.5)
                heartbeat(position, round(time.monotonic() - start, 3))
            with gpu_lease(cancelled, lambda: heartbeat(1, round(time.monotonic() - start, 3))):
                yield round(time.monotonic() - start, 3)
        finally:
            with self.cv:
                if acquired and self.active is job:
                    self.active = None; self.completed += 1
                elif admitted and job in self.waiting: self.waiting.remove(job)
                self.cv.notify_all()


class Store:
    """Speed history only. Older state tables in the file are left untouched."""
    def __init__(self, root=ROOT):
        self.root = Path(root); self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.root, 0o700)
        self.path = self.root/'state-v3.sqlite3'; self._init()
        os.chmod(self.path, 0o600)

    def connect(self):
        conn = sqlite3.connect(self.path, timeout=20)
        conn.row_factory = sqlite3.Row
        conn.execute('PRAGMA busy_timeout=20000')
        return conn

    def _init(self):
        with self.connect() as c:
            c.execute('PRAGMA journal_mode=WAL')
            c.execute('CREATE TABLE IF NOT EXISTS speeds (id TEXT PRIMARY KEY, model TEXT, input INTEGER, output INTEGER, prefill REAL, decode REAL, ttft REAL, created REAL)')

    def record_speed(self,model,usage,request_id):
        model=str(model or '').lower().removeprefix('local/')
        if not model or model=='test-model':return
        inp=int(usage.get('prompt_tokens') or 0);out=int(usage.get('completion_tokens') or 0)
        pre=float(usage.get('prefill_tok_s') or 0);decode=float(usage.get('decode_tok_s') or 0)
        if pre<=0 and decode<=0:return
        with self.connect() as c:c.execute('INSERT OR IGNORE INTO speeds VALUES (?,?,?,?,?,?,?,?)',
            (request_id,model,inp,out,pre,decode,float(usage.get('ttft_s') or 0),time.time()))

    def speeds(self):
        with self.connect() as c:
            rows=c.execute('SELECT model,count(*) samples,sum(CASE WHEN decode>0 THEN output ELSE 0 END) output,sum(CASE WHEN decode>0 THEN output/decode ELSE 0 END) decode_s,sum(CASE WHEN prefill>0 THEN input ELSE 0 END) input,sum(CASE WHEN prefill>0 THEN input/prefill ELSE 0 END) prefill_s FROM speeds GROUP BY model').fetchall()
            return {r['model']:{'samples':r['samples'],'decode_tok_s':r['output']/r['decode_s'] if r['decode_s'] else None,
                              'prefill_tok_s':r['input']/r['prefill_s'] if r['prefill_s'] else None} for r in rows}


class Gateway:
    def __init__(self, root=ROOT):
        self.root=Path(root);self.store=Store(self.root);self.queue=SerialQueue()

    def import_speeds(self,path):
        if not Path(path).exists():return
        with self.store.connect() as c:
            for line in Path(path).open(encoding='utf-8',errors='replace'):
                try:r=json.loads(line)
                except ValueError:continue
                if r.get('kind')!='done' or r.get('recovery_attempts'):continue
                model=str(r.get('model') or '').lower().removeprefix('local/')
                if not model or model=='test-model':continue
                pre=float(r.get('prefill_tok_s') or 0);dec=float(r.get('decode_tok_s') or 0)
                if pre<=0 and dec<=0:continue
                c.execute('INSERT OR IGNORE INTO speeds VALUES (?,?,?,?,?,?,?,?)',
                          (r['id'],model,int(r.get('prompt_tokens') or 0),int(r.get('completion_tokens') or 0),pre,dec,float(r.get('ttft_s') or 0),r.get('ts') or time.time()))

    def prepare(self, identity, messages, body, emit):
        """Forward the client's history unchanged; attach the cache identity."""
        recent_tools=[]
        for m in reversed(messages):
            if m.get('role')!='tool':break
            recent_tools.append(m)
        if recent_tools:emit({'kind':'tool_result','count':len(recent_tools),'success':sum(tool_ok(m.get('content')) is True for m in recent_tools),'agent_name':identity.agent})
        # Backend cache identity must match the application session isolation.
        # Without a known identity, leave it to the backend to match the
        # session by prompt prefix; a random id per request would defeat it.
        body=dict(body)
        if identity.persistent:
            body['metadata']={'session_id':identity.key, 'thread_id':identity.thread,'agent_name':identity.agent}
        return body

    def policy_calls(self,identity,calls):
        for call in calls:
            fn=call.get('function') or {}
            if fn.get('name','').split('.')[-1] not in ('spawn_agent','spawn'):continue
            if identity.child:raise Blocked('本地子任务不得再创建子任务，请把分工回传给主任务。')
            args=json.loads(fn.get('arguments') or '{}')
            # Codex's native variants have different field names.
            if 'fork_context' in args:args['fork_context']=False
            if 'fork_turns' in args:args['fork_turns']='none'
            schema_hint='\n只执行以上分配目标。按需读取指定文件，返回结果、修改文件、验证结果及未解决事项。'
            if isinstance(args.get('message'),str):args['message']+=schema_hint
            fn['arguments']=json.dumps(args,ensure_ascii=False)
        return calls

    def status(self):return {'queue':self.queue.snapshot(),'defaults':DEFAULTS,'speeds':self.store.speeds(),'context_policy':'append_only'}
