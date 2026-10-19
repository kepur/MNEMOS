import importlib.util
from pathlib import Path
import json
import threading
import time
import unittest
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('bridge', str(Path(__file__).with_name('mtplx-responses-proxy.py')))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
TOOL = {'type':'function','name':'exec_command','parameters':{'type':'object','properties':{'cmd':{'type':'string'}},'required':['cmd']}}

def call(cmd='cat first.txt', name='exec_command'):
    return {'id':'call_test','type':'function','function':{'name':name,'arguments':json.dumps({'cmd':cmd})}}

class Backend(BaseHTTPRequestHandler):
    script=[]
    requests=[]
    headers_seen=[]
    def log_message(self,*args): pass
    def do_GET(self):
        raw=json.dumps({'data':[{'id':'test-model'}]}).encode()
        self.send_response(200);self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.path.endswith('/count_tokens'):
            raw=json.dumps({'input_tokens':len(json.dumps(body))//3}).encode()
            self.send_response(200);self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw);return
        self.requests.append(body)
        self.headers_seen.append({k.lower():v for k,v in self.headers.items()})
        step=self.script.pop(0)
        time.sleep(step.get('delay',0))
        message=step['message']
        usage={'prompt_tokens':10,'completion_tokens':5,'total_tokens':15}
        if body.get('stream'):
            delta=dict(message)
            if 'tool_calls' in delta:
                delta['tool_calls']=[dict(c,index=i) for i,c in enumerate(delta['tool_calls'])]
            packet={'choices':[{'delta':delta,'finish_reason':step.get('finish_reason')}],'usage':usage}
            if step.get('error'):packet['error']=step['error']
            raw=('data: '+json.dumps(packet)+'\n\ndata: [DONE]\n\n').encode()
            content_type='text/event-stream'
        else:
            raw=json.dumps({'choices':[{'message':message}],'usage':usage}).encode()
            content_type='application/json'
        self.send_response(200);self.send_header('Content-Type',content_type);self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)

