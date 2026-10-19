# 本地 Agent 架构（agentd + 透传网关）

## 核心原则

1. **流程控制写在代码里，模型只填受限的格子。** 下一步做什么、何时算完成、失败后怎么办，由 Orchestrator 状态机决定，不由模型决定。
2. **完成以验收命令为准。** 模型调用 `finish` 后，由系统运行验收命令，退出码为 0 才算完成。
3. **Prompt 只追加，不改写。** MTPLX 的 session bank 只能复用逐 token 一致的前缀；Qwen3-Next 混合架构的循环状态无法回退到中间位置，改写任何一处历史，下一轮都要整段重新 prefill。
4. **记忆来自账本，不来自摘要。** 新会话由「任务卡 + 账本事实 + 结构化交接」组成，不重放旧对话，也不让模型去总结历史。
5. **一条推理通道，工具并行。** GPU 和内存带宽是共享的；多 Agent 的收益来自"A 跑测试时 B 用 GPU"，而不是同时推理。

## 组件

```
CLI: python3 -m agentd run ...          Codex / OpenCode（交互式对话）
          │                                        │
agentd/orchestrator.py  任务状态机               mtplx-responses-proxy.py :8002
agentd/worker.py        会话循环 + 保护规则        gateway_core.py：透传、身份、串行队列、速度统计
agentd/tools.py         9 个工具，限定在工作区内           │
agentd/ledger.py        SQLite 账本                       │
agentd/llm.py           模型客户端 + 优先级通道 ───────────┤
                                MTPLX :8000 · LM Studio :1234 · oMLX :7777 · Bonsai :2386
                                （同一时间只占用一个后端，切换时其余后端释放显存）
```

- **网关（:8002）** 只负责协议转换、会话身份（决定缓存亲和）、单通道队列和指标。它不压缩历史、不注入证据、不拦截重复调用，也不固化 Blocked。上下文由 Codex 的 auto-compact 管理（131072 窗口，98304 时压缩）。
  - 支持的协议：Responses（Codex）、Chat Completions（OpenCode、Qwen Code），以及透传到 MTPLX 的 Anthropic Messages `/v1/messages`（Claude Code）。所有请求都使用切换器当前的模型和思考开关。
  - 会话身份的识别顺序：Codex 的 `thread-id`/turn 元数据 → `x-opencode-session`（serafina 插件设置）→ `x-session-id` → `prompt_cache_key`（Qwen Code）→ `metadata.user_id` 中的 session 段（Claude Code）。都识别不到时不发送会话 ID，由 MTPLX 按前缀自行匹配。
  - 转发客户端原始的 User-Agent，OpenCode 请求额外带上 `x-mtplx-client: opencode`，让 MTPLX 使用针对各客户端的缓存策略。

## 本地中转站（网关 :8002）

| 协议 | 端点 | MTPLX | LM Studio | oMLX | Bonsai |
|---|---|---|---|---|---|
| OpenAI Chat Completions | `POST /v1/chat/completions` | 转发 | 转发 | 转发，自动带 oMLX 的 API key | 转发 |
| OpenAI Responses（Codex） | `POST /v1/responses` | 转成 Chat 后转发 | 同左 | 同左 | 同左 |
| Anthropic Messages（Claude Code） | `POST /v1/messages`、`/v1/messages/count_tokens` | 原生透传，并补上思考开关 | 原生透传 | 网关转换成 Chat（oMLX 的 `/v1/messages` 不会把 Nemotron 的推理和正文分开） | 网关转换成 Chat（含流式、工具调用、图片） |
| 模型列表 | `GET /v1/models` | 当前加载的模型，加上别名 `active`、`local` | 同左 | 同左 | 同左 |

- 地址：OpenAI 协议用 `http://127.0.0.1:8002/v1`，Anthropic 协议用 `http://127.0.0.1:8002`。API key 填任意非空值（比如 `local`），只监听本机，不做校验。模型名写什么都行，统一转给当前加载的模型。
- 切换器 App 里点"API 接入"（主窗口或菜单栏菜单都有），可以复制地址和 token，还有 Claude Code、Codex、OpenCode、Qwen Code、Pi、Hermes、Cursor/Cline、Python SDK、curl 的配置示例。

