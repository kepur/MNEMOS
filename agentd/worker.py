"""Worker session loop.

One session = one fresh, append-only conversation for one task:
    [system] [task card] (assistant tool call, tool result)*
Every reply should be a tool call; a reply without one gets an appended nudge
and two in a row end the session, so a reply that only
announces the next step cannot end the task. Completion is decided by the
acceptance command, not by the model. Guards end a session that loops; the
orchestrator decides what happens next from the ledger.
"""
from __future__ import annotations

import collections
import dataclasses
import json
import time

from . import prompts
from .llm import ModelError
from .tools import CONTROL, SCHEMAS, ToolError, parse_arguments


@dataclasses.dataclass
class Verification:
    passed: bool
    exit_code: int | None
    output: str
    attempts_left: int
    skipped: bool = False


@dataclasses.dataclass
class Outcome:
    kind: str  # done | unverified | attempts_exhausted | blocked | handoff | loop | no_action | error
    data: dict
    rounds: int
    changed: list
    last_verify: Verification | None = None


def _short(value, limit=120):
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    text = ' '.join(text.split())
    return text if len(text) <= limit else text[:limit - 1] + '…'


def _call_label(name, args, root=''):
    if root:
        prefix = str(root).rstrip('/') + '/'
        args = {k: (v[len(prefix):] if isinstance(v, str) and v.startswith(prefix) else v) for k, v in args.items()}
        if isinstance(args.get('command'), str):
            args['command'] = args['command'].replace(prefix, '').replace('cd ' + prefix.rstrip('/') + ' && ', '')
    if name == 'read_file':
        rng = f":{args.get('start_line', 1)}-{args.get('end_line', '')}" if args.get('start_line') or args.get('end_line') else ''
        return f"read_file {args.get('path')}{rng}"
    if name == 'run':
        return f"run `{_short(args.get('command', ''), 80)}`"
    if name in ('edit_file', 'write_file', 'list_files'):
        return f"{name} {args.get('path', '.')}"
    if name == 'search':
        return f"search /{_short(args.get('pattern', ''), 40)}/ {args.get('path', '.')}"
    return name


