"""agentd tests with a scripted model (no GPU).

    python3 -m unittest test_agentd -v
"""
import copy
import json
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path

from agentd import config as cfg
from agentd.ledger import Ledger
from agentd.llm import Lane, Reply
from agentd.orchestrator import Orchestrator
from agentd.tools import Toolbox, ToolError

BUGGY = 'def add(a, b):\n    return a - b\n'
FIXED = 'def add(a, b):\n    return a + b\n'
TEST = ('import unittest\nfrom calc import add\n\n'
        'class T(unittest.TestCase):\n    def test_add(self):\n        self.assertEqual(add(2, 3), 5)\n')
ACCEPT = 'python3 -m unittest -q test_calc'


def call(name, prompt=None, **args):
    return ('call', name, args, prompt)


class FakeClient:
    """Plays a script of replies and records every request."""
    model = 'fake-model'

    def __init__(self, script):
        self.script = list(script)
        self.requests = []
        self.lengths = {}

    def chat(self, *, session_id, messages, tools, tool_choice, max_tokens, priority=5):
        self.requests.append({'session_id': session_id, 'messages': copy.deepcopy(messages),
                              'tool_choice': copy.deepcopy(tool_choice), 'tools': [t['function']['name'] for t in tools]})
        if not self.script:
            raise AssertionError('script exhausted')
        step = self.script.pop(0)
        if callable(step):
            step = step(self.requests[-1])
        prompt = (step[3] if len(step) > 3 and step[3] else None) or len(json.dumps(messages)) // 3
        cached = self.lengths.get(session_id, 0)
        self.lengths[session_id] = prompt
        usage = {'prompt_tokens': prompt, 'completion_tokens': 30, 'cached_tokens': cached,
                 'new_prefill_tokens': prompt - cached}
        if step[0] == 'text':
            return Reply({'role': 'assistant', 'content': step[1]}, 'stop', usage, 0.01)
        message = {'role': 'assistant', 'content': '', 'reasoning_content': f'thinking {len(self.requests)}',
                   'tool_calls': [{'id': f'c{len(self.requests)}', 'type': 'function',
                                   'function': {'name': step[1], 'arguments': json.dumps(step[2])}}]}
        return Reply(message, 'tool_calls', usage, 0.01)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        (self.repo / 'calc.py').write_text(BUGGY)
        (self.repo / 'test_calc.py').write_text(TEST)
        self.ledger = Ledger(self.root / 'data' / 'ledger.sqlite3')
        self.config = cfg.load({'max_sessions': 4, 'max_attempts': 2, 'repeat_limit': 2, 'input_budget': 24576})
        self.lines = []

    def tearDown(self):
        self.tmp.cleanup()

    def run_goal(self, script, accept=ACCEPT, in_place=True, **overrides):
        self.config.update(overrides)
        self.client = FakeClient(script)
        orch = Orchestrator(self.ledger, self.client, self.config, self.lines.append)
        return orch.run(self.repo, 'make add() add', accept, in_place=in_place, data_root=self.root / 'data')

    def assert_append_only(self):
        by_session = {}
        for request in self.client.requests:
            by_session.setdefault(request['session_id'], []).append(request['messages'])
        for session, history in by_session.items():
            for before, after in zip(history, history[1:]):
                self.assertEqual(after[:len(before)], before, f'{session}: history was rewritten')
                self.assertGreater(len(after), len(before))
        # Every request in every session shares the same system prompt and tools.
        self.assertEqual(len({r['messages'][0]['content'] for r in self.client.requests}), 1)
        self.assertEqual(len({tuple(r['tools']) for r in self.client.requests}), 1)


