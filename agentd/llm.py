"""Model client: OpenAI chat completions against the active local backend.

One process-wide lane serialises inference (the GPU is shared); tools run
outside the lane. Each worker session has its own stable session id so the
backend's session bank can restore its exact token prefix. Callers keep the
message list append-only; this module never rewrites history.
"""
from __future__ import annotations

import dataclasses
import heapq
import itertools
import json
import os
import threading
import time
import urllib.error
import urllib.request
import uuid

from . import config as cfg
from gateway_core import gpu_lease, install_backend_auth

install_backend_auth()  # oMLX requires its API key; other backends are untouched


def traffic(event):
    """Append to the switcher's activity log (best effort; never fails a request)."""
    try:
        cfg.TRAFFIC.parent.mkdir(parents=True, exist_ok=True)
        with cfg.TRAFFIC.open('a', encoding='utf-8') as sink:
            sink.write(json.dumps({**event, 'ts': time.time()}, ensure_ascii=False) + '\n')
    except OSError:
        pass


class ModelError(RuntimeError):
    def __init__(self, message, status=None, retryable=False):
        super().__init__(message)
        self.status = status
        self.retryable = retryable


@dataclasses.dataclass
class Reply:
    message: dict
    finish_reason: str
    usage: dict
    elapsed_s: float

    @property
    def tool_calls(self):
        return self.message.get('tool_calls') or []

    def history_message(self):
        """The assistant turn exactly as generated, for the next request.

        reasoning_content is echoed back so the backend can match the
        committed tokens (dropping it would fork the cached prefix).
        """
        item = {'role': 'assistant', 'content': self.message.get('content') or ''}
        if self.message.get('reasoning_content'):
            item['reasoning_content'] = self.message['reasoning_content']
        if self.tool_calls:
            item['tool_calls'] = self.tool_calls
        return item


class Lane:
    """Priority lane: one model request at a time, lower number first,
    FIFO within a priority."""

    def __init__(self):
        self.cv = threading.Condition()
        self.heap = []
        self.busy = False
        self.counter = itertools.count()

    def acquire(self, priority=5):
        ticket = (priority, next(self.counter))
        with self.cv:
            heapq.heappush(self.heap, ticket)
            while self.busy or self.heap[0] != ticket:
                self.cv.wait()
            heapq.heappop(self.heap)
            self.busy = True

    def release(self):
        with self.cv:
            self.busy = False
            self.cv.notify_all()


LANE = Lane()