class BridgeTest(unittest.TestCase):
    def test_stream_backend_error_keeps_original_reason(self):
        Backend.script=[{'message':{},'finish_reason':'error','error':{'message':'vision runtime incompatible'}}]
        _,events=self.request()
        self.assertEqual(events[-1]['type'],'response.failed')
        self.assertIn('vision runtime incompatible',events[-1]['response']['error']['message'])
        self.assertEqual(len(Backend.requests),1)
    def setUp(self):
        Backend.script=[];Backend.requests=[];Backend.headers_seen=[]
        self.backend=ThreadingHTTPServer(('127.0.0.1',0),Backend)
        self.backend_url=f'http://127.0.0.1:{self.backend.server_port}'
        self.traffic=[]
        self.patches=[patch.object(bridge,'_runtime',return_value={'backend':getattr(self,'backend_kind','mtplx'),'backend_url':self.backend_url,**getattr(self,'runtime_extra',{})}),patch.object(bridge,'_traffic',side_effect=self.traffic.append),patch.object(bridge,'_switcher_log')]
        for p in self.patches:p.start()
        self.server=ThreadingHTTPServer(('127.0.0.1',0),bridge.ProxyHandler)
        for s in [self.backend,self.server]:threading.Thread(target=s.serve_forever,daemon=True).start()
    def tearDown(self):
        for s in [self.server,self.backend]:s.shutdown();s.server_close()
        for p in reversed(self.patches):p.stop()
    def request(self, input_items=None, choice=None):
        body={'model':'test-model','input':input_items or '请完成检查','tools':[TOOL],'stream':True}
        if choice:body['tool_choice']=choice
        req=urllib.request.Request(f'http://127.0.0.1:{self.server.server_port}/v1/responses',data=json.dumps(body).encode(),headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(req,timeout=10) as r:raw=r.read()
        return raw,bridge._iter_sse_payloads(raw)
    def test_two_retries_callback_and_final(self):
        Backend.script=[{'message':{'content':'现在让我查看 first.txt 文件。'}},{'message':{'content':'正在执行命令 `cat first.txt`，分析中...'},'delay':2.1},{'message':{'content':'','tool_calls':[call()]}}]
        raw,events=self.request()
        self.assertIn(b': recovering-tool-call',raw)
        response=events[-1]['response']
        self.assertEqual(response['status'],'completed')
        tools=[x for x in response['output'] if x['type']=='function_call']
        self.assertEqual(len(tools),1)
        for request in Backend.requests[1:]:self.assertEqual(request['tool_choice'],'required')
        msg=next(e['item'] for e in events if e['type']=='response.output_item.done' and e['item']['type']=='message')
        self.assertEqual(msg['id'],response['output'][0]['id'])
        self.assertEqual(response['usage']['input_tokens'],30)
        Backend.script=[{'message':{'content':'','tool_calls':[call('cat second.txt')]}}]
        inputs=[{'role':'user','content':'检查两个文件'},tools[0],{'type':'function_call_output','call_id':tools[0]['call_id'],'output':'FIRST_OK'}]
        _,events=self.request(inputs)
        messages=Backend.requests[-1]['messages']
        self.assertTrue(any(m.get('role')=='tool' and m.get('content')=='FIRST_OK' for m in messages))
        self.assertEqual(json.loads(events[-1]['response']['output'][0]['arguments'])['cmd'],'cat second.txt')
        Backend.script=[{'message':{'content':'两个文件检查完成，结果正常。'}}]
        _,events=self.request()
        self.assertEqual(len(events[-1]['response']['output']),1)
        self.assertEqual(events[-1]['response']['output'][0]['type'],'message')
    def test_unrecoverable_is_delivered_pause(self):
        Backend.script=[{'message':{'content':'让我查看文件。'}}]*3
        _,events=self.request()
        self.assertEqual(events[-1]['type'],'response.completed')
        self.assertIn('任务暂停',str(events[-1]['response']['output']))
        self.assertFalse(any(e['type']=='response.failed' for e in events))
    def test_example_command_is_not_executed(self):
        Backend.script=[{'message':{'content':'可以使用 `cat first.txt` 查看内容，这是命令示例。'}}]
        _,events=self.request()
        self.assertEqual(len(Backend.requests),1)
        self.assertEqual(events[-1]['response']['output'][0]['type'],'message')
    def test_none_choice_is_respected(self):
        Backend.script=[{'message':{'content':'让我查看文件。'}}]
        _,events=self.request(choice='none')
        self.assertEqual(len(Backend.requests),1)
        self.assertEqual(Backend.requests[0]['tool_choice'],'none')
    def test_unknown_tool_is_rejected(self):
        Backend.script=[{'message':{'content':'让我查看文件。'}},{'message':{'content':'让我查看文件。','tool_calls':[call(name='made_up_tool')]}},{'message':{'content':'','tool_calls':[call()]}}]
        _,events=self.request()
        self.assertEqual(events[-1]['response']['output'][-1]['name'],'exec_command')
    def test_loop_does_not_remove_tools(self):
        inputs=[{'role':'user','content':'完成任务'}]
        for i in range(2):inputs += [{'type':'function_call','name':'exec_command','call_id':str(i),'arguments':'{"cmd":"cat first.txt"}'},{'type':'function_call_output','call_id':str(i),'output':'OK'}]
        result=bridge._chat_payload({'input':inputs,'tools':[TOOL]}, {})
        self.assertEqual(len(result['tools']),1)
    def test_detector(self):
        self.assertTrue(bridge._stalled_tool_promise('好的，我已经看到了 `arp_engine.py` 的内容。现在让我查看 `rate_limiter.py` 文件，了解限速器的实现。'))
        self.assertTrue(bridge._stalled_tool_promise('I will check the next file.'))
        self.assertTrue(bridge._stalled_tool_promise('Got chunk with value=17, next=step.json. Reading next file.'))
        self.assertTrue(bridge._stalled_tool_promise('start.json 读取到 value=11，next 指向 step.json。继续读取：'))
        self.assertTrue(bridge._stalled_tool_promise('第三个文件 value=14，next=null，链式读取完成。现在求和并写入 result.txt。'))
        self.assertFalse(bridge._stalled_tool_promise('现在已经写入完成。'))
        self.assertFalse(bridge._stalled_tool_promise('已修复并验证完成。'))
        self.assertFalse(bridge._stalled_tool_promise('分析结果：实现采用令牌桶。'))
        # Qwen Code / Qwopus thinking-off stalls from the 2026-10-09 bench
        self.assertTrue(bridge._stalled_tool_promise('Now fix `top_words()` — ties should be ordered alphabetically:'))
        self.assertTrue(bridge._stalled_tool_promise('Now update `__init__.py` to export it.Now update `exports.py` to import `compute_tax` instead of `calc_tax`.'))
        self.assertTrue(bridge._stalled_tool_promise('%V gives the wrong year. I need to use `isocalendar()` to get the ISO year and week number, then format them.'))
        self.assertTrue(bridge._stalled_tool_promise('No `import re` — need to add it:'))
        self.assertTrue(bridge._stalled_tool_promise('Good, no uncommitted changes. Let me apply all the patches now.'))
        self.assertFalse(bridge._stalled_tool_promise('Now the function breaks ties alphabetically and all 8 tests pass.'))
        self.assertFalse(bridge._stalled_tool_promise('Summary of changes:\n- fixed words()\n- fixed top_words()'))
        self.assertFalse(bridge._stalled_tool_promise('All tests pass. You may want to restart the server.'))
        self.assertTrue(bridge._stalled_tool_promise('Still failing. The `__getattr__` contains `calc_tax` in its text. I need to avoid having the literal string `calc_tax` in the `__init__.py` file.'))
        self.assertTrue(bridge._stalled_tool_promise('OK, I will rewrite the parser to handle quotes.'))
        self.assertFalse(bridge._stalled_tool_promise('Should I also update the README? I need your confirmation?'))
        self.assertFalse(bridge._stalled_tool_promise('Done. I updated three files and all tests pass.'))

class StatefulBridgeTest(BridgeTest):
    def test_pause_is_not_memoised(self):
        Backend.script=[{'message':{'content':'让我查看文件。'}}]*3
        _,events=self.request(thread='reconnect')
        self.assertEqual(events[-1]['type'],'response.completed')
        output=events[-1]['response']['output']
        self.assertIn('尚未完成',str(output))
        added=[e['item']['id'] for e in events if e['type']=='response.output_item.added']
        done=[e['item']['id'] for e in events if e['type']=='response.output_item.done']
        self.assertEqual(added,done)
        self.assertEqual(output[0]['id'],done[0])
        self.assertEqual(''.join(e['delta'] for e in events if e['type']=='response.output_text.delta'),output[0]['content'][0]['text'])
        # A retry (e.g. the user typing 继续) reaches the model again.
        count=len(Backend.requests)
        Backend.script=[{'message':{'content':'','tool_calls':[call()]}}]
        _,retry=self.request([{'role':'user','content':'完成任务'},{'role':'user','content':'继续'}],thread='reconnect')
        self.assertEqual(len(Backend.requests),count+1)
        self.assertEqual(retry[-1]['response']['output'][-1]['type'],'function_call')

    def test_continue_only_reaches_backend(self):
        Backend.script=[{'message':{'content':'好的，继续之前的工作已完成。'}}]
        _,events=self.request([{'role':'user','content':'继续完成'}],thread='no-objective')
        self.assertEqual(events[-1]['type'],'response.completed')
        self.assertEqual(len(Backend.requests),1)

    def setUp(self):
        import tempfile
        from gateway_core import Gateway
        super().setUp()
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        p=patch.object(bridge,'GATEWAY',Gateway(self.root/'memory'));p.start();self.patches.append(p)
    def tearDown(self):
        super().tearDown();self.temp.cleanup()
    def request(self,input_items=None,choice=None,thread='real-thread'):
        body={'model':'test-model','input':input_items or '完成任务','tools':[TOOL],'stream':True}
        if choice:body['tool_choice']=choice
        req=urllib.request.Request(f'http://127.0.0.1:{self.server.server_port}/v1/responses',data=json.dumps(body).encode(),headers={'Content-Type':'application/json','thread-id':thread})
        with urllib.request.urlopen(req,timeout=15) as r:raw=r.read()
        return raw,bridge._iter_sse_payloads(raw)
    def seed(self):
        f=self.root/'one.txt';f.write_text('ONE')
        Backend.script=[{'message':{'tool_calls':[call('cat '+str(f))]}}]
        _,events=self.request();tool=events[-1]['response']['output'][0]
        inputs=[{'role':'user','content':'完成任务'},tool,{'type':'function_call_output','call_id':tool['call_id'],'output':'Process exited with code 0\nOutput:\nONE'}]
        return f,inputs
    def test_repeated_read_is_forwarded_unchanged(self):
        # Loop control belongs to the client (or agentd), not the pass-through gateway.
        f,inputs=self.seed();Backend.script=[{'message':{'tool_calls':[call('cat '+str(f))]}}]
        _,events=self.request(inputs)
        self.assertEqual(events[-1]['response']['output'][-1]['type'],'function_call')
        self.assertFalse(any(e['kind']=='replan' for e in self.traffic))
        self.assertFalse(any('cached_read_evidence' in str(m) for m in Backend.requests[-1]['messages']))
    def test_100_real_http_round_trips_are_append_only(self):
        inputs=[{'role':'user','content':'FINAL_EXPECTED_42 保持原始目标'}]
        for n in range(100):
            c=call('echo step'+str(n));c['id']='step-'+str(n)
            Backend.script=[{'message':{'tool_calls':[c]}}]
            _,events=self.request(inputs,thread='long-http')
            self.assertEqual(events[-1]['type'],'response.completed')
            tool=events[-1]['response']['output'][-1]
            inputs.extend([tool,{'type':'function_call_output','call_id':tool['call_id'],'output':'Process exited with code 0\nOutput:\n'+str(n)+'x'*900}])
        Backend.script=[{'message':{'content':'FINAL_EXPECTED_42 完成。'}}]
        _,events=self.request(inputs,thread='long-http')
        self.assertEqual(events[-1]['response']['output'][0]['type'],'message')
        sent=[r['messages'] for r in Backend.requests[1:]]
        for before,after in zip(sent,sent[1:]):
            self.assertEqual(after[:len(before)],before)
        self.assertEqual(len(sent[-1]),1+1+2*100)
        self.assertEqual(sent[-1][0]['role'],'system')
        self.assertIn('Codex 工具协议',sent[-1][0]['content'])
        self.assertEqual(sent[-1][-1]['role'],'tool')
        self.assertEqual(len({r['metadata']['session_id'] for r in Backend.requests[1:]}),1)

class ChatCompatibilityTest(BridgeTest):
    def test_chat_paused_task_is_delivered_as_text_and_stop(self):
        for stream in (True,False):
            Backend.script=[{'message':{'content':'让我查看文件。'}}]*3
            raw,_=self.chat([{'role':'user','content':'完成任务'}],stream,session='paused-'+str(stream))
            if stream:
                chunks=bridge._iter_sse_payloads(raw)
                self.assertEqual(chunks[-1]['choices'][0]['finish_reason'],'stop')
                self.assertIn('任务暂停',''.join(x.get('choices',[{}])[0].get('delta',{}).get('content','') for x in chunks))
            else:
                self.assertIn('任务暂停',json.loads(raw)['choices'][0]['message']['content'])
    def chat(self,messages,stream=True,session='opencode-unique'):
        body={'model':'test-model','messages':messages,'tools':[{'type':'function','function':{k:v for k,v in TOOL.items() if k!='type'}}],'stream':stream}
        req=urllib.request.Request(f'http://127.0.0.1:{self.server.server_port}/v1/chat/completions',data=json.dumps(body).encode(),headers={'Content-Type':'application/json','x-opencode-session':session,'User-Agent':'opencode/1.3.15 ai-sdk/5'})
        with urllib.request.urlopen(req,timeout=15) as r:raw=r.read();content=r.headers['Content-Type']
        return raw,content
    def test_stream_chat_tools_usage_and_callback(self):
        Backend.script=[{'message':{'tool_calls':[call()]}}]
        raw,ctype=self.chat([{'role':'user','content':'read file'}])
        chunks=bridge._iter_sse_payloads(raw);self.assertIn(b'[DONE]',raw);self.assertNotIn(b'event: response',raw)
        calls=[c for x in chunks for c in (x.get('choices') or [{}])[0].get('delta',{}).get('tool_calls',[])]
        self.assertEqual(calls[0]['function']['name'],'exec_command');self.assertEqual(chunks[-1]['choices'][0]['finish_reason'],'tool_calls')
        Backend.script=[{'message':{'content':'completed'}}]
        raw,_=self.chat([{'role':'user','content':'read file'},{'role':'assistant','content':None,'tool_calls':calls},{'role':'tool','tool_call_id':calls[0]['id'],'content':'Process exited with code 0\nOutput:\nOK'}])
        self.assertTrue(any(m.get('role')=='tool' for m in Backend.requests[-1]['messages']))
        self.assertEqual(bridge._iter_sse_payloads(raw)[-1]['choices'][0]['finish_reason'],'stop')
    def test_opencode_identity_reaches_backend(self):
        Backend.script=[{'message':{'content':'','tool_calls':[call()]}},{'message':{'content':'','tool_calls':[call()]}}]*2
        self.chat([{'role':'user','content':'read file'}])
        seen=Backend.headers_seen[-1]
        self.assertEqual(seen.get('x-mtplx-client'),'opencode')
        self.assertIn('opencode',seen.get('user-agent',''))
        self.assertEqual(Backend.requests[-1]['metadata']['thread_id'],'opencode-opencode-unique')
        self.assertEqual([e for e in self.traffic if e['kind']=='start'][-1]['client'],'opencode')
    def test_nonstream_json_and_multimodal_preserved(self):
        Backend.script=[{'message':{'content':'red square'}}]
        raw,ctype=self.chat([{'role':'user','content':[{'type':'text','text':'describe'},{'type':'image_url','image_url':{'url':'data:image/png;base64,abc'}}]}],False)
        self.assertIn('application/json',ctype);self.assertEqual(json.loads(raw)['choices'][0]['message']['content'],'red square')
        self.assertTrue(any(isinstance(m.get('content'),list) and any(p.get('type')=='image_url' for p in m['content']) for m in Backend.requests[-1]['messages']))

class AnthropicPassthroughTest(BridgeTest):
    def messages(self, body, ua='claude-cli/2.1.74 (external, cli)'):
        req=urllib.request.Request(f'http://127.0.0.1:{self.server.server_port}/v1/messages',data=json.dumps(body).encode(),
            headers={'Content-Type':'application/json','anthropic-version':'2023-06-01','User-Agent':ua})
        with urllib.request.urlopen(req,timeout=15) as r:return r.read(),r.headers.get('Content-Type')
    def test_thinking_model_and_session_follow_the_switcher(self):
        Backend.script=[{'message':{'content':'hi'}}]
        body={'model':'claude-haiku-4-5','max_tokens':64,'stream':False,'messages':[{'role':'user','content':'hi'}],
              'metadata':{'user_id':'user_abc_account_def_session_0b5f-77'}}
        raw,ctype=self.messages(body)
        sent=Backend.requests[-1];seen=Backend.headers_seen[-1]
        self.assertEqual(sent['thinking'],{'type':'disabled'})
        self.assertEqual(sent['model'],'test-model')
        self.assertEqual(sent['metadata'],body['metadata'])
        self.assertTrue(seen.get('x-mtplx-session-id'))
        self.assertIn('claude-cli',seen.get('user-agent',''))
        self.assertIn('application/json',ctype)
        self.assertEqual(json.loads(raw)['choices'][0]['message']['content'],'hi')
        self.assertEqual([e for e in self.traffic if e['kind']=='start'][-1]['client'],'claude')
        Backend.script=[{'message':{'content':'again'}}]
        self.messages({**body,'thinking':{'type':'enabled','budget_tokens':1024}})
        self.assertEqual(Backend.requests[-1]['thinking']['type'],'enabled')
        self.assertEqual(Backend.headers_seen[-1].get('x-mtplx-session-id'),seen.get('x-mtplx-session-id'))
    def test_stream_is_relayed_verbatim(self):
        Backend.script=[{'message':{'content':'streamed'}}]
        raw,ctype=self.messages({'model':'x','max_tokens':8,'stream':True,'messages':[{'role':'user','content':'go'}]})
        self.assertIn('text/event-stream',ctype)
        self.assertIn(b'streamed',raw);self.assertIn(b'[DONE]',raw)


class OmlxBackendTest(ChatCompatibilityTest):
    """oMLX: named model, template-level thinking switch, API key only on its port."""
    backend_kind='omlx'
    runtime_extra={'api_model':'omlx-model','enable_thinking':False,'reasoning_effort':'medium'}
    def setUp(self):
        super().setUp()
        import tempfile, gateway_core
        self.tmp=tempfile.TemporaryDirectory()
        settings=Path(self.tmp.name)/'settings.json'
        settings.write_text(json.dumps({'server':{'port':self.backend.server_port},'auth':{'api_key':'k-test'}}))
        self.settings_patch=patch.object(gateway_core,'OMLX_SETTINGS',settings);self.settings_patch.start()
        gateway_core._omlx_cache['mtime']=None
        gateway_core.install_backend_auth()
    def tearDown(self):
        urllib.request.install_opener(None)
        self.settings_patch.stop();self.tmp.cleanup()
        super().tearDown()
    def test_chat_payload_named_model_and_thinking_off(self):
        Backend.script=[{'message':{'content':'done'}}]
        history=[{'role':'user','content':'x'*4000},{'role':'assistant','content':'y'*4000}]*30+[{'role':'user','content':'go'}]
        self.chat(history)
        sent=Backend.requests[-1]
        self.assertEqual(sent['model'],'omlx-model')
        self.assertEqual(sent['chat_template_kwargs'],{'enable_thinking':False})
        self.assertEqual(sent['reasoning_effort'],'low');self.assertNotIn('enable_thinking',sent)
        self.assertFalse(sent['parallel_tool_calls'])
        # append-only: the long history reaches the backend unclipped
        self.assertEqual(sum(1 for m in sent['messages'] if m['role']!='system'),len(history))
        self.assertEqual(Backend.headers_seen[-1].get('authorization'),'Bearer k-test')
    def test_thinking_on_sends_effort(self):
        self.runtime_extra={**self.runtime_extra,'enable_thinking':True,'reasoning_effort':'high'}
        with patch.object(bridge,'_runtime',return_value={'backend':'omlx','backend_url':self.backend_url,**self.runtime_extra}):
            Backend.script=[{'message':{'content':'done'}}]
            self.chat([{'role':'user','content':'go'}])
        sent=Backend.requests[-1]
        self.assertEqual(sent['chat_template_kwargs'],{'enable_thinking':True});self.assertEqual(sent['reasoning_effort'],'high')
    def test_key_only_sent_to_omlx_port(self):
        other=ThreadingHTTPServer(('127.0.0.1',0),Backend);threading.Thread(target=other.serve_forever,daemon=True).start()
        try:
            urllib.request.urlopen(f'http://127.0.0.1:{other.server_port}/v1/models',timeout=5).read()
            urllib.request.urlopen(f'{self.backend_url}/v1/models',timeout=5).read()
        finally:
            other.shutdown();other.server_close()
        Backend.script=[{'message':{'content':'ok'}}]
        self.chat([{'role':'user','content':'go'}])
        self.assertEqual(Backend.headers_seen[-1].get('authorization'),'Bearer k-test')
    messages=AnthropicPassthroughTest.messages
    def test_claude_code_is_translated_to_chat(self):
        # oMLX's /v1/messages leaves Nemotron's reasoning in the text; its chat endpoint splits it.
        Backend.script=[{'message':{'content':'hi','reasoning_content':'thinking...'}}]
        raw,_=self.messages({'model':'claude-haiku-4-5','max_tokens':64,'stream':False,'messages':[{'role':'user','content':'hi'}]})
        sent=Backend.requests[-1]
        self.assertEqual(sent['model'],'omlx-model');self.assertIn('messages',sent);self.assertNotIn('thinking',sent)
        self.assertEqual(sent['chat_template_kwargs'],{'enable_thinking':False});self.assertEqual(sent['reasoning_effort'],'low')
        self.assertEqual(json.loads(raw)['content'][0]['text'],'hi')
        self.assertEqual(Backend.headers_seen[-1].get('authorization'),'Bearer k-test')


class AnthropicTranslateTest(unittest.TestCase):
    """Backends without /v1/messages (Bonsai): the gateway translates."""
    backend_kind='bonsai'
    setUp=BridgeTest.setUp
    tearDown=BridgeTest.tearDown
    def post(self, path, body):
        req=urllib.request.Request(f'http://127.0.0.1:{self.server.server_port}{path}',data=json.dumps(body).encode(),
            headers={'Content-Type':'application/json','anthropic-version':'2023-06-01','User-Agent':'claude-cli/2.1.74'})
        with urllib.request.urlopen(req,timeout=15) as r:return r.read(),r.headers.get('Content-Type')
    def test_tool_history_and_tool_use_reply(self):
        Backend.script=[{'message':{'content':'','tool_calls':[{'id':'c9','type':'function','function':{'name':'Read','arguments':'{"file_path":"a.py"}'}}]}}]
        body={'model':'claude-sonnet-4-5','max_tokens':256,'system':[{'type':'text','text':'You are helpful.'}],
              'tools':[{'name':'Read','description':'read a file','input_schema':{'type':'object','properties':{'file_path':{'type':'string'}}}}],
              'messages':[{'role':'user','content':'open a.py'},
                          {'role':'assistant','content':[{'type':'text','text':'Reading.'},{'type':'tool_use','id':'c1','name':'Read','input':{'file_path':'b.py'}}]},
                          {'role':'user','content':[{'type':'tool_result','tool_use_id':'c1','content':'print(1)'},{'type':'text','text':'now a.py'}]}]}
        raw,ctype=self.post('/v1/messages',body)
        sent=Backend.requests[-1]
        self.assertEqual([m['role'] for m in sent['messages']],['system','user','assistant','tool','user'])
        self.assertEqual(sent['messages'][2]['tool_calls'][0]['function']['name'],'Read')
        self.assertEqual(sent['messages'][3],{'role':'tool','tool_call_id':'c1','content':'print(1)'})
        self.assertEqual(sent['tools'][0]['function']['parameters']['properties']['file_path']['type'],'string')
        self.assertEqual(sent['model'],'test-model')
        reply=json.loads(raw)
        self.assertEqual(reply['type'],'message');self.assertEqual(reply['stop_reason'],'tool_use')
        self.assertEqual(reply['content'][-1],{'type':'tool_use','id':'c9','name':'Read','input':{'file_path':'a.py'}})
    def test_stream_events(self):
        Backend.script=[{'message':{'content':'Let me read it.','tool_calls':[{'id':'c2','type':'function','function':{'name':'Read','arguments':'{"file_path":"x"}'}}]}}]
        raw,ctype=self.post('/v1/messages',{'model':'x','max_tokens':64,'stream':True,'messages':[{'role':'user','content':'go'}]})
        self.assertIn('text/event-stream',ctype)
        events=[json.loads(line[6:]) for line in raw.decode().splitlines() if line.startswith('data: ')]
        kinds=[e['type'] for e in events]
        self.assertEqual(kinds[0],'message_start');self.assertEqual(kinds[-2:],['message_delta','message_stop'])
        self.assertIn({'type':'text_delta','text':'Let me read it.'},[e.get('delta') for e in events])
        starts=[e['content_block'] for e in events if e['type']=='content_block_start']
        self.assertEqual([b['type'] for b in starts],['text','tool_use']);self.assertEqual(starts[1]['name'],'Read')
        self.assertIn({'type':'input_json_delta','partial_json':'{"file_path":"x"}'},[e.get('delta') for e in events])
        self.assertEqual(events[-2]['delta']['stop_reason'],'tool_use')
        self.assertEqual(kinds.count('content_block_start'),kinds.count('content_block_stop'))
    def test_count_tokens(self):
        raw,_=self.post('/v1/messages/count_tokens',{'model':'x','messages':[{'role':'user','content':'hello world'}]})
        self.assertGreater(json.loads(raw)['input_tokens'],0)

class ModelsListTest(BridgeTest):
    def test_models_lists_active_and_aliases(self):
        with urllib.request.urlopen(f'http://127.0.0.1:{self.server.server_port}/v1/models',timeout=10) as r:body=json.load(r)
        self.assertEqual([m['id'] for m in body['data']],['test-model','active','local'])
        self.assertEqual(body['models'],[])


if __name__=='__main__':unittest.main(verbosity=2)
