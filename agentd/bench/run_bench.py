"""Phase 0 benchmark: run coding tasks with an acceptance command and record
completion, wall time and what the inference server actually prefilled.

    python3 -m agentd.bench.run_bench --runner codex
    python3 -m agentd.bench.run_bench --runner agentd --tasks fix_bug,multi_file

Server metrics come from MTPLX /v1/mtplx/prefill_history (a 100-entry ring),
polled during each task so long tasks do not lose entries. Requests from other
clients during the same window are counted too; keep the machine otherwise idle.
"""
from __future__ import annotations

import argparse
import collections
import contextlib
import hashlib
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
TASKS = HERE / 'tasks'
PACKAGE_ROOT = HERE.parents[1]
RUNTIME = Path.home() / '.local/state/mtplx-qwen38/runtime.json'


def runtime():
    try:
        return json.loads(RUNTIME.read_text())
    except (OSError, ValueError):
        return {}


class HistoryPoller:
    """Collect /v1/mtplx/prefill_history entries that appear during a window."""

    def __init__(self, backend, interval=10.0):
        self.url = backend.rstrip('/') + '/v1/mtplx/prefill_history'
        self.interval = interval
        self.seen = {}
        self.stop_event = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.start_t = 0.0

    def poll(self):
        try:
            with urllib.request.urlopen(self.url, timeout=5) as r:
                history = json.load(r).get('history') or []
        except (OSError, ValueError):
            return
        for entry in history:
            if entry.get('t', 0) >= self.start_t:
                key = (entry.get('t'), entry.get('session_id'), entry.get('prompt_tokens'))
                self.seen[key] = entry

    def _run(self):
        while not self.stop_event.wait(self.interval):
            self.poll()

    def __enter__(self):
        self.start_t = time.time()
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.stop_event.set()
        self.thread.join(timeout=5)
        self.poll()

    def summary(self):
        rows = sorted(self.seen.values(), key=lambda e: e['t'])
        by_session = collections.defaultdict(list)
        for row in rows:
            by_session[row.get('session_id')].append(row)
        append_hits = continuations = 0
        for session_rows in by_session.values():
            for prev, cur in zip(session_rows, session_rows[1:]):
                continuations += 1
                if cur.get('cached_tokens', 0) >= prev.get('prompt_tokens', 0):
                    append_hits += 1
        prompt = sum(r.get('prompt_tokens', 0) for r in rows)
        new = sum(r.get('new_prefill_tokens', 0) for r in rows)
        return {
            'requests': len(rows),
            'sessions': len(by_session),
            'prompt_tokens': prompt,
            'new_prefill_tokens': new,
            'cached_ratio': round(1 - new / prompt, 3) if prompt else None,
            'prefill_s': round(sum(r.get('prompt_eval_time_s', 0) for r in rows), 1),
            'ttft_s': round(sum(r.get('ttft_s', 0) for r in rows), 1),
            'max_prompt_tokens': max((r.get('prompt_tokens', 0) for r in rows), default=0),
            'append_hit_ratio': round(append_hits / continuations, 3) if continuations else None,
            'miss_reasons': dict(collections.Counter(str(r.get('cache_miss_reason')) for r in rows)),
        }


def tree_hash(path):
    h = hashlib.sha256()
    for p in sorted(Path(path).rglob('*')):
        if p.is_file() and '__pycache__' not in p.parts:
            h.update(str(p.relative_to(path)).encode())
            h.update(p.read_bytes())
    return h.hexdigest()


def git(cwd, *args):
    return subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True)


def prepare(task, workdir):
    if workdir.exists():
        shutil.rmtree(workdir)
    shutil.copytree(TASKS / task / 'repo', workdir)
    git(workdir, 'init', '-q')
    git(workdir, 'add', '-A')
    git(workdir, '-c', 'user.name=bench', '-c', 'user.email=bench@localhost',
        '-c', 'commit.gpgsign=false', 'commit', '-qm', 'task start')


def prompt_for(spec):
    return (f"{spec['goal']}\n\n完成标准：在仓库根目录运行 `{spec['accept']}`，全部测试通过。"
            '完成后简要说明修改了什么。')


