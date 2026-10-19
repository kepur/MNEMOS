"""Orchestrator: the task state machine that owns the loop.

For each task it runs worker sessions until the acceptance command passes or
a limit is reached. Every session outcome maps to a definite next step:

    done / unverified    -> task complete
    attempts_exhausted   -> task failed (acceptance kept failing)
    blocked              -> task blocked, reason reported
    handoff/loop/no_act. -> new session from card + handoff, unless the task
                            stalled (no file change in max_stalls sessions)
    error                -> retry once, then fail

One coder owns each goal. Optional bounded Planner/Reviewer roles use the
same ledger and shared GPU lane; multiple simultaneous coders are not enabled.
"""
from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path

from . import prompts
from .ledger import Ledger
from .llm import ModelError
from .team import Team
from .tools import Toolbox, clip_output
from .worker import Verification, Worker


def sh(command, cwd, timeout):
    try:
        env = {**os.environ, 'PYTHONDONTWRITEBYTECODE': '1', 'GIT_PAGER': 'cat', 'PAGER': 'cat'}
        proc = subprocess.run(['/bin/bash', '-c', command], cwd=cwd, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=timeout, env=env)
        return proc.returncode, proc.stdout + proc.stderr
    except subprocess.TimeoutExpired as exc:
        out = (exc.stdout or b'').decode(errors='replace') if isinstance(exc.stdout, bytes) else (exc.stdout or '')
        return -9, out + f'\n[timed out after {timeout}s]'


def git(cwd, *args):
    return subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True)


def tail(text, limit):
    text = text.strip()
    return text if len(text) <= limit else '[...]\n' + text[-limit:]