class Worker:
    def __init__(self, client, toolbox, ledger, config, log=print, priority=5):
        self.client = client
        self.toolbox = toolbox
        self.ledger = ledger
        self.config = config
        self.log = log
        self.priority = priority

    def run_session(self, *, task_id, seq, card, verify, role='coder'):
        cfg = self.config
        session_id = self.ledger.start_session(task_id, seq, role)
        messages = [{'role': 'system', 'content': prompts.SYSTEM}, {'role': 'user', 'content': card}]
        budget = int(cfg['input_budget'])
        rounds_limit = int(cfg['rounds_per_session'])
        seen = {}                       # (name, args) -> (round, state_key)
        repeats = 0
        no_action = 0
        edits = collections.Counter()   # path -> edits since last successful run
        changed = set()
        forced = None
        appended_chars = 0
        last_prompt = last_completion = first_prompt = 0
        last_verify = None
        tag = f'[{task_id[-5:]} s{seq}'

        def end(kind, data=None, rounds=0):
            self.ledger.end_session(session_id, kind)
            return Outcome(kind, data or {}, rounds, sorted(changed), last_verify)

        def ask_handoff(text):
            nonlocal forced, appended_chars
            messages.append({'role': 'user', 'content': text})
            appended_chars += len(text)
            forced = 'handoff'
            self.ledger.event(task_id, session_id, round_no, 'guard', {'kind': 'handoff_requested', 'text': text})

        for round_no in range(1, rounds_limit + 2):
            # Budget check before each request: previous prompt + its output +
            # what was appended since (rough chars-per-token for code/English).
            # A handoff only helps once the session holds more than its card,
            # otherwise a large card would hand off forever.
            estimate = last_prompt + last_completion + appended_chars // 3
            grown = estimate - first_prompt >= budget * 0.25
            if forced is None and last_prompt and grown and estimate >= budget * float(cfg['handoff_ratio']):
                ask_handoff(prompts.HANDOFF_BUDGET.format(used=estimate, budget=budget))
            elif forced is None and round_no >= rounds_limit:
                ask_handoff(prompts.HANDOFF_ROUNDS.format(rounds=rounds_limit))
            # tool_choice is fixed for the whole session: MTPLX renders it into
            # the first system message. 'auto' (default) keeps the restored
            # prefix stable across rounds (measured with bench/cache_probe.py);
            # a reply without a tool call gets an appended nudge instead.
            # The handoff request travels as an appended user message.
            try:
                reply = self._chat(session_id, messages, cfg['tool_choice'])
            except ModelError as exc:
                self.ledger.event(task_id, session_id, round_no, 'error', {'message': str(exc)})
                return end('error', {'message': str(exc)}, round_no)
            usage = reply.usage
            self.ledger.add_usage(session_id, usage, reply.elapsed_s)
            last_prompt = int(usage.get('prompt_tokens') or 0)
            last_completion = int(usage.get('completion_tokens') or 0)
            first_prompt = first_prompt or last_prompt
            appended_chars = 0
            messages.append(reply.history_message())
            self.ledger.event(task_id, session_id, round_no, 'model', {
                'prompt_tokens': last_prompt, 'cached_tokens': usage.get('cached_tokens'),
                'completion_tokens': last_completion, 'elapsed_s': round(reply.elapsed_s, 2),
                'finish_reason': reply.finish_reason, 'content': _short(reply.message.get('content') or '', 300)})
            meter = (f"prompt {last_prompt} (cached {usage.get('cached_tokens', 0)}) "
                     f"out {last_completion} {reply.elapsed_s:.1f}s")

            calls = reply.tool_calls
            if not calls:
                no_action += 1
                self.log(f'{tag} r{round_no}] no tool call | {meter}')
                self.ledger.event(task_id, session_id, round_no, 'guard', {'kind': 'no_action', 'count': no_action})
                if no_action >= int(cfg['no_action_limit']):
                    return end('no_action', {'content': reply.message.get('content') or ''}, round_no)
                messages.append({'role': 'user', 'content': prompts.NUDGE})
                appended_chars += len(prompts.NUDGE)
                continue
            no_action = 0

            for call in calls:
                fn = call.get('function') or {}
                name = fn.get('name') or ''
                call_id = call.get('id') or f'call_{round_no}'
                try:
                    args = parse_arguments(fn.get('arguments'))
                except ToolError as exc:
                    self._tool_result(messages, call_id, f'error: {exc}')
                    appended_chars += 80
                    continue

                if name in CONTROL:
                    if name == 'finish':
                        last_verify = verify(args)
                        self.ledger.event(task_id, session_id, round_no, 'verify', {
                            'passed': last_verify.passed, 'exit_code': last_verify.exit_code,
                            'skipped': last_verify.skipped, 'summary': _short(args.get('summary', ''), 400),
                            'output': last_verify.output[-1500:]})
                        self.log(f'{tag} r{round_no}] finish → acceptance '
                                 f'{"skipped" if last_verify.skipped else "exit " + str(last_verify.exit_code)} | {meter}')
                        if last_verify.skipped:
                            self._tool_result(messages, call_id, prompts.NO_ACCEPT)
                            return end('unverified', args, round_no)
                        if last_verify.passed:
                            self._tool_result(messages, call_id, prompts.VERIFY_PASSED)
                            return end('done', args, round_no)
                        if last_verify.attempts_left <= 0:
                            return end('attempts_exhausted', args, round_no)
                        text = prompts.VERIFY_FAILED.format(code=last_verify.exit_code, left=last_verify.attempts_left,
                                                            output=last_verify.output)
                        self._tool_result(messages, call_id, text)
                        appended_chars += len(text)
                        edits.clear()
                        continue
                    self.log(f'{tag} r{round_no}] {name}: {_short(args, 160)} | {meter}')
                    if name == 'report_blocked':
                        return end('blocked', args, round_no)
                    return end('handoff', args, round_no)

                if forced == 'handoff':
                    # The model ignored the handoff request; end here and let the
                    # orchestrator build the handoff from the ledger.
                    return end('handoff', {}, round_no)

                key = (name, json.dumps(args, sort_keys=True, ensure_ascii=False))
                state = self.toolbox.state_key(name, args)
                previous = seen.get(key)
                if state is not None and previous and previous[1] == state:
                    repeats += 1
                    text = prompts.DUPLICATE.format(round=previous[0])
                    self._tool_result(messages, call_id, text)
                    appended_chars += len(text)
                    self.log(f'{tag} r{round_no}] duplicate {_call_label(name, args, self.toolbox.root)} ({repeats}) | {meter}')
                    self.ledger.event(task_id, session_id, round_no, 'guard',
                                      {'kind': 'duplicate', 'call': _call_label(name, args, self.toolbox.root), 'count': repeats})
                    if repeats >= int(cfg['repeat_limit']):
                        return end('loop', {'call': _call_label(name, args, self.toolbox.root), 'repeats': repeats}, round_no)
                    continue

                started = time.monotonic()
                result = self.toolbox.execute(name, args)
                spent = time.monotonic() - started
                self.ledger.add_tool_time(session_id, spent)
                # Record the state after execution: a later identical call is a
                # duplicate only if nothing it depends on changed in between.
                if state is not None:
                    seen[key] = (round_no, self.toolbox.state_key(name, args))
                text = result.text
                for path in result.changed:
                    changed.add(path)
                    if name in ('edit_file', 'write_file'):
                        edits[path] += 1
                        if edits[path] >= int(cfg['edits_before_verify']):
                            text += prompts.EDIT_WARNING.format(path=path, count=edits[path])
                if name == 'run' and result.exit_code == 0:
                    edits.clear()
                self._tool_result(messages, call_id, text)
                appended_chars += len(text)
                status = 'ok' if result.ok else ('exit ' + str(result.exit_code) if result.exit_code is not None else 'error')
                self.log(f'{tag} r{round_no}] {_call_label(name, args, self.toolbox.root)} → {status} ({spent:.1f}s) | {meter}')
                self.ledger.event(task_id, session_id, round_no, 'tool', {
                    'call': _call_label(name, args, self.toolbox.root), 'ok': result.ok, 'exit_code': result.exit_code,
                    'changed': list(result.changed), 'seconds': round(spent, 2), 'result': _short(text, 300)})

        return end('handoff', {}, rounds_limit)

    def _chat(self, session_id, messages, choice):
        attempts = 0
        while True:
            try:
                return self.client.chat(session_id=session_id, messages=messages, tools=SCHEMAS,
                                        tool_choice=choice, max_tokens=int(self.config['max_output_tokens']),
                                        priority=self.priority)
            except ModelError as exc:
                attempts += 1
                if not exc.retryable or attempts > 2:
                    raise
                time.sleep(5 * attempts)

    @staticmethod
    def _tool_result(messages, call_id, text):
        messages.append({'role': 'tool', 'tool_call_id': call_id, 'content': text})