## oMLX 后端（2026-10-11）

有些模型 MTPLX 和 LM Studio 加载不了，就交给 oMLX（用户本机的 `/Applications/oMLX.app`，端口和 API key 都在 `~/.omlx/settings.json`）。

- **认证**：`gateway_core.install_backend_auth()` 给发往 oMLX 本机端口的 urllib 请求自动加上 `Authorization: Bearer <key>`。key 每次从 oMLX 自己的设置文件读取，不复制、不写日志。网关、agentd、`omlx_ctl.py` 共用这一处逻辑。
- **思考开关**：发 `chat_template_kwargs.enable_thinking`，同时发 `reasoning_effort`（关思考时发 `low`）。Nemotron 和 Ling 看前者；K2 的模板只认后者，默认 high，没有关闭开关。
- **历史**：和 MTPLX 一样只追加、不裁剪，这样能吃到 oMLX 的分页前缀缓存。
- **启停**：`omlx_ctl.py ensure|loaded|release`。`start-qwen38.sh` 的 omlx 分支会停掉 MTPLX、卸载 LM Studio，然后加载目标模型。其他后端启动前先执行 `release`。单独卸载一个模型需要管理员会话，所以 release 的做法是重启 oMLX 服务，重启后不加载任何模型。健康检查和 daemon 脚本用 `omlx_ctl.py loaded` 判断模型是否已加载。
- **模型目录**：`/Users/mac/AinerWorkFlow/mlx localagent_model/models/llm/`（oMLX 的 model_dir，按"组织/模型"两级结构扫描）。
  - Nemotron 3.5 Lightning：软链接到 LM Studio 目录里的同一份权重。
  - K2 Horizon MoVA：DreamFoundries 的 4bit 转换用的是它自己 fork 的权重名（`switch_mlp`、`switch_v`）。分片用 APFS 克隆（`cp -c`，不额外占磁盘），只把 safetensors 文件头里的名字改成 oMLX 原生实现的 `experts`、`v_experts`，头部补空格保持原长度，张量字节和偏移都不变。
  - Ling 3.0 Flash oQ2：仓库自带 `bailing_hybrid.py`，需要 trust_remote_code。这里不执行这份代码，而是走 mlx-lm 官方的 `bailing_moe_v3`。两者只差 40 个 MoE router：官方实现要浮点权重，checkpoint 存的是 8bit。所以把 router 精确反量化成 bf16，单独存成 `model-router-gates.safetensors`（约 100MB）；原来的 router 键改名为 `model.layers.9NN.*`，加载时被 sanitize 当作 MTP 层丢掉。其余分片同样是 APFS 克隆。
  - 原始权重目录都没有改动。
- **实测**（oMLX，单请求，短提示 / 约 7K / 约 14K 上下文的解码 tok/s）：Nemotron 94 / 71 / 51，预填充 650–1100；K2 43 / 28 / 23，预填充 250–380；Ling 23 / 24 / 25，预填充 190–390。同一份 Nemotron 权重在 LM Studio 上是 55 / 46 / 44；在 MTPLX 上是 57 / 62 / 57，走 AR，MTP 头没有生效。
- **OpenCode 基准**（5 个任务，思考开 + medium）：

  | 模型（oMLX） | 通过 | 总耗时 | 备注 |
  |---|---|---|---|
  | Nemotron 3.5 Lightning 30B A3B | 5/5 | 783 秒 | 对照：Qwopus（MTPLX，思考关）5/5，991 秒 |
  | K2 Horizon MoVA 36B A4B | 4/5 | 431 秒 | 回答简短、轮数少；refactor_rename 只改了 3 个文件就宣布完成 |
  | Ling 3.0 Flash oQ2 | 1/5 | 586 秒 | 3 个任务因 Metal 看门狗中止：2048 token 的预填充块约 10 秒，超过系统允许的单个命令时长。oMLX 的分块大小是全局设置，没有为它修改 |

## 切换器 App（v3）