def run_codex(spec, workdir, timeout, log_dir):
    rt = runtime()
    model = rt.get('api_model') or 'local/qwopus3.6-35b-a3b-coder-4bit'
    ctx = int(rt.get('context_length') or 131072)
    provider = '{name="Local bench",base_url="http://127.0.0.1:8002/v1",wire_api="responses"}'
    cmd = ['codex', 'exec', '--ignore-user-config', '--skip-git-repo-check', '--ephemeral', '--json',
           '-C', str(workdir), '-s', 'workspace-write', '-m', model,
           '-c', 'model_provider=local-bench', '-c', f'model_providers.local-bench={provider}',
           '-c', f'model_reasoning_effort={rt.get("reasoning_effort") or "medium"}',
           '-c', f'model_context_window={ctx}', '-c', f'model_auto_compact_token_limit={ctx * 3 // 4}',
           '-c', 'approval_policy=never',
           '-o', str(log_dir / 'last_message.txt'), prompt_for(spec)]
    started = time.monotonic()
    events = collections.Counter()
    with (log_dir / 'events.jsonl').open('w') as sink:
        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, env=clean_env())
        killed = threading.Event()
        timer = threading.Timer(timeout, lambda: (killed.set(), proc.kill()))
        timer.start()
        try:
            for line in proc.stdout:
                sink.write(line)
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                kind = event.get('type', '?')
                item = event.get('item') or {}
                events[kind + (':' + item['type'] if isinstance(item, dict) and item.get('type') else '')] += 1
            proc.wait()
        finally:
            timer.cancel()
    return {'exit_code': proc.returncode, 'timed_out': killed.is_set(),
            'wall_s': round(time.monotonic() - started, 1), 'events': dict(events)}


def run_agentd(spec, workdir, timeout, log_dir):
    cmd = [sys.executable, '-m', 'agentd', 'run', '--repo', str(workdir), '--in-place',
           '--goal', spec['goal'], '--accept', spec['accept'], '--json-summary', str(log_dir / 'summary.json')]
    started = time.monotonic()
    with (log_dir / 'agentd.log').open('w') as sink:
        try:
            proc = subprocess.run(cmd, cwd=PACKAGE_ROOT, stdin=subprocess.DEVNULL, stdout=sink,
                                  stderr=subprocess.STDOUT, timeout=timeout, env=clean_env())
            code, timed_out = proc.returncode, False
        except subprocess.TimeoutExpired:
            code, timed_out = -9, True
    result = {'exit_code': code, 'timed_out': timed_out, 'wall_s': round(time.monotonic() - started, 1)}
    try:
        result['agentd'] = json.loads((log_dir / 'summary.json').read_text())
    except (OSError, ValueError):
        pass
    return result


OPENCODE_APP = Path('/Applications/OpenCode.app/Contents/MacOS/OpenCode')
OPENCODE_SERVER = '/Applications/OpenCode.app/Contents/Resources/app.asar/out/main/chunks/node-pJrOSIuY.js'