class Orchestrator:
    def __init__(self, ledger: Ledger, client, config, log=print):
        self.ledger = ledger
        self.client = client
        self.config = config
        self.log = log

    # -- workspace ---------------------------------------------------------
    def workspace(self, repo: Path, run_id: str, in_place: bool, root: Path):
        if in_place:
            return repo, None
        top = git(repo, 'rev-parse', '--show-toplevel')
        if top.returncode != 0:
            raise SystemExit(f'{repo} is not a git repository; use --in-place to work on it directly')
        if git(repo, 'status', '--porcelain').stdout.strip():
            self.log('warning: uncommitted changes in the repository are not part of the worktree')
        branch = f'agentd/{run_id}'
        path = root / 'worktrees' / run_id
        path.parent.mkdir(parents=True, exist_ok=True)
        made = git(repo, 'worktree', 'add', '-q', '-b', branch, str(path), 'HEAD')
        if made.returncode != 0:
            raise SystemExit(f'git worktree add failed: {made.stderr.strip()}')
        return path, branch

    @staticmethod
    def listing(toolbox: Toolbox):
        rows = toolbox.tool_list_files('.').text.splitlines()
        if len(rows) <= 80:
            return '\n'.join(rows)
        top = sorted({r.split('/')[0].split('  (')[0] for r in rows})
        return 'Top level (large repository; use list_files/search):\n' + '\n'.join(top[:80])

    def accept_state(self, root, accept):
        code, output = sh(accept, root, int(self.config['accept_timeout']))
        return {'exit_code': code, 'output': tail(output, 1500), 'full': output}

    # -- main loop ---------------------------------------------------------
    def run(self, repo, goal, accept=None, in_place=False, data_root=None):
        cfg = self.config
        if cfg.get("team_mode") and not accept:
            raise ValueError("team mode requires a deterministic acceptance command")
        team = None
        started = time.monotonic()
        repo = Path(repo).expanduser().resolve()
        run_id = self.ledger.new_run_id()
        root, branch = self.workspace(repo, run_id, in_place, Path(data_root or self.ledger.path.parent))
        self.ledger.create_run(run_id, repo, root, branch, goal, accept)
        task_id = self.ledger.create_task(run_id, goal, accept)
        toolbox = Toolbox(root, int(cfg['run_timeout']))
        worker = Worker(self.client, toolbox, self.ledger, cfg, self.log)
        self.log(f'run {run_id} · workspace {root}' + (f' · branch {branch}' if branch else '')
                 + f' · model {self.client.model}')

        state = self.accept_state(root, accept) if accept else None
        if state:
            self.log(f'initial acceptance: exit {state["exit_code"]}')
        attempts = 0

        def verify(args):
            nonlocal attempts, state
            if not accept:
                return Verification(True, None, '', 0, skipped=True)
            state = self.accept_state(root, accept)
            if state['exit_code'] == 0 and team:
                review = team.review(goal, accept, state)
                if not review['approved']:
                    state = {'exit_code': 1, 'output': 'Review requires fixes: ' + '\n'.join(review['issues']), 'full': 'Review requires fixes: ' + '\n'.join(review['issues'])}
            if state['exit_code'] == 0:
                return Verification(True, 0, tail(state['full'], 800), cfg['max_attempts'] - attempts)
            attempts += 1
            self.ledger.update_task(task_id, attempts=attempts)
            first = next((l.strip() for l in state['full'].splitlines()
                          if any(k in l for k in ('Error', 'FAIL', 'error:', 'assert', 'Traceback'))), '')
            self.ledger.fact(task_id, 'verify', f'acceptance attempt {attempts} failed (exit {state["exit_code"]}): {first[:200]}')
            return Verification(False, state['exit_code'], clip_output(state['full']), cfg['max_attempts'] - attempts)

        self.ledger.update_task(task_id, status='running')
        handoff, stalls, errors, seq = None, 0, 0, 0
        status, reason, outcome = 'failed', '', None
        try:
            if cfg.get('team_mode'):
                team = Team(self.client, cfg, self.ledger, task_id, toolbox, self.log)
                team.plan(goal, accept, self.listing(toolbox), state)
            while True:
                seq += 1
                if seq > int(cfg['max_sessions']):
                    reason = f'session limit ({cfg["max_sessions"]}) reached'
                    break
                card = prompts.card(goal=goal, role='coder', workspace=str(root), listing=self.listing(toolbox),
                                    accept=accept, accept_state=state, facts=self.ledger.facts(task_id),
                                    handoff=handoff, budget=cfg['input_budget'], rounds=cfg['rounds_per_session'],
                                    session_no=seq)
                before = toolbox.fingerprint()
                outcome = worker.run_session(task_id=task_id, seq=seq, card=card, verify=verify)
                self.ledger.update_task(task_id, sessions=seq)
                kind = outcome.kind
                self.log(f'session {seq} ended: {kind} after {outcome.rounds} rounds'
                         + (f' · changed {", ".join(outcome.changed)}' if outcome.changed else ''))
                if kind == 'done':
                    status = 'done'
                    break
                if kind == 'unverified':
                    status, reason = 'done_unverified', 'no acceptance command'
                    break
                if kind == 'attempts_exhausted':
                    reason = f'acceptance failed {attempts} times'
                    break
                if kind == 'blocked':
                    status = 'blocked'
                    reason = f"{outcome.data.get('reason', '')} {outcome.data.get('need', '')}".strip()
                    break
                if kind == 'error':
                    errors += 1
                    if errors >= 2:
                        status, reason = 'error', outcome.data.get('message', 'model error')
                        break
                    seq -= 1
                    time.sleep(10)
                    continue
                # handoff, loop, no_action: continue in a fresh session if the
                # task is still moving.
                files_changed = toolbox.fingerprint() != before
                if kind in ('loop', 'no_action'):
                    detail = outcome.data.get('call') or _first_line(outcome.data.get('content', ''))
                    self.ledger.fact(task_id, 'guard', f'session {seq} ended by {kind}: {detail}')
                stalls = 0 if files_changed else stalls + 1
                if stalls >= int(cfg['max_stalls']):
                    reason = f'no file changes in {stalls} consecutive sessions (last ended by {kind})'
                    break
                handoff = outcome.data if kind == 'handoff' and outcome.data.get('remaining') else \
                    self.synthetic_handoff(task_id, seq, kind)
                self.ledger.save_handoff(f'{task_id}-s{seq}', task_id, handoff)
                if files_changed and accept:
                    state = self.accept_state(root, accept)
        except ModelError as exc:
            status, reason = "blocked", str(exc)
            self.log("team stopped: " + reason)
        except KeyboardInterrupt:
            status, reason = 'cancelled', 'interrupted'

        summary = self.summary(run_id, task_id, root, branch, status, reason, outcome, started)
        if team and hasattr(team, 'roles'):
            summary['team'] = team.roles
            summary['advisory_model_s'] = round(sum(r['elapsed_s'] for r in team.roles), 1)
        self.ledger.update_task(task_id, status=status, result=summary)
        self.ledger.finish_run(run_id, status, summary)
        return summary

    def synthetic_handoff(self, task_id, seq, kind):
        """Handoff built from the ledger when the session did not write one."""
        session_id = f'{task_id}-s{seq}'
        events = [e for e in self.ledger.events(task_id, kinds=('tool', 'guard', 'verify'), limit=60)
                  if e['session_id'] == session_id]
        calls = [e['data']['call'] + ('' if e['data'].get('ok') else ' (failed)') for e in events if e['kind'] == 'tool']
        changed = sorted({p for e in events if e['kind'] == 'tool' for p in e['data'].get('changed', []) if p != '*'})
        duplicates = sorted({e['data']['call'] for e in events if e['kind'] == 'guard' and e['data'].get('kind') == 'duplicate'})
        done = f"Session {seq} actions: {'; '.join(calls[-12:]) or 'none'}."
        if changed:
            done += f" Files changed: {', '.join(changed)}."
        return {
            'done': done,
            'remaining': f'Not recorded; session {seq} ended by {kind}. Use the acceptance result above.',
            'facts': '',
            'next_step': 'Work from the acceptance output above.'
                         + (f" Do not repeat: {'; '.join(duplicates)}." if duplicates else ''),
        }

    def summary(self, run_id, task_id, root, branch, status, reason, outcome, started):
        sessions = self.ledger.sessions(task_id)
        total = lambda key: sum(int(s.get(key) or 0) for s in sessions)
        diff = git(root, 'diff', '--stat', 'HEAD').stdout.strip().splitlines()
        result = {
            'run_id': run_id, 'task_id': task_id, 'status': status, 'reason': reason,
            'workspace': str(root), 'branch': branch,
            'final_summary': (outcome.data.get('summary') if outcome else '') or '',
            'sessions': len(sessions), 'rounds': total('rounds'),
            'prompt_tokens': total('prompt_tokens'), 'cached_tokens': total('cached_tokens'),
            'new_prefill_tokens': total('new_prefill_tokens'), 'completion_tokens': total('completion_tokens'),
            'model_s': round(sum(s.get('model_s') or 0 for s in sessions), 1),
            'tool_s': round(sum(s.get('tool_s') or 0 for s in sessions), 1),
            'wall_s': round(time.monotonic() - started, 1),
            'session_ends': [s.get('end_reason') for s in sessions],
            'diff': diff[-1] if diff else '',
        }
        prompt = result['prompt_tokens']
        result['cached_ratio'] = round(result['cached_tokens'] / prompt, 3) if prompt else None
        return result


def _first_line(text):
    return next((line.strip() for line in str(text).splitlines() if line.strip()), '')[:160]


def format_summary(s):
    lines = [f"status: {s['status']}" + (f" ({s['reason']})" if s['reason'] else '')]
    if s['final_summary']:
        lines.append(f"summary: {s['final_summary']}")
    lines.append(f"sessions {s['sessions']} ({', '.join(map(str, s['session_ends']))}) · rounds {s['rounds']} · "
                 f"wall {s['wall_s']}s (model {s['model_s']}s, tools {s['tool_s']}s)")
    lines.append(f"tokens: prompt {s['prompt_tokens']} · cached {s['cached_tokens']} ({s['cached_ratio']}) · "
                 f"prefilled {s['new_prefill_tokens']} · generated {s['completion_tokens']}")
    if s['diff']:
        lines.append(f"diff: {s['diff']}")
    if s['branch']:
        lines.append(f"branch {s['branch']} in {s['workspace']} (merge it yourself when satisfied)")
    return '\n'.join(lines)


def dump(summary, path):
    Path(path).write_text(json.dumps(summary, ensure_ascii=False, indent=2))