class WorkerLoopTests(Base):
    def test_fix_and_verified_finish(self):
        summary = self.run_goal([
            call('read_file', path='calc.py'),
            call('edit_file', path='calc.py', old_text='a - b', new_text='a + b'),
            call('run', command=ACCEPT),
            call('finish', summary='fixed add', evidence='tests pass'),
        ])
        self.assertEqual(summary['status'], 'done', summary)
        self.assertEqual((self.repo / 'calc.py').read_text(), FIXED)
        self.assertEqual(summary['sessions'], 1)
        self.assert_append_only()
        # reasoning is echoed back exactly as generated
        second = self.client.requests[1]['messages']
        self.assertEqual(second[2]['reasoning_content'], 'thinking 1')
        self.assertEqual(self.client.requests[0]['tool_choice'], self.config['tool_choice'])

    def test_finish_without_fix_is_rejected_until_attempts_run_out(self):
        summary = self.run_goal([
            call('finish', summary='done?'),
            call('finish', summary='really done'),
        ])
        self.assertEqual(summary['status'], 'failed')
        self.assertIn('acceptance failed 2 times', summary['reason'])
        feedback = self.client.requests[1]['messages'][-1]
        self.assertEqual(feedback['role'], 'tool')
        self.assertIn('Acceptance command failed', feedback['content'])
        self.assertIn('AssertionError', feedback['content'])

    def test_duplicate_read_is_not_executed_and_loop_ends_session(self):
        reads = [call('read_file', path='calc.py')] * 3
        summary = self.run_goal(reads + reads, max_stalls=2)
        self.assertEqual(summary['status'], 'failed')
        self.assertIn('no file changes in 2 consecutive sessions', summary['reason'])
        self.assertEqual(summary['session_ends'], ['loop', 'loop'])
        second = self.client.requests[2]['messages'][-1]['content']
        self.assertIn('[not executed]', second)
        # the next session is told what looped
        card = self.client.requests[3]['messages'][1]['content']
        self.assertIn('ended by loop', card)
        self.assertIn('Do not repeat: read_file calc.py', card)
        self.assert_append_only()

    def test_reread_after_change_is_allowed(self):
        summary = self.run_goal([
            call('read_file', path='calc.py'),
            call('edit_file', path='calc.py', old_text='a - b', new_text='a + b'),
            call('read_file', path='calc.py'),
            call('finish', summary='ok'),
        ])
        self.assertEqual(summary['status'], 'done')
        self.assertNotIn('[not executed]', self.client.requests[3]['messages'][-1]['content'])

    def test_rerun_of_same_command_without_changes_is_duplicate(self):
        self.run_goal([
            call('run', command=ACCEPT),
            call('run', command=ACCEPT),
            call('edit_file', path='calc.py', old_text='a - b', new_text='a + b'),
            call('run', command=ACCEPT),
            call('finish', summary='ok'),
        ])
        self.assertIn('[not executed]', self.client.requests[2]['messages'][-1]['content'])
        self.assertIn('exit_code: 0', self.client.requests[4]['messages'][-1]['content'])

    def test_text_only_reply_is_nudged_then_ends_session(self):
        summary = self.run_goal([
            ('text', 'Let me check the file.'),
            call('edit_file', path='calc.py', old_text='a - b', new_text='a + b'),
            call('finish', summary='ok'),
        ])
        self.assertEqual(summary['status'], 'done')
        nudge = self.client.requests[1]['messages'][-1]
        self.assertEqual(nudge['role'], 'user')
        self.assertIn('No tool was called', nudge['content'])
        self.assert_append_only()

        self.tearDown()
        self.setUp()
        summary = self.run_goal([('text', 'Let me check.'), ('text', 'Now I will look.'),
                                 ('text', 'thinking'), ('text', 'thinking')], max_stalls=2)
        self.assertEqual(summary['session_ends'], ['no_action', 'no_action'])

    def test_budget_forces_handoff_and_fresh_session_continues(self):
        handoff = {'done': 'found the bug in calc.py:2 (subtraction)', 'remaining': 'change - to +',
                   'facts': 'calc.py:2 uses a - b', 'next_step': 'edit calc.py line 2'}
        summary = self.run_goal([
            call('read_file', path='calc.py', prompt=1000),
            call('read_file', path='test_calc.py', prompt=2000),
            call('handoff', **handoff),
            call('edit_file', path='calc.py', old_text='a - b', new_text='a + b', prompt=1000),
            call('finish', summary='fixed', prompt=1100),
        ], input_budget=2400, handoff_ratio=0.7)
        self.assertEqual(summary['status'], 'done', summary)
        # tool_choice never changes (it is rendered into the cached system prefix)
        self.assertEqual({r['tool_choice'] for r in self.client.requests}, {self.config['tool_choice']})
        asked = self.client.requests[2]['messages'][-1]
        self.assertEqual(asked['role'], 'user')
        self.assertIn('Context budget', asked['content'])
        card = next(r for r in self.client.requests if r['session_id'].endswith('-s2'))['messages'][1]['content']
        self.assertIn('Handoff from session 1', card)
        self.assertIn('calc.py:2 uses a - b', card)
        self.assertEqual(summary['session_ends'], ['handoff', 'done'])
        self.assert_append_only()

    def test_ignored_handoff_request_ends_session_with_ledger_handoff(self):
        summary = self.run_goal([
            call('read_file', path='calc.py', prompt=1000),
            call('read_file', path='test_calc.py', prompt=2000),
            call('list_files', path='.'),
            call('edit_file', path='calc.py', old_text='a - b', new_text='a + b', prompt=1000),
            call('finish', summary='fixed', prompt=1100),
        ], input_budget=2400, handoff_ratio=0.7)
        self.assertEqual(summary['session_ends'], ['handoff', 'done'])
        card = next(r for r in self.client.requests if r['session_id'].endswith('-s2'))['messages'][1]['content']
        self.assertIn('read_file calc.py; read_file test_calc.py', card)

    def test_large_card_does_not_hand_off_immediately(self):
        summary = self.run_goal([
            call('edit_file', path='calc.py', old_text='a - b', new_text='a + b', prompt=2000),
            call('finish', summary='ok', prompt=2100),
        ], input_budget=2400, handoff_ratio=0.7)
        self.assertEqual(summary['session_ends'], ['done'])
        self.assertEqual({r['tool_choice'] for r in self.client.requests}, {self.config['tool_choice']})

    def test_rounds_limit_requests_handoff(self):
        script = [call('list_files', path='.'), call('search', pattern='def add'),
                  call('handoff', done='looked', remaining='fix', next_step='edit'),
                  call('edit_file', path='calc.py', old_text='a - b', new_text='a + b'),
                  call('finish', summary='ok')]
        summary = self.run_goal(script, rounds_per_session=3)
        self.assertEqual(summary['status'], 'done')
        self.assertIn('used its 3 rounds', self.client.requests[2]['messages'][-1]['content'])

    def test_blocked_is_reported(self):
        summary = self.run_goal([call('report_blocked', reason='needs API key', need='STRIPE_KEY')])
        self.assertEqual(summary['status'], 'blocked')
        self.assertIn('STRIPE_KEY', summary['reason'])

    def test_worktree_keeps_original_repo_untouched(self):
        for args in (['init', '-q'], ['add', '-A'],
                     ['-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'init']):
            subprocess.run(['git', *args], cwd=self.repo, check=True, capture_output=True)
        summary = self.run_goal([
            call('edit_file', path='calc.py', old_text='a - b', new_text='a + b'),
            call('finish', summary='ok'),
        ], in_place=False)
        self.assertEqual(summary['status'], 'done')
        self.assertEqual((self.repo / 'calc.py').read_text(), BUGGY)
        self.assertEqual((Path(summary['workspace']) / 'calc.py').read_text(), FIXED)
        self.assertTrue(summary['branch'].startswith('agentd/'))
        self.assertIn('1 file changed', summary['diff'])


class ToolboxTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / 'a.py').write_text('x = 1\ny = 2\nx = 1\n')
        self.box = Toolbox(self.root)

    def tearDown(self):
        self.tmp.cleanup()

    def test_confined_to_workspace(self):
        with self.assertRaises(ToolError):
            self.box.path('../outside.txt', must_exist=False)
        self.assertIn('outside the workspace', self.box.execute('read_file', {'path': '/etc/hosts'}).text)

    def test_edit_errors_are_actionable(self):
        result = self.box.execute('edit_file', {'path': 'a.py', 'old_text': 'x = 1', 'new_text': 'x = 3'})
        self.assertFalse(result.ok)
        self.assertIn('matches 2 times (lines [1, 3])', result.text)
        result = self.box.execute('edit_file', {'path': 'a.py', 'old_text': 'y = 3', 'new_text': 'z'})
        self.assertIn('closest lines', result.text)
        self.assertIn('2| y = 2', result.text)

    def test_run_reports_exit_code_and_refuses_push(self):
        result = self.box.execute('run', {'command': 'echo hi; exit 3'})
        self.assertEqual(result.exit_code, 3)
        self.assertIn('hi', result.text)
        self.assertIn('refused', self.box.execute('run', {'command': 'git push origin main'}).text)

    def test_read_ranges(self):
        (self.root / 'big.txt').write_text(''.join(f'line {i}\n' for i in range(1, 501)))
        text = self.box.execute('read_file', {'path': 'big.txt'}).text
        self.assertIn('(lines 1-300 of 500)', text)
        self.assertIn('[more: read_file start_line=301]', text)
        text = self.box.execute('read_file', {'path': 'big.txt', 'start_line': 490, 'end_line': 495}).text
        self.assertIn('  490| line 490', text)

    def test_codegraph_and_aoci_tools(self):
        sample_code = 'class Calculator:\n    """A simple calculator."""\n    def add(self, a: int, b: int) -> int:\n        return a + b\n'
        (self.root / 'calc_sample.py').write_text(sample_code)

        # 1. code_outline test
        res_outline = self.box.execute('code_outline', {'path': 'calc_sample.py'})
        self.assertTrue(res_outline.ok)
        self.assertIn('[CodeGraph 大纲]', res_outline.text)
        self.assertIn('class Calculator:', res_outline.text)
        self.assertIn('def add(self, a: int, b: int) -> int: ...', res_outline.text)

        # 2. code_search_symbol test
        res_sym = self.box.execute('code_search_symbol', {'name': 'Calculator'})
        self.assertTrue(res_sym.ok)
        self.assertIn('Found 1 symbols:', res_sym.text)
        self.assertIn('calc_sample.py:1 [class] Calculator', res_sym.text)

        # 3. code_blueprint test
        res_bp = self.box.execute('code_blueprint', {})
        self.assertTrue(res_bp.ok)
        self.assertIn('[AOCI 仓库架构蓝图]', res_bp.text)


class LaneTests(unittest.TestCase):
    def test_priority_then_fifo(self):
        lane = Lane()
        order = []
        lane.acquire(5)
        threads = []
        for name, priority in (('coder-a', 5), ('reviewer', 1), ('coder-b', 5)):
            t = threading.Thread(target=lambda n=name, p=priority: (lane.acquire(p), order.append(n), lane.release()))
            t.start()
            threads.append(t)
            time.sleep(0.05)
        lane.release()
        for t in threads:
            t.join(2)
        self.assertEqual(order, ['reviewer', 'coder-a', 'coder-b'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