- **按模型的推荐配置**（v3.1）：思考开关、推理等级、MTP 深度按模型分别设定，选中哪个模型就填入它的配置。手动改动会按模型记住；「恢复推荐」可回到推荐值。推荐值包括：Qwopus 关闭思考 + medium（本机实测）；原版 Qwen 3.6 A3B 和 Qwen 3.8 开启思考 + medium（官方定位是思考模型）；GPT-OSS / Gemma medium；DeepSeek 云端 high；GPT 云端 xhigh。`runtime.json` 里的 `enable_thinking`/`reasoning_effort` 总是对应当前加载模型的配置。
- **全托管 Agent 模式**：一键把所有客户端切到本地最佳配置（Qwopus，关闭思考），关闭时恢复各客户端原来的配置。
- **客户端卡片**：Codex、OpenCode、Claude Code、Qwen Code 每个客户端可以单独选择——本地（跟随当前模型）、原配置，或它自己的云端模型（Codex 用模型列表里的云端预设，OpenCode 用 `opencode.jsonc` 里所有启用的服务商）。第一次改动前会备份原配置到 `~/Library/Application Support/CodexModelSwitcher/client-backups.json`（权限 0600），"原配置"总是恢复到最初那一份。
- **开机自动加载**：勾选后，开机时加载当前选中的本地模型，崩溃后也会自动恢复；不勾选则开机不加载（对应 `~/.local/state/mtplx-qwen38/disabled` 文件）。
- **命令行**：`CodexModelSwitcher --client <codex|opencode|claude|qwen> <status|targets|local|restore|TARGET> [--home DIR]`；`--api` 启动时直接打开 API 接入窗口。
- **构建**：`./build-app.sh --install`，旧版本会备份到 `backups/`。

## 各客户端接入本地模型

| 客户端 | 接入方式 |
|---|---|
| Codex | 切换器写入 `~/.codex/config.toml`（provider `local-qwen` → `:8002/v1`，Responses 协议） |
| OpenCode | `~/.config/opencode/opencode.jsonc` 中的 `serafina` provider → `:8002/v1`；插件 `plugins/serafina.js` 负责会话身份，并提供 `agentd` 工具 |
| Qwen Code | `qwen --auth-type openai --openai-base-url http://127.0.0.1:8002/v1 --openai-api-key local -m local/qwopus3.6-35b-a3b-coder-4bit` |
| Claude Code | `ANTHROPIC_BASE_URL=http://127.0.0.1:8002 ANTHROPIC_AUTH_TOKEN=local ANTHROPIC_MODEL=local/qwopus3.6-35b-a3b-coder-4bit claude`（网关会把它请求的任何模型名都映射到本地模型） |
| agentd | 直接访问 `runtime.json` 中的 `backend_url`；`agentd run …` 或在 OpenCode 中调用 `agentd` 工具 |

Qwopus 3.6 Coder 是针对**关闭思考**做的微调（见其模型卡）。切换器里的 `enable_thinking` 对以上所有客户端统一生效。
- **agentd** 直接调用后端（读取 `runtime.json` 中的 `backend_url`），每个 Worker 会话使用独立且稳定的 `x-mtplx-session-id`。

## Worker 会话

```
[system（所有会话完全相同）] [tools（完全相同）] [任务卡] (assistant 工具调用, 工具结果)*
```

- `tool_choice` 在整个会话中保持不变（MTPLX 会把它渲染进第一条 system 消息）。默认是 `auto`，前缀复用最稳定；回复里没有工具调用时，会追加一条提醒，连续两次就交接。改成 `required`（`runtime.json` 的 `agentd.tool_choice`）可以强制每一轮都调用工具，但会话缓存几轮后就会失效。
- 工具：`read_file` `list_files` `search` `edit_file` `write_file` `run`，以及控制工具 `finish` `report_blocked` `handoff`。
- assistant 回合原样回传，`reasoning_content` 也包括在内，保证与服务端已提交的 token 一致。

### 保护规则（默认值是工程起点，可调）

