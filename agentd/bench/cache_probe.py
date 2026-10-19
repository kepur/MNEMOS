"""Reproduce how the backend reuses a session's prefix across agent rounds.

    python3 -m agentd.bench.cache_probe [--rounds 7] [--mode hybrid|native|compact] [--stream]

Each round appends one tool call and its result (strictly append-only), so a
correct session cache restores the whole previous prompt every time. Printed
per round: prompt tokens, restored (cached) tokens and the restore mode.
"""
import argparse
import json
import urllib.request
import uuid

from agentd import config as cfg
from agentd import prompts
from agentd.llm import ModelClient
from agentd.tools import SCHEMAS


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rounds', type=int, default=7)
    parser.add_argument('--mode', help='x-mtplx-tool-prompt-mode header (default: server setting)')
    parser.add_argument('--stream', action='store_true')
    parser.add_argument('--tool-choice', default='required')
    parser.add_argument('--thinking', choices=('on', 'off'), help='override runtime.json enable_thinking')
    parser.add_argument('--args-dict', action='store_true', help='echo tool-call arguments as objects')
    parser.add_argument('--verbose', action='store_true', help='print snapshot/restore diagnostics')
    args = parser.parse_args()
    client = ModelClient()
    sid = f'cache-probe-{uuid.uuid4().hex[:8]}'
    files = {f'part{i}.txt': f'part {i}: ' + 'lorem ipsum dolor sit amet ' * 40 + '\n' for i in range(1, args.rounds + 2)}
    messages = [{'role': 'system', 'content': prompts.SYSTEM},
                {'role': 'user', 'content': f'[{sid}] Read part1.txt, part2.txt, ... in order with read_file, '
                                            'one call per reply, until told to stop.'}]
    for rnd in range(1, args.rounds + 1):
        body = {'model': client.model, 'messages': messages, 'tools': SCHEMAS, 'tool_choice': args.tool_choice,
                'parallel_tool_calls': False, 'max_tokens': 512, 'stream': args.stream,
                'enable_thinking': (args.thinking == 'on') if args.thinking else bool(cfg.runtime().get('enable_thinking', True)),
                'metadata': {'session_id': sid}}
        if args.stream:
            body['stream_options'] = {'include_usage': True}
        headers = {'Content-Type': 'application/json', 'x-mtplx-session-id': sid}
        if args.mode:
            headers['x-mtplx-tool-prompt-mode'] = args.mode
        request = urllib.request.Request(client.backend + '/v1/chat/completions', data=json.dumps(body).encode(), headers=headers)
        calls, usage, stats = {}, {}, {}
        with urllib.request.urlopen(request, timeout=600) as response:
            if not args.stream:
                data = json.load(response)
                usage, stats = data.get('usage') or {}, data.get('mtplx_stats') or {}
                calls = dict(enumerate(data['choices'][0]['message'].get('tool_calls') or []))
            else:
                for raw in response:
                    line = raw.decode().strip()
                    if not line.startswith('data: ') or line == 'data: [DONE]':
                        continue
                    chunk = json.loads(line[6:])
                    usage = chunk.get('usage') or usage
                    stats = chunk.get('mtplx_stats') or stats
                    for choice in chunk.get('choices') or []:
                        for c in (choice.get('delta') or {}).get('tool_calls') or []:
                            slot = calls.setdefault(c.get('index', 0), {'id': '', 'type': 'function', 'function': {'name': '', 'arguments': ''}})
                            slot['id'] = c.get('id') or slot['id']
                            slot['function']['name'] += (c.get('function') or {}).get('name') or ''
                            slot['function']['arguments'] += (c.get('function') or {}).get('arguments') or ''
        cached = (usage.get('prompt_tokens_details') or {}).get('cached_tokens', 0)
        previous = 0 if rnd == 1 else last_prompt
        verdict = 'full' if rnd > 1 and cached >= previous else ('partial' if cached else 'cold')
        print(f'r{rnd}: prompt {usage.get("prompt_tokens")} cached {cached} ({verdict}) '
              f'restore={stats.get("session_restore_mode")}', flush=True)
        if args.verbose:
            post = stats.get('session_postcommit_snapshot') or {}
            served = stats.get('session_restore_served') or {}
            print(f'    miss={stats.get("cache_miss_reason")} live={stats.get("live_frontier_miss_reason")} '
                  f'served(entry={served.get("entry_prefix_len")} matched={served.get("requested_matched")} '
                  f'point={served.get("actual_restore_point")}) postcommit(stored={post.get("stored")} '
                  f'mode={post.get("mode")} prefix={post.get("prefix_len")} reason={post.get("reason") or post.get("skip_reason")})',
                  flush=True)
        last_prompt = int(usage.get('prompt_tokens') or 0)
        tool_calls = [calls[i] for i in sorted(calls)]
        echoed = tool_calls
        if args.args_dict:
            echoed = [{**c, 'function': {**c['function'], 'arguments': json.loads(c['function']['arguments'] or '{}')}}
                      for c in tool_calls]
        messages.append({'role': 'assistant', 'content': '', 'tool_calls': echoed})
        for call in tool_calls:
            path = json.loads(call['function']['arguments'] or '{}').get('path', '')
            messages.append({'role': 'tool', 'tool_call_id': call.get('id'), 'content': files.get(path, 'not found')})
        if not tool_calls:
            messages.append({'role': 'user', 'content': 'Call read_file for the next part.'})


if __name__ == '__main__':
    main()
