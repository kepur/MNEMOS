import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from agentd import config
from agentd.ledger import Ledger
from agentd.llm import Reply, ModelError
from agentd.orchestrator import Orchestrator
from agentd.team import Team, PLAN
from agentd.tools import Toolbox
from test_agentd import FakeClient, call, BUGGY, FIXED, TEST, ACCEPT

class TeamTests(unittest.TestCase):
    def test_review_rejection_returns_to_worker_even_after_tests_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp);(root/'calc.py').write_text(BUGGY);(root/'test_calc.py').write_text(TEST)
            ledger = Ledger(root/'state/ledger.sqlite3')
            client = FakeClient([call('edit_file',path='calc.py',old_text='a - b',new_text='a + b'),
                                 call('finish',summary='fixed'),call('finish',summary='checked')])
            with patch('agentd.orchestrator.Team') as factory:
                team = factory.return_value
                team.roles = []
                team.review.side_effect = [{'approved':False,'issues':['Check negative inputs']},{'approved':True,'issues':[]}]
                result = Orchestrator(ledger,client,config.load({'team_mode':True,'max_attempts':3}),lambda x:None).run(root,'fix add','PYTHONDONTWRITEBYTECODE=1 '+ACCEPT,in_place=True)
            self.assertEqual(result['status'],'done')
            team.plan.assert_called_once();self.assertEqual(team.review.call_count,2)
            self.assertIn('Check negative inputs',client.requests[-1]['messages'][-1]['content'])

    def test_team_requires_acceptance(self):
        with tempfile.TemporaryDirectory() as tmp:
            o=Orchestrator(Ledger(Path(tmp)/'l.sqlite3'),None,{'team_mode':True})
            with self.assertRaises(ValueError):o.run(tmp,'fix')

    def test_planner_cannot_write_and_requires_structured_submission(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'calc.py').write_text(BUGGY)
            team=Team.__new__(Team);team.toolbox=Toolbox(root);team.ledger=Ledger(root/'l.sqlite3');team.task_id='test'
            # ledger writes use a stub; filesystem behavior is real.
            class LedgerStub:
                def fact(self,*args):pass
            team.ledger=LedgerStub();team.cfg={'review_rounds':3};team.roles=[];team.log=lambda x:None
            client=FakeClient([call('write_file',path='calc.py',content=FIXED),call('submit_plan',steps=['read calc','fix add','run tests'],risks=[])])
            result=team.role('planner',client,'goal',PLAN)
            self.assertEqual((root/'calc.py').read_text(),BUGGY)
            self.assertIn('read-only',client.requests[-1]['messages'][-1]['content'])
            self.assertTrue(result['steps'])