class OpenCodeServer:
    """The desktop app's own server, run headless through its Electron binary.

    Uses the user's ~/.config/opencode (Serafina provider + plugin) but an
    isolated data directory, so benchmark sessions stay out of their history.
    """

    def __init__(self, root, port=4199, password='bench'):
        self.root = Path(root)
        self.port = port
        self.auth = 'Basic ' + __import__('base64').b64encode(f'opencode:{password}'.encode()).decode()
        self.password = password
        self.proc = None

    def __enter__(self):
        for sub in ('data', 'state'):
            (self.root / sub).mkdir(parents=True, exist_ok=True)
        script = self.root / 'serve.mjs'
        script.write_text(
            f"const {{ Server }} = await import({json.dumps(OPENCODE_SERVER)});\n"
            f"await Server.listen({{ port: {self.port}, hostname: '127.0.0.1', username: 'opencode', "
            f"password: process.env.OPENCODE_SERVER_PASSWORD, cors: [] }});\nconsole.log('ready');\n")
        env = {**clean_env(), 'ELECTRON_RUN_AS_NODE': '1', 'OPENCODE_SERVER_USERNAME': 'opencode',
               'OPENCODE_SERVER_PASSWORD': self.password, 'XDG_DATA_HOME': str(self.root / 'data'),
               'XDG_STATE_HOME': str(self.root / 'state'), 'NO_PROXY': '127.0.0.1,localhost'}
        log = (self.root / 'server.log').open('w')
        self.proc = subprocess.Popen([str(OPENCODE_APP), str(script)], cwd=self.root, env=env,
                                     stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            try:
                self.call('GET', '/session', timeout=2)
                return self
            except OSError:
                time.sleep(0.5)
        raise RuntimeError(f'OpenCode server did not start; see {self.root / "server.log"}')

    def __exit__(self, *exc):
        if self.proc:
            self.proc.terminate()
            try:
                self.proc.wait(10)
            except subprocess.TimeoutExpired:
                self.proc.kill()

    def call(self, method, path, body=None, timeout=30):
        request = urllib.request.Request(
            f'http://127.0.0.1:{self.port}{path}', method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={'Authorization': self.auth, 'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
        return json.loads(raw) if raw else None


def run_opencode(spec, workdir, timeout, log_dir):
    # The switcher declares one OpenCode model, "active"; the gateway maps it to
    # whatever runtime.json has loaded (the results file records which).
    model = 'active'
    server = RUN_CONTEXT['opencode']
    q = '?directory=' + urllib.parse.quote(str(workdir))
    session = server.call('POST', '/session' + q, {
        'title': 'bench ' + workdir.parent.name,
        'permission': [{'permission': '*', 'pattern': '*', 'action': 'allow'}]})
    started = time.monotonic()
    timed_out = False
    try:
        server.call('POST', f'/session/{session["id"]}/message{q}', {
            'model': {'providerID': 'serafina', 'modelID': model},
            # Measure OpenCode's own loop, not a hand-off to agentd.
            'tools': {'agentd': False},
            'parts': [{'type': 'text', 'text': prompt_for(spec)}]}, timeout=timeout)
    except (TimeoutError, OSError) as exc:
        timed_out = 'timed out' in str(exc).lower()
        try:
            server.call('POST', f'/session/{session["id"]}/abort{q}', {})
        except OSError:
            pass
    wall = round(time.monotonic() - started, 1)
    messages = server.call('GET', f'/session/{session["id"]}/message{q}', timeout=30) or []
    (log_dir / 'messages.json').write_text(json.dumps(messages, ensure_ascii=False, indent=1))
    events = collections.Counter()
    last_text = ''
    for message in messages:
        events['message:' + str((message.get('info') or {}).get('role'))] += 1
        for part in message.get('parts') or []:
            kind = part.get('type')
            events['part:' + str(kind) + (':' + part['tool'] if kind == 'tool' and part.get('tool') else '')] += 1
            if kind == 'text' and (message.get('info') or {}).get('role') == 'assistant':
                last_text = part.get('text') or last_text
    (log_dir / 'last_message.txt').write_text(last_text)
    return {'exit_code': 0, 'timed_out': timed_out, 'wall_s': wall, 'events': dict(events)}


def clean_env(**extra):
    """The caller's environment minus any Claude/Anthropic session settings,
    so a CLI under test never inherits the host agent's endpoint or identity."""
    env = {k: v for k, v in os.environ.items() if not k.startswith(('CLAUDE', 'ANTHROPIC'))}
    env.update(extra)
    return env


def _run_cli(cmd, workdir, timeout, log_dir, env):
    """Run a headless agent CLI with JSON-lines output; count event types."""
    started = time.monotonic()
    events = collections.Counter()
    last = ''
    with (log_dir / 'events.jsonl').open('w') as sink:
        proc = subprocess.Popen(cmd, cwd=workdir, env=env, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        killed = threading.Event()
        timer = threading.Timer(timeout, lambda: (killed.set(), proc.kill()))
        timer.start()
        try:
            for line in proc.stdout:
                sink.write(line)
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                kind = str(event.get('type', '?'))
                message = event.get('message') if isinstance(event.get('message'), dict) else {}
                for block in message.get('content') or []:
                    if isinstance(block, dict):
                        events[kind + ':' + str(block.get('type'))] += 1
                        if block.get('type') == 'text':
                            last = block.get('text') or last
                if not message:
                    events[kind] += 1
                if kind == 'result' and isinstance(event.get('result'), str):
                    last = event['result']
            proc.wait()
        finally:
            timer.cancel()
    (log_dir / 'last_message.txt').write_text(last)
    return {'exit_code': proc.returncode, 'timed_out': killed.is_set(),
            'wall_s': round(time.monotonic() - started, 1), 'events': dict(events)}


def run_qwen(spec, workdir, timeout, log_dir):
    rt = runtime()
    home = log_dir / '_home'
    home.mkdir(exist_ok=True)
    cmd = [shutil.which('qwen') or 'qwen', prompt_for(spec), '--yolo', '--auth-type', 'openai',
           '--openai-base-url', 'http://127.0.0.1:8002/v1', '--openai-api-key', 'local',
           '-m', rt.get('api_model') or 'local/qwopus3.6-35b-a3b-coder-4bit',
           '--advisor', 'off', '-o', 'stream-json']
    # Isolated settings/memory so runs neither read nor write ~/.qwen.
    env = clean_env(HOME=str(home))
    return _run_cli(cmd, workdir, timeout, log_dir, env)


def run_claude(spec, workdir, timeout, log_dir):
    rt = runtime()
    model = rt.get('api_model') or 'local/qwopus3.6-35b-a3b-coder-4bit'
    config = log_dir / '_claude'
    config.mkdir(exist_ok=True)
    cmd = [shutil.which('claude') or 'claude', '-p', prompt_for(spec), '--dangerously-skip-permissions',
           '--model', model, '--output-format', 'stream-json', '--verbose']
    # The gateway bridges Anthropic Messages to MTPLX with the switcher's
    # thinking setting and maps every requested model to the local one.
    env = clean_env(ANTHROPIC_BASE_URL='http://127.0.0.1:8002', ANTHROPIC_AUTH_TOKEN='local',
                    ANTHROPIC_MODEL=model, ANTHROPIC_DEFAULT_HAIKU_MODEL=model,
                    ANTHROPIC_DEFAULT_SONNET_MODEL=model, ANTHROPIC_DEFAULT_OPUS_MODEL=model,
                    ANTHROPIC_SMALL_FAST_MODEL=model, CLAUDE_CONFIG_DIR=str(config),
                    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1', DISABLE_AUTOUPDATER='1', DISABLE_TELEMETRY='1')
    return _run_cli(cmd, workdir, timeout, log_dir, env)


RUNNERS = {'codex': run_codex, 'agentd': run_agentd, 'opencode': run_opencode,
           'qwen': run_qwen, 'claude': run_claude}
RUN_CONTEXT = {}


def run_tasks(args, names, root, backend, report, results_dir, tag):
    for name in names:
        spec = json.loads((TASKS / name / 'task.json').read_text())
        workdir = root / name / 'repo'
        log_dir = root / name
        prepare(name, workdir)
        tests_before = tree_hash(workdir / 'tests')
        print(f'[{name}] running {args.runner} ...', flush=True)
        with HistoryPoller(backend) as poller:
            outcome = RUNNERS[args.runner](spec, workdir, args.timeout, log_dir)
        accept = subprocess.run(spec['accept'], shell=True, cwd=workdir, capture_output=True, text=True, timeout=300)
        tampered = tree_hash(workdir / 'tests') != tests_before
        diff = git(workdir, 'diff', '--stat', 'HEAD').stdout.strip().splitlines()
        untracked = git(workdir, 'ls-files', '--others', '--exclude-standard').stdout.split()
        passed = accept.returncode == 0 and not tampered
        report['tasks'][name] = {
            'passed': passed, 'accept_exit': accept.returncode, 'tests_tampered': tampered,
            'accept_tail': (accept.stdout + accept.stderr)[-600:],
            'diff': diff[-1] if diff else '', 'new_files': untracked,
            **outcome, 'server': poller.summary(),
        }
        print(f'[{name}] passed={passed} wall={outcome["wall_s"]}s server={report["tasks"][name]["server"]}', flush=True)
        (results_dir / f'{tag}.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--runner', choices=sorted(RUNNERS), required=True)
    parser.add_argument('--tasks', default='all')
    parser.add_argument('--timeout', type=int, default=1500, help='seconds per task')
    parser.add_argument('--label', default='', help='suffix for the results file')
    parser.add_argument('--workroot', default=str(Path.home() / '.local/share/agentd/bench'))
    args = parser.parse_args(argv)

    names = sorted(p.name for p in TASKS.iterdir() if (p / 'task.json').exists())
    if args.tasks != 'all':
        names = [n for n in args.tasks.split(',') if n in names]
    stamp = time.strftime('%Y%m%d-%H%M%S')
    tag = f'{stamp}-{args.runner}' + (f'-{args.label}' if args.label else '')
    root = Path(args.workroot) / tag
    results_dir = HERE / 'results'
    results_dir.mkdir(exist_ok=True)
    backend = str(runtime().get('backend_url') or 'http://127.0.0.1:8000')
    report = {'tag': tag, 'runner': args.runner, 'model': runtime().get('api_model'),
              'started': stamp, 'tasks': {}}
    with contextlib.ExitStack() as stack:
        if args.runner == 'opencode':
            RUN_CONTEXT['opencode'] = stack.enter_context(OpenCodeServer(root / '_opencode'))
        run_tasks(args, names, root, backend, report, results_dir, tag)
    totals = report['tasks'].values()
    report['summary'] = {
        'passed': sum(t['passed'] for t in totals), 'total': len(report['tasks']),
        'wall_s': round(sum(t['wall_s'] for t in totals), 1),
        'prefill_s': round(sum(t['server']['prefill_s'] for t in totals), 1),
        'new_prefill_tokens': sum(t['server']['new_prefill_tokens'] for t in totals),
        'requests': sum(t['server']['requests'] for t in totals),
    }
    (results_dir / f'{tag}.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps(report['summary'], ensure_ascii=False))
    print(f'results: {results_dir / (tag + ".json")}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