| 规则 | 默认 | 触发后的动作 |
|---|---|---|
| 调用和依赖的文件状态完全相同（读文件看内容哈希；搜索/列目录/运行看工作区指纹） | — | 不执行，回复"结果与第 N 轮相同" |
| 重复调用次数 | 3 | 以 `loop` 结束会话，写入账本事实，开新会话 |
| 只输出文字、没有工具调用 | 2 | 第 1 次追加提醒，第 2 次以 `no_action` 结束会话 |
| 同一文件连续修改且没有成功运行过 | 3 | 在工具结果里附加"先运行验证" |
| 会话在任务卡之外的增长超过 25%，且总量达到预算的 70% | 24576 tokens | 追加交接请求，开新会话继续 |
| 每个会话的轮数 | 16 | 同上 |
| 验收失败次数 | 4 | 任务判定为 `failed` |
| 连续没有文件变化的会话数 | 2 | 任务判定为 `failed`（停滞） |
| 每个任务的会话数 | 6 | 任务判定为 `failed` |

### 会话结束后的下一步（orchestrator）

| 会话结果 | 下一步 |
|---|---|
| `done` | 任务完成（验收已通过） |
| `attempts_exhausted` | 失败，账本里有每次验收的输出 |
| `blocked` | 停止，把原因报告给用户 |
| `handoff` / `loop` / `no_action` | 用任务卡 + 交接（模型写的，或从账本生成的）开新会话；连续停滞则判定失败 |
| `error` | 重试一次，之后判定失败 |

每个分支都有明确的下一步，不存在"没有下一步"的状态。

## 使用

```bash
cd ~/Code_Start/Aislos/tools/CodexModelSwitcher
python3 -m agentd run --repo ~/proj --goal "修复 X，使测试通过" --accept "python3 -m pytest -q"
python3 -m agentd status
python3 -m agentd show <run_id>
```

- 默认在 git worktree（`~/.local/share/agentd/worktrees/<run_id>`，分支 `agentd/<run_id>`）中工作，原仓库不动；结束后自行审查并合并。不是 git 仓库时用 `--in-place`。
- 账本位置：`~/.local/share/agentd/ledger.sqlite3`。
- 参数可以在 `runtime.json` 的 `"agentd": {...}` 中覆盖，也可以通过命令行参数覆盖。

## 基准（Phase 0）

```bash
python3 -m agentd.bench.run_bench --runner codex   # Codex 经由网关
python3 -m agentd.bench.run_bench --runner agentd   # 也支持 opencode / qwen / claude
```

`agentd/bench/tasks/` 下有 5 个带验收命令的任务（修 bug、实现功能、跨文件功能、顺着失败追查根因、长上下文重命名），每个都有参考答案用来验证可解。结果写入 `agentd/bench/results/`，服务端指标来自 MTPLX 的 `/v1/mtplx/prefill_history`。

## 客户端实测（2026-10-09，Qwopus 3.6 35B A3B Coder，关闭思考，5 个基准任务）

| 客户端 | 通过 | 总耗时 | 备注 |
|---|---|---|---|
| OpenCode（经网关） | 5/5 | 991 秒 | 最快；主力 |
| Claude Code（经网关 `/v1/messages`） | 5/5 | 1161 秒 | 稳定，固定前缀最大 |
| Codex（经网关，新的检测规则） | 4/5 | 1094 秒 | 旧网关时只有 2/5；剩下那题失败也是"宣布下一步就停"，检测规则已再次扩充 |
| Qwen Code（经网关，新的检测规则） | 5/5 | 2088 秒 | 改规则前只有 2/5 |
| agentd（`tool_choice=auto`） | 抽测 3/3 | debug 72 秒 / fix 95 秒 / multi 252 秒 | 用 `required` 时同样 3 题要 195 / 128 / 576 秒 |

- Qwopus Coder 是为关闭思考而微调的，实测关闭思考后所有客户端都能跑通而且更快，所以全托管模式默认关闭思考。
- "宣布下一步就停"（例如 "Now update X:"、"I need to …"）是本地模型最主要的失败方式。网关会对**最后一句**做检测：以冒号结尾、"Now/Next + 动词"、"I need to / I'll / let me + 动词"，命中就用 `tool_choice=required` 重试一次（追加消息，不改写历史）。
- 不同客户端之间比较缓存，要看每次请求实际新增 prefill 的 token 数，而不是缓存比例。MTPLX 对所有客户端基本都只能复用到第一轮的 prompt；agentd 用 `required` 时，连这部分也会在几轮之后失效。

## 推理服务端的前缀缓存