class ModelClient:
    def __init__(self, runtime=None, lane=LANE):
        self.runtime = runtime if runtime is not None else cfg.runtime()
        self.backend = str(self.runtime.get('backend_url') or 'http://127.0.0.1:8000').rstrip('/')
        self.kind = self.runtime.get('backend') or 'mtplx'
        self.lane = lane
        self._model = None

    @property
    def model(self):
        if self._model is None:
            try:
                with urllib.request.urlopen(self.backend + '/v1/models', timeout=10) as r:
                    data = json.load(r).get('data') or []
                ids = [m['id'] for m in data]
                wanted = self.runtime.get('pinned_model')
                if wanted and wanted not in ids:
                    raise ModelError(f'configured role model {wanted} is not loaded on {self.backend}')
                self._model = wanted or (ids[0] if ids else None)
            except (OSError, ValueError, KeyError, IndexError):
                self._model = None
            if not self._model and self.runtime.get('pinned_model'):
                raise ModelError(f'role model {self.runtime["pinned_model"]} is unavailable at {self.backend}')
            if not self._model:
                self._model = str(self.runtime.get('api_model') or 'local').removeprefix('local/')
        return self._model

    def chat(self, *, session_id, messages, tools, tool_choice='required', max_tokens=8192,
             priority=5, timeout=1800):
        body = {
            'model': self.model,
            'messages': messages,
            'tools': tools,
            'tool_choice': tool_choice,
            'parallel_tool_calls': False,
            'max_tokens': max_tokens,
            'stream': False,
            'metadata': {'session_id': session_id},
        }
        if self.kind == 'lmstudio':
            body['reasoning_effort'] = self.runtime.get('reasoning_effort') or 'medium'
        if self.kind == 'mtplx':
            body['enable_thinking'] = bool(self.runtime.get('enable_thinking', True))
        if self.kind == 'omlx':
            thinking = bool(self.runtime.get('enable_thinking', True))
            body['chat_template_kwargs'] = {'enable_thinking': thinking}
            # K2 reads only reasoning_effort (no off switch); see the gateway.
            body['reasoning_effort'] = (self.runtime.get('reasoning_effort') or 'medium') if thinking else 'low'
        request_id = 'agentd-' + uuid.uuid4().hex[:16]
        request = urllib.request.Request(
            self.backend + '/v1/chat/completions',
            data=json.dumps(body, ensure_ascii=False).encode(),
            headers={'Content-Type': 'application/json',
                     'x-mtplx-session-id': session_id,
                     'x-mtplx-request-id': request_id},
            method='POST')
        self.lane.acquire(priority)
        started = time.monotonic()
        traffic({'kind': 'start', 'id': request_id, 'model': self.model, 'image': False, 'question': '(agentd)',
                 'backend': self.backend, 'thread_id': session_id, 'agent_name': '/agentd/' + str(self.runtime.get('role') or 'coder'), 'client': 'agentd'})
        try:
            with gpu_lease():
                with urllib.request.urlopen(request, timeout=timeout) as response:
                    data = json.load(response)
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors='replace')[:2000]
            traffic({'kind': 'error', 'id': request_id, 'message': f'HTTP {exc.code}: {detail[:500]}'})
            raise ModelError(f'HTTP {exc.code}: {detail}', exc.code, exc.code >= 500) from None
        except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
            traffic({'kind': 'error', 'id': request_id, 'message': str(exc)[:500]})
            raise ModelError(f'backend unreachable: {exc}', retryable=True) from None
        except KeyboardInterrupt:
            traffic({'kind': 'cancelled', 'id': request_id})
            self.cancel(request_id)
            raise
        finally:
            self.lane.release()
        elapsed = time.monotonic() - started
        if data.get('error'):
            error = data['error']
            raise ModelError(error.get('message', str(error)) if isinstance(error, dict) else str(error))
        choice = (data.get('choices') or [{}])[0]
        usage = dict(data.get('usage') or {})
        usage['cached_tokens'] = int((usage.get('prompt_tokens_details') or {}).get('cached_tokens') or 0)
        stats = data.get('mtplx_stats') or {}
        for key in ('ttft_s', 'decode_tok_s', 'prefill_tok_s', 'new_prefill_tokens', 'cache_miss_reason'):
            if key in stats:
                usage[key] = stats[key]
        usage.setdefault('new_prefill_tokens', max(0, int(usage.get('prompt_tokens') or 0) - usage['cached_tokens']))
        reply = Reply(choice.get('message') or {}, choice.get('finish_reason') or '', usage, elapsed)
        if reply.message.get('content'):
            traffic({'kind': 'delta', 'id': request_id, 'text': reply.message['content'][:8000]})
        traffic({'kind': 'done', 'id': request_id, 'model': self.model, 'question': '(agentd)',
                 'answer': (reply.message.get('content') or '')[:400],
                 'prompt_tokens': usage.get('prompt_tokens'), 'completion_tokens': usage.get('completion_tokens'),
                 'decode_tok_s': usage.get('decode_tok_s'), 'prefill_tok_s': usage.get('prefill_tok_s'),
                 'ttft_s': usage.get('ttft_s'), 'elapsed_s': round(elapsed, 3), 'tool_calls': len(reply.tool_calls)})
        if os.environ.get('AGENTD_TRACE'):
            self._trace(os.environ['AGENTD_TRACE'], body, data, stats)
        return reply

    def _trace(self, path, body, data, stats):
        """Debug aid: full request, response and the backend's prefix diagnosis."""
        diagnostic = None
        try:
            with urllib.request.urlopen(self.backend + '/health', timeout=5) as r:
                diagnostic = (json.load(r).get('session_bank') or {}).get('last_prefix_diagnostic')
        except (OSError, ValueError):
            pass
        with open(path, 'a', encoding='utf-8') as sink:
            sink.write(json.dumps({'t': time.time(), 'request': body, 'response': data.get('choices'),
                                   'stats': {k: v for k, v in stats.items() if 'cache' in k or 'prefill' in k
                                             or k in ('session_restore_mode', 'ttft_s')},
                                   'diagnostic': diagnostic}, ensure_ascii=False) + '\n')

    def cancel(self, request_id):
        try:
            urllib.request.urlopen(urllib.request.Request(
                f'{self.backend}/v1/mtplx/cancel/{request_id}', data=b'', method='POST'), timeout=3)
        except OSError:
            pass
