import json, tempfile, threading, time, unittest
from pathlib import Path
from gateway_core import Gateway, Identity, SerialQueue, Blocked, Cancelled, dumps


class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.g=Gateway(self.root/'memory')
        self.i=Identity('thread-a',cwd=str(self.root))
    def tearDown(self):self.tmp.cleanup()

    def test_prepare_is_pass_through(self):
        messages=[{'role':'system','content':'rules'},{'role':'user','content':'继续完成'}]
        for n in range(60):
            messages+=[{'role':'assistant','content':None,'tool_calls':[{'id':str(n),'function':{'name':'exec_command','arguments':'{}'}}]},
                       {'role':'tool','tool_call_id':str(n),'content':'Process exited with code 0\nOutput:\n'+'x'*2000}]
        body={'model':'m','messages':list(messages),'max_tokens':8192}
        events=[]
        out=self.g.prepare(self.i,messages,body,events.append)
        self.assertEqual(out['messages'],messages)
        self.assertEqual(out['max_tokens'],8192)
        self.assertEqual(out['metadata']['session_id'],self.i.key)
        self.assertEqual(events[-1]['kind'],'tool_result')
        self.assertNotIn('metadata',body)

    def test_identity_never_hashes_shared_system_prompt(self):
        m=[{'role':'system','content':'same prompt'}]
        a=Identity.resolve({'thread-id':'one'}, {},m);b=Identity.resolve({'thread-id':'two'}, {},m)
        self.assertNotEqual(a.key,b.key)
        self.assertNotEqual(Identity.resolve({}, {},m).key,Identity.resolve({}, {},m).key)
        child=Identity.resolve({'x-codex-turn-metadata':dumps({'thread_id':'one','agent_name':'/root/worker'})},{},m)
        self.assertTrue(child.child);self.assertNotEqual(child.key,a.key)
        self.assertEqual(Identity.resolve({'x-opencode-session':'s1'},{},m).thread,'opencode-s1')

    def test_generic_session_keys_and_anonymous_requests(self):
        m=[{'role':'user','content':'x'}]
        a=Identity.resolve({},{'prompt_cache_key':'qwen-code-ses-1'},m);b=Identity.resolve({},{'prompt_cache_key':'qwen-code-ses-1'},m)
        self.assertTrue(a.persistent);self.assertEqual(a.key,b.key);self.assertEqual(a.thread,'client-qwen-code-ses-1')
        self.assertEqual(Identity.resolve({'X-Session-Id':'s9'},{},m).thread,'client-s9')
        claude=Identity.resolve({},{'metadata':{'user_id':'user_x_account_y_session_9f2c-1a'}},m)
        self.assertEqual(claude.thread,'client-9f2c-1a')
        anon=Identity.resolve({},{},m);self.assertFalse(anon.persistent)
        self.assertNotIn('metadata',self.g.prepare(anon,m,{'messages':m},lambda _:None))

    def test_fifo_single_active_and_queued_cancel(self):
        q=SerialQueue();order=[];hold=threading.Event();active=threading.Event();cancel=threading.Event()
        def first():
            with q.lease(self.i,'1',lambda:False,lambda *_:None):active.set();hold.wait(3);order.append('1')
        def next_job(id,cancelled):
            try:
                with q.lease(Identity('thread-'+id),id,cancelled,lambda *_:None):order.append(id)
            except Cancelled:order.append('cancelled')
        a=threading.Thread(target=first);a.start();active.wait(1)
        b=threading.Thread(target=next_job,args=('2',cancel.is_set));b.start()
        while q.snapshot()['queued']<1:time.sleep(.01)
        d=threading.Thread(target=next_job,args=('3',lambda:False));d.start();cancel.set();b.join(2);hold.set();a.join(2);d.join(2)
        self.assertEqual(order,['cancelled','1','3']);self.assertEqual(q.snapshot()['peak_active'],1)

    def test_nested_child_rejected_and_fork_disabled(self):
        with self.assertRaises(Blocked):
            with self.g.queue.lease(Identity('a','/root/child/nested'),'a',lambda:False,lambda *_:None):pass
        c={'function':{'name':'spawn_agent','arguments':dumps({'message':'read specific file','fork_context':True})}}
        updated=self.g.policy_calls(self.i,[c]);self.assertFalse(json.loads(updated[0]['function']['arguments'])['fork_context'])
        with self.assertRaises(Blocked):self.g.policy_calls(Identity('a','/root/worker'),[c])

    def test_speeds_and_status(self):
        self.g.store.record_speed('local/m',{'prompt_tokens':1000,'completion_tokens':100,'prefill_tok_s':500,'decode_tok_s':50},'r1')
        status=self.g.status()
        self.assertAlmostEqual(status['speeds']['m']['decode_tok_s'],50)
        self.assertEqual(status['context_policy'],'append_only')

if __name__=='__main__':unittest.main(verbosity=2)