只追加是必要条件，但还不够。2026-10-09 用 `agentd/bench/cache_probe.py` 实测 MTPLX 2.11 + Qwopus 3.6：同一会话严格只追加，前缀也无法逐轮完整复用。

| 思考历史 | 工具提示模式 | 每轮恢复 |
|---|---|---|
| scoped（默认） | hybrid（默认） | 多数只恢复公共块（约 1.5K），偶尔完整 |
| scoped | native | 第 2–3 轮完整，之后冷启动 |
| preserve | hybrid | 只恢复公共块 |
| preserve | native | 全部冷启动 |

另外排查过的变量：流式/非流式、轮间延迟、清空 bank、tool-call 参数以字符串还是对象回传，都不影响结果。只有 `tool_choice` 有影响：用 `auto` 时能稳定复用第一轮的 prompt；用 `required` 时几轮后就完全冷启动（所以 agentd 默认用 `auto`）。更进一步的逐轮复用要靠服务端修复。

- 复现与验收：`python3 -m agentd.bench.cache_probe --rounds 8 [--mode native] [--verbose]`，健康的状态是每轮都显示 `(full)`。
- 影响：会话越长，每轮的 prefill 越贵（refactor 任务后段每轮 30–80 秒）。agentd 的短会话加交接机制限制了上限。
- 后续（Phase 4）：以 cache_probe 和 run_bench 作为验收标准，评估 MTPLX 升级、oMLX 或其他推理服务。`start-qwen38.sh` 保留了 `MTPLX_PRESERVE_THINKING` 开关（默认 `auto`），方便做实验。

## 部署网关

```bash
./deploy-gateway.sh
```

脚本会先跑网关测试，然后暂停健康检查（`~/.local/state/mtplx-qwen38/disabled`），替换 `~/bin` 下的文件并重启 :8002 代理。直接 kill 代理会让健康检查误判服务挂了，从而重载整个模型。

## 后续（Phase 3+）

- Planner：用 `submit_plan` 工具提交 JSON 格式的 DAG（目标、文件范围、依赖、验收命令），由代码校验。
- 多个 Coder 各用一个 worktree，并行执行工具；推理按 `llm.Lane` 的优先级排队（Reviewer/Planner 优先于 Coder）。
- Reviewer 只读 diff，在验收通过之后、合并之前运行。
- Swift 面板展示账本中的任务 DAG 和会话指标。


## 可选规划与验收模式（2026-10-09）

主模型继续使用原来的 MTPLX 参数、模板、工具与前缀缓存；双模型协作是外层执行器功能，默认关闭。

- 切换器“应用模型”加载当前选择；“任务执行”填写项目、目标和验收命令。
- 打开规划与验收：OSS 20B 提交只读规划，主模型执行，确定性验收命令通过后由 OSS 20B 只读复核；不通过送回修复，上限沿用任务配置。
- 选 Qwen 9B：9B 整理相关信息，规划和复核仍由主模型负责。
- 辅助模型在 LM Studio :1234 加载，主模型在原后端；不同角色独立短上下文。只有切换器拥有的辅助模型标识会被替换，不卸载其他用户模型。
- 网关和 agentd 通过同一个文件锁控制生成，模型可以驻留两个，生成请求一次一路。直接绕过网关/agentd 的外部请求不受这个锁控制。
- 开关也被 OpenCode 插件读取，给本地代码任务提供 agentd 委派提示。需要重启 OpenCode 载入新版插件。这是工具调用引导，不能保证每次模型都选择正确工具。
- CLI：`agentd run --repo /path/to/project --goal "修复问题" --accept "python3 -m unittest discover -s tests" --team`。默认隔离 worktree；UI 明确告知直接改指定项目。
- 此模式不加入关键词拒答过滤。模型拒答、无工具调用、无有效角色提交或验收失败均有有界停止；不把口头承诺当完成。

实测：Qwopus A3B + OSS 20B 同时驻留完成独立加法缺陷修复任务；20B 规划、A3B 读取/编辑/运行、20B 复核，46.6 秒，4 个编码工具回合，验收通过。仅为小型闭环验证，不代表所有项目或拒答行为。
证据：`build/team-smoke-result.json`；自动角色测试覆盖复核驳回后继续执行、只读规划角色不能写文件、无验收命令不得启动。
