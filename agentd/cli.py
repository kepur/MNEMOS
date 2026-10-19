"""agentd command line.

    python3 -m agentd run --repo ~/proj --goal "..." --accept "python3 -m pytest -q"
    python3 -m agentd status
    python3 -m agentd show RUN_ID
"""
from __future__ import annotations

import argparse
import json
import sys
import time

from . import config as cfg
from .ledger import Ledger
from .llm import ModelClient
from .orchestrator import Orchestrator, dump, format_summary


def log(line):
    print(time.strftime('%H:%M:%S ') + line, flush=True)


def cmd_run(args):
    overrides = {k: getattr(args, k) for k in ('input_budget', 'rounds_per_session', 'max_sessions', 'max_attempts')}
    config = cfg.load(overrides)
    ledger = Ledger(cfg.DATA / 'ledger.sqlite3')
    if args.team:
        config["team_mode"] = True
    if config["team_mode"] and not args.accept:
        raise SystemExit("规划执行模式必须提供 --accept 验收命令")
    worker_runtime = cfg.runtime()
    if worker_runtime.get("backend") in ("lmstudio", "omlx"):
        # Multi-model servers list every installed model; use the switcher's.
        worker_runtime["pinned_model"] = worker_runtime.get("api_model")
    client = ModelClient(worker_runtime)
    if not args.accept:
        log('warning: no --accept command; completion cannot be verified')
    summary = Orchestrator(ledger, client, config, log).run(
        args.repo, args.goal, args.accept, in_place=args.in_place)
    print(format_summary(summary), flush=True)
    if args.json_summary:
        dump(summary, args.json_summary)
    return 0 if summary['status'] in ('done', 'done_unverified') else 1


def cmd_status(args):
    ledger = Ledger(cfg.DATA / 'ledger.sqlite3')
    for run in ledger.runs(args.limit):
        result = json.loads(run['result']) if run['result'] else {}
        print(f"{run['id']}  {run['status']:<15} {result.get('wall_s', '-')}s  "
              f"sessions {result.get('sessions', '-')}  {run['goal'][:70]!r}")
    return 0


def cmd_show(args):
    ledger = Ledger(cfg.DATA / 'ledger.sqlite3')
    run, tasks = ledger.run(args.run_id)
    if not run:
        print(f'no run {args.run_id}', file=sys.stderr)
        return 1
    print(f"run {run['id']} · {run['status']} · {run['workspace']}")
    for task in tasks:
        print(f"\ntask {task['id']} · {task['status']} · attempts {task['attempts']}\n  goal: {task['goal']}")
        for fact in ledger.facts(task['id']):
            print(f"  fact [{fact['kind']}] {fact['text']}")
        for session in ledger.sessions(task['id']):
            print(f"  session {session['seq']}: {session['end_reason']} · rounds {session['rounds']} · "
                  f"prompt {session['prompt_tokens']} cached {session['cached_tokens']} · model {session['model_s']:.0f}s")
        for event in ledger.events(task['id'], kinds=('tool', 'guard', 'verify')):
            data = event['data']
            text = data.get('call') or data.get('kind') or ('verify exit ' + str(data.get('exit_code')))
            print(f"    s{event['session_id'].rsplit('-s', 1)[-1]} r{event['round']} {event['kind']}: {text}")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(prog='agentd', description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    run = sub.add_parser('run', help='run a goal to verified completion')
    run.add_argument('--repo', required=True)
    run.add_argument('--goal', required=True)
    run.add_argument('--accept', help='shell command; exit 0 means the task is done')
    run.add_argument('--team', action='store_true', help='plan, execute, verify and review with local roles')
    run.add_argument('--in-place', action='store_true', help='edit the repo directly instead of a git worktree')
    run.add_argument('--json-summary')
    run.add_argument('--input-budget', type=int)
    run.add_argument('--rounds-per-session', type=int)
    run.add_argument('--max-sessions', type=int)
    run.add_argument('--max-attempts', type=int)
    run.set_defaults(func=cmd_run)
    status = sub.add_parser('status', help='recent runs')
    status.add_argument('--limit', type=int, default=10)
    status.set_defaults(func=cmd_status)
    show = sub.add_parser('show', help='timeline of one run')
    show.add_argument('run_id')
    show.set_defaults(func=cmd_show)
    args = parser.parse_args(argv)
    return args.func(args)
