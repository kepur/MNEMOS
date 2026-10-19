#!/usr/bin/env python3
"""MTPLX 2.11.0: connect its existing vision prefill to target-only AR.

No draft head is enabled. Image requests bypass AR session snapshots to avoid
reusing token-identical state across different pixels. Text cache is unchanged.
Fail on source drift rather than blindly patching another version.
"""
from pathlib import Path
import ast
import importlib.metadata
import sys


def runtime_changes(root):
    path = root / 'runtime.py'
    source = path.read_text()
    if '# serafina_ar_vision_v1' in source: return {}
    guard = '''        if input_embeddings is not None and not self.mtp_enabled:
            raise RuntimeError("vision splice requires the MTP-patched runtime")'''
    assert source.count(guard) == 1
    source = source.replace(guard, '''        if input_embeddings is not None and not self.mtp_enabled:
            # serafina_ar_vision_v1: stock Qwen target accepts pixel embeddings.
            # Do not pass the MTP-only return_hidden/emit_logits keywords.
            import inspect
            if "input_embeddings" not in inspect.signature(self.model.__call__).parameters:
                raise RuntimeError("target-only runtime does not accept vision embeddings")
            logits = self.model(input_ids, cache=cache, input_embeddings=input_embeddings)
            return logits[:, -int(logits_keep):, :] if logits_keep else logits''')
    ast.parse(source)
    return {path: source}


def counter_changes(root, pending):
    path = root / 'server/openai.py'
    source = pending.get(path, path.read_text())
    if '# serafina_chat_counter_v1' in source: return {}
    marker = '    @app.post("/v1/messages/count_tokens")'
    assert source.count(marker) == 1
    endpoint = '''    # serafina_chat_counter_v1: same chat template and image grid as generation.
    @app.post("/v1/gateway/count_tokens")
    async def gateway_count_tokens(raw_request: Request, request: ChatCompletionRequest) -> Any:
        headers = dict(raw_request.headers)
        policy = resolve_request_policy(state, request, headers=headers,
            metadata=_request_metadata(request), endpoint="count_tokens")
        messages, images = _vision_extract_and_flatten(policy.messages_for_generation)
        prompt_ids = _encode_messages(state.runtime.tokenizer, messages,
            enable_thinking=policy.thinking_enabled,
            reasoning_effort=policy.reasoning_effort,
            strip_assistant_reasoning_history=state.args.strip_assistant_reasoning_history,
            scoped_reasoning_history=_reasoning_history_scoped_active(state),
            preserve_reasoning_history=_reasoning_history_preserve_echo_active(state),
            tools=policy.tool_specs if policy.tools_active else None,
            tool_choice=request.tool_choice, tool_prompt_mode=policy.tool_prompt_mode)
        if images:
            from mtplx.vision.processing import decode_image, image_pad_token_count, preprocess_images
            spec = _server_vision_spec(state)
            if spec is None: raise HTTPException(status_code=400, detail="model has no vision tower")
            config = json.loads((Path(str(state.args.model)) / "preprocessor_config.json").read_text())
            counts = []
            for raw in images:
                pixels, grids = preprocess_images([decode_image(raw)], config)
                counts.append(image_pad_token_count(grids[0]))
                del pixels
            prompt_ids = _expand_image_pads(prompt_ids, image_pad_id=int(spec.image_token_id), pad_counts=counts)
        return {"input_tokens": len(prompt_ids)}

'''
    source = source.replace(marker, endpoint + marker)
    ast.parse(source)
    return {path: source}


def patched(root):
    if importlib.metadata.version('mtplx') != '2.11.0':
        raise RuntimeError('This compatibility patch is only verified on MTPLX 2.11.0')
    gen = root / 'generation.py'
    server = root / 'server/openai.py'
    g, s = gen.read_text(), server.read_text()
    if '# serafina_ar_vision_v1' in g and '# serafina_ar_vision_v1' in s:
        return {}
    start, end = g.index('def generate_ar('), g.index('\ndef generate_mtp1(')
    block = g[start:end]
    signature = '    abort_check: Callable[[], bool] | None = None,\n) -> GenerationOutput:'
    assert block.count(signature) == 1
    block = block.replace(signature, '    abort_check: Callable[[], bool] | None = None,\n    vision_splice: Any | None = None,\n) -> GenerationOutput:')
    marker = '    reject_non_k1_a3b_whole_moe_request(rt, entrypoint="generate_ar")'
    assert marker in block
    block = block.replace(marker, marker + '\n    # serafina_ar_vision_v1: pixel state is request-local in target-only AR.\n    if vision_splice is not None:\n        session_bank = None\n        capture_final_state = False\n        vision_splice.reset()')
    prefill = '        capture_hidden=ar_return_hidden,\n'
    assert block.count(prefill) == 1
    block = block.replace(prefill, prefill + '        vision_splice=vision_splice,\n')
    g = g[:start] + '@_with_vision_rope\n' + block + g[end:]
    guard = '''            if str(request_generation_mode or "") == "ar":
                raise HTTPException(
                    status_code=400,
                    detail="image content requires MTP generation mode",
                )'''
    assert s.count(guard) == 1
    s = s.replace(guard, '            # serafina_ar_vision_v1: target-only AR accepts the vision splice.')
    ar_call = '                    out = generate_ar(\n                        state.runtime,\n                        prompt_ids,\n'
    assert s.count(ar_call) == 1
    s = s.replace(ar_call, ar_call + '                        vision_splice=vision_splice,\n')
    ast.parse(g); ast.parse(s)
    return {gen: g, server: s}


if __name__ == '__main__':
    root = Path(sys.prefix) / 'lib/python3.12/site-packages/mtplx'
    changes = {**patched(root), **runtime_changes(root)}
    changes.update(counter_changes(root, changes))
    for path, source in changes.items():
        backup = path.with_suffix(path.suffix + '.serafina-original')
        if not backup.exists(): backup.write_bytes(path.read_bytes())
        path.write_text(source)
    print('AR vision patch applied' if changes else 'AR vision patch already installed')
