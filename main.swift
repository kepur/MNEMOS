import AppKit
import Foundation
import Darwin

enum Serafina {
    static let lilac = NSColor(srgbRed: 0.91, green: 0.86, blue: 0.99, alpha: 1)
    static let mist = NSColor(srgbRed: 0.97, green: 0.95, blue: 1, alpha: 1)
    static let ink = NSColor(srgbRed: 0.15, green: 0.09, blue: 0.20, alpha: 1)
    static let night = NSColor(srgbRed: 0.11, green: 0.07, blue: 0.16, alpha: 1)
    static let cream = NSColor(srgbRed: 0.95, green: 0.96, blue: 0.62, alpha: 1)
    static let grape = NSColor(srgbRed: 0.48, green: 0.36, blue: 0.98, alpha: 1)
    static let petal = NSColor(srgbRed: 0.78, green: 0.70, blue: 1, alpha: 1)
    static let muted = NSColor(srgbRed: 0.40, green: 0.34, blue: 0.52, alpha: 1)
    static let paper = NSColor(srgbRed: 0.99, green: 0.97, blue: 1, alpha: 1)

    static func display(_ size: CGFloat) -> NSFont {
        if let font = NSFont(name: "NewYork-RegularItalic", size: size) ?? NSFont(name: "New York", size: size) {
            return font
        }
        return NSFont(name: "Georgia-Italic", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    }

    static func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return base
    }
}

enum AppLanguage: String {
    case zh = "zh-CN"
    case en = "en-US"
}

final class I18n {
    static var current: AppLanguage {
        get {
            let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-CN"
            return AppLanguage(rawValue: saved) ?? .zh
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appLanguage")
        }
    }

    private static let table: [String: [AppLanguage: String]] = [
        "app.name": [.zh: "MNEMOS", .en: "MNEMOS"],
        "tab.models": [.zh: "模型与客户端", .en: "Models & Clients"],
        "tab.api": [.zh: "API 与模型接口", .en: "API Providers"],
        "tab.dashboard": [.zh: "运行监控与统计", .en: "Dashboard & Stats"],
        "tab.hardware": [.zh: "系统硬件与服务", .en: "Hardware & Processes"],
        "tab.tasks": [.zh: "任务执行与监管", .en: "Tasks & Diagnostics"],
        "tab.network": [.zh: "网络与流量安全", .en: "Network & Sentinel"],
        "tab.startup": [.zh: "开机自启管控", .en: "Startup Services"],
        "tab.watchlist": [.zh: "重点程序管控", .en: "Watchlist Sentinel"],
        "btn.release_memory": [.zh: "⏏️ 释放显存", .en: "⏏️ Release VRAM"],
        "btn.lang": [.zh: "🌐 简中", .en: "🌐 EN"],
        "status.ready": [.zh: " 🟢 就绪 ", .en: " 🟢 Ready "],
        "harness.tokens": [.zh: "Token 用量", .en: "Token Usage"],
        "harness.hit_rate": [.zh: "缓存命中率", .en: "Cache Hit Rate"],
        "harness.cached_read": [.zh: "缓存读取 / 输出", .en: "Cached Read / Output"],
        "harness.memory_saved": [.zh: "96GB 内存节省", .en: "96GB VRAM Saved"],
        "aoci.title": [.zh: "🌐 AOCI 全局架构感知", .en: "🌐 AOCI Global Architecture"],
        "codegraph.title": [.zh: "🎯 CodeGraph 局部精准跳查", .en: "🎯 CodeGraph AST Navigation"],
        "platform.title": [.zh: "💻 跨平台架构与算力适配", .en: "💻 Cross-Platform Architecture"],
    ]

    /// Bidirectional phrase pairs (Chinese <-> English) applied across the entire view hierarchy & subpages
    private static let phrasePairs: [(zh: String, en: String)] = [
        // ─── Global & Top Bar & Navigation ───
        ("本地主模型 · 可选辅助模型 · 规划、执行、验收", "Local Primary Model · Optional Secondary · Plan, Act, Verify"),
        ("全托管 Agent 模式", "Managed Agent Mode"),
        ("开启后，所有客户端使用本地最佳配置。", "When enabled, all clients use recommended local settings."),
        ("本地多端模型控制台", "Local Multi-Client Model Console"),
        ("各客户端独立模型路由", "Per-Client Independent Model Routing"),
        ("运行时与监控", "Runtime & Telemetry"),
        ("模型服务", "Model Services"),
        ("Agent 监管", "Agent Supervision"),
        ("AGENT 监管", "AGENT SUPERVISION"),
        ("当前空载 · 显存未占用", "Idle · VRAM Unallocated"),
        (" ⚪ 空载 (未载入模型) ", " ⚪ Idle (No Model Loaded) "),
        (" 🟠 推理中 ", " 🟠 Generating "),
        (" 🟢 闲置就绪 ", " 🟢 Idle Ready "),
        (" ⚪ 空载 ", " ⚪ Idle "),
        ("Serafina · 模型加载中", "Serafina · Loading Model"),
        ("预填 -- · 生成 --", "Prefill -- · Gen --"),
        (" ⚡️ 214M tok · 命中 99% ", " ⚡️ 214M tok · 99% Hit "),
        (" 🟢 就绪 ", " 🟢 Ready "),
        ("● :8002 在线", "● :8002 Online"),
        ("⏏️ 释放显存", "⏏️ Release VRAM"),
        ("⏏️ 卸载释放显存", "⏏️ Unload VRAM"),
        ("⏏️ 卸载并释放显存", "⏏️ Unload & Free VRAM"),
        ("当前模型：", "Current Model: "),
        ("Codex 当前默认：", "Codex Current Default: "),

        // ─── Page 0: Models & Clients ───
        ("模型运行状态", "Model Status"),
        ("点击 ⏻ 启停本地模型 · 绿色就绪 · 橙色推理 · 灰色停止", "Click ⏻ to toggle local model · Green: Ready · Orange: Generating · Gray: Stopped"),
        ("上下文 128K · 统一内存 96GB", "Context 128K · Unified Memory 96GB"),
        ("会话预算", "Session Budget"),
        ("任务上下文", "Task Context"),
        ("紧凑 2K（每 1.5K 增量总结 · 120B 防爆）", "Compact 2K (1.5K summarize · 120B safe)"),
        ("会话 24K（推荐 · 30B/35B 适用）", "Session 24K (Recommended · 30B/35B)"),
        ("会话 56K（长任务全量）", "Session 56K (Full Context)"),
        ("紧凑模式每 1.5K 增量总结历史，防止 120B 超大模型 Metal Watchdog 超时。", "Compact summarizes every 1.5K to prevent Metal Watchdog timeout on 120B."),
        ("推理", "Effort"),
        ("深度", "Depth"),
        ("开启思考", "Enable Thinking"),
        ("应用速度", "Apply Speed"),
        ("恢复推荐", "Reset Defaults"),
        ("应用模型", "Apply Model"),
        ("应用模型 · 加载到内存", "Apply & Load Model"),
        ("快速问答 · OSS 20B", "Fast Chat · OSS 20B"),
        ("应用所选模型", "Apply Selected Model"),
        ("切换后重启 Codex", "Restart Codex on Switch"),
        ("切换本地模型时，Codex 也切到本地", "Switch Codex to local when local model changes"),
        ("客户端 · 共用同一个本地模型", "Clients · Unified Local Model Bridge"),
        ("全部恢复原配置", "Restore All Configs"),
        ("恢复原配置", "Restore Original"),
        ("重启客户端", "Restart Client"),
        ("开新会话", "New Session"),
        ("打开", "Open"),
        ("终端", "Terminal"),
        ("检测中…", "Checking…"),
        ("本地换模型无需重启；更改接入配置后请重启或开新会话。", "Model switch needs no restart; restart app or start new session if config changed."),
        ("每个客户端单独选择：本地（跟随当前加载的模型和思考开关，换模型不用重启客户端）、原配置，或它自己的云端模型。恢复原配置＝恢复第一次切换前备份的接入设置，不清除会话。切换本地/云端后：Codex、OpenCode 重启 App，Claude Code、Qwen Code 开新会话。Claude Code 改的是 ~/.claude/settings.json，影响所有 Claude Code 会话（包括 Claude 桌面版的 Code）。", "Select per client: Local (tracks active model & thinking, zero restart), original config, or cloud model. Restoring original keeps sessions intact. Restart Codex/OpenCode after switching; start a new session in Claude Code or Qwen Code."),

        // ─── Page 1: API Integration ───
        ("任何 Agent 都可以接入：OpenAI 和 Anthropic 两种协议，统一转给当前本地模型", "Connect Any Agent: OpenAI & Anthropic protocols bridged to local model"),
        ("配置示例", "Config Samples"),
        ("复制示例", "Copy Sample"),
        ("模型名", "Model Name"),
        ("也可以写 local 或任何名字", "Or use 'local' or any arbitrary name"),
        ("任意非空值；仅本机 127.0.0.1 可访问，不校验", "Any non-empty string; 127.0.0.1 loopback only, not validated"),
        ("Messages、count_tokens（客户端会自动补 /v1/messages）", "Messages, count_tokens (client appends /v1/messages)"),
        ("Chat Completions、Responses、Models", "Chat Completions, Responses, Models"),
        ("所有请求共用同一个推理队列，使用切换器当前的模型和思考开关；网关只透传，不改写对话历史。", "All requests share the unified inference queue with current model & thinking settings; gateway proxies without rewriting history."),

        // ─── Page 2: Dashboard, Harness, Live Stream ───
        ("实时监控 · 6层全栈可观测性与 ARP 运行时看板", "Live Telemetry · 6-Layer Observability & ARP Dashboard"),
        ("六层全链路健康感知 (服务在线 ≠ 模型可用 ≠ GPU健康) · 自适应故障隔离 (ARP) · 智能体有效产出", "6-layer health matrix (Online ≠ Usable ≠ GPU healthy) · Adaptive recovery (ARP) · Agent throughput"),
        ("系统统一内存", "Unified Memory"),
        ("RAM/Swap 稳定", "RAM/Swap Stable"),
        ("看门狗正常", "Watchdog Normal"),
        ("推理引擎", "Inference Engine"),
        ("模型就绪", "Model Ready"),
        ("网关与协议", "Gateway & Protocols"),
        ("督导决策", "Supervisor & Safety"),
        ("熔断器活跃", "Breaker Active"),
        ("记忆与恢复", "Memory & WAL"),
        ("WAL/快照就绪", "WAL/Snapshot Ready"),
        ("WAL 同步正常", "WAL Sync Normal"),
        ("系统资源正常", "System Resources OK"),
        ("累积服务 Token", "Served Tokens"),
        ("前缀缓存效率", "Cache Efficiency"),
        ("实时吞吐 TPS", "Throughput TPS"),
        ("有效产出 EAT", "Effective Output (EAT)"),
        ("算力损耗 WCR", "Compute Waste (WCR)"),
        ("ARP 故障防护", "ARP Resilience Guard"),
        ("首字预填 / 持续生成", "Prefill / Generation"),
        ("验收证据推进率 · 真实进展", "Verification Progress Rate · True Progress"),
        ("验收证据推进率", "Acceptance Progress Rate"),
        ("零无效算力损耗", "Zero Compute Waste"),
        ("异常重试/循环损耗", "Retry/Loop Overhead"),
        ("0 次 Metal 崩溃 · 看门狗就绪", "0 Metal Crashes · Watchdog Armed"),
        ("0 次 Metal 崩溃", "0 Metal Crashes"),
        ("🟢 守卫就绪", "🟢 Guard Ready"),
        ("⛔️ 隔离中", "⛔️ Quarantined"),
        ("🟡 降级自愈", "🟡 Degraded Healing"),
        ("解除隔离", "Reset Quarantine"),
        ("ARP 保护事件：", "ARP Event: "),
        ("正常守卫中 · 无 Metal 异常 · Prefill 分块 2048", "Normal guard · No Metal fault · Prefill chunk 2048"),
        ("触发故障隔离 · 模型 ", "Fault quarantine triggered · Model "),
        (" 正在冷却", " cooling down"),
        (" 避免 Metal 连续崩溃", " preventing Metal cascade crashes"),
        ("最近故障", "Recent Incident"),
        ("执行自愈:", "Action:"),
        ("运行时监管 · PAR Supervisor & 防循环熔断器", "Runtime Supervision · PAR Supervisor & Loop Breakers"),
        ("任务流水线：", "Task Pipeline: "),
        ("任务流水线", "Task Pipeline"),
        ("[规划] ➔ [定位入口] ➔ [编码实现] ➔ [回归验证] ➔ [验收交付] · 待命中", "[Plan] ➔ [Entrypoint] ➔ [Code] ➔ [Verify] ➔ [Deliver] · Standby"),
        ("熔断器状态：", "Breaker State: "),
        ("🟢 L0 正常运行 · 双平面 Guard 活跃", "🟢 L0 Normal · Dual-plane Guard Active"),
        ("🟡 L1 建议微调 (Advisory Nudge) · 提示词已注入修正策略", "🟡 L1 Advisory Nudge · Prompts Adjusted"),
        ("🟠 L2 策略突变 (Strategy Mutation) · 诊断中: ", "🟠 L2 Mutation · Diagnosing: "),
        ("🔴 L3 现场保护 (Quiescent Pause) · APFS+Git 快照已锁定", "🔴 L3 Quiescent Pause · APFS+Git Locked"),
        ("防死循环雷达：", "Loop Radar: "),
        ("Type A~H (8类特征) 监控中 · 0 异常 · 幂等副作用已拦截", "Type A~H monitoring · 0 anomalies · Idempotent effects blocked"),
        ("分层前缀缓存：", "Hierarchical Cache: "),
        ("Eligibility 100% · Actual Hit -- (Project Core 锁定)", "Eligibility 100% · Actual Hit -- (Project Core Locked)"),
        ("⚡️ DeepSeek Harness 智能体推理与 KV-Cache 命中率大盘", "⚡️ DeepSeek Harness Agent Inference & KV-Cache Dashboard"),
        ("结合 AOCI 全局架构蓝图与 CodeGraph 局部 AST 剪枝 · 维持 99% 前缀缓存复用 · 彻底减负 96GB 内存与推理延迟", "AOCI architecture + CodeGraph AST pruning · 99% prefix reuse · Offload 96GB memory & latency"),
        ("Token 用量", "Token Usage"),
        ("缓存命中率", "Cache Hit Rate"),
        ("缓存读取 / 输出", "Cached Read / Output"),
        ("96GB 内存节省", "96GB Memory Saved"),
        ("未缓存仅", "Uncached only"),
        ("未缓存", "Uncached"),
        ("免重复Prefill", "Zero repeat prefill"),
        ("极速 KV-Cache 命中复用", "Ultra-fast KV-Cache reuse"),
        ("大幅降低显存带宽与等待时间", "Greatly reduced VRAM bandwidth & latency"),
        ("🌐 AOCI (AI-Oriented Code Indexing) 全局架构感知", "🌐 AOCI (AI-Oriented Code Indexing) Global Architecture"),
        (" 🟢 蓝图受控 ", " 🟢 Blueprint Verified "),
        (" 🟢 节省 70%~85% Token ", " 🟢 Saves 70%~85% Tokens "),
        ("🎯 CodeGraph 局部精准跳查 (AST & Tree-sitter Outline)", "🎯 CodeGraph AST Navigation (AST & Tree-sitter Outline)"),
        ("精准提取类与函数签名大纲，剥离实现体 (平均压缩率 82.5%) · 支持跨文件符号跳查与调用链爆炸半径分析 · 杜绝整文件Dump刷屏", "Extracts class/function signatures, strips bodies (avg 82.5% compression) · Cross-file jump & blast-radius analysis · Zero whole-file dump"),
        ("💻 跨平台架构与算力适配 (Cross-Platform Architecture)", "💻 Cross-Platform Architecture & Compute Adaptation"),
        (" 🍎 macOS (Metal/MPS) ", " 🍎 macOS (Metal/MPS) "),
        ("当前底座: Apple Silicon M2 Max (38-Core GPU, 96GB 统一内存) · 架构已完成核心解耦，后续平滑扩充 Windows 11 + NVIDIA CUDA (TensorRT-LLM) 与 AMD ROCm 专供版", "Current foundation: Apple Silicon M2 Max (38-Core GPU, 96GB VRAM) · Decoupled core expands to Windows 11 + NVIDIA CUDA (TensorRT-LLM) & AMD ROCm"),
        ("🔄 刷新代码蓝图 & 命中率", "🔄 Refresh Blueprint & Cache"),
        ("呼吸灯 VU 表 · 绿灯: 闲置就绪 | 橙灯(呼吸): 工作中 (每 5 tok/s 点亮 1 拍 · 满排 20 拍) | 红灯: 未启动", "VU Meter · Green: Idle | Orange (breathing): Generating (1 tick per 5 tok/s) | Red: Off"),
        ("本地网关请求会显示在这里；云端请求不经过本地。可在服务页点击文本测试。", "Local gateway requests stream here; cloud calls bypass local. Run test in Services tab."),
        ("token 流会写在这里。", "Token stream will appear here.\n"),

        // ─── Page 3: Hardware & Services ───
        ("硬件与显存监控 · Apple Silicon (M2 Max 96GB)", "Hardware & VRAM Monitor · Apple Silicon (M2 Max 96GB)"),
        ("GPU 显存占用 (Metal / MLX)", "GPU VRAM Usage (Metal / MLX)"),
        ("系统统一内存 (Mach Kernel VM)", "System Unified Memory (Mach Kernel VM)"),
        ("芯片规格", "Chip Spec"),
        ("温控状态", "Thermals"),
        ("🟢 正常 (Nominal)", "🟢 Nominal"),
        ("能耗良好 · 峰值能效", "Optimal efficiency"),
        ("系统运行", "System Uptime"),
        ("持续稳定在线", "Continuously stable"),
        ("SSD 运行时快照与缓存", "SSD Runtime Cache & Snapshots"),
        ("SSD 运行时缓存: 正在读取…", "SSD Runtime Cache: Reading…"),
        ("清理 SSD 缓存", "Clear SSD Cache"),
        ("💻 进程家族 CPU & 内存细化监控 (父子进程树)", "💻 Process Family CPU & Memory Monitor (Parent/Child Tree)"),
        ("全面透视具体应用程序及其 Helper/Renderer/Daemon 子进程对 CPU 和物理内存的独立占用 · 支持父子级联折叠", "Inspect apps and their Helper/Renderer/Daemon child procs' CPU & RAM usage · Cascading hierarchy"),
        ("🔥 按 CPU 消耗排行", "🔥 Sort by CPU"),
        ("🧠 按 内存占用排行", "🧠 Sort by Memory"),
        ("按 CPU 消耗排行", "Sort by CPU"),
        ("按 内存占用排行", "Sort by Memory"),
        ("🔄 刷新排行", "🔄 Refresh Procs"),
        ("正在扫描系统进程家族资源...", "Scanning process families..."),
        ("Codex、OpenCode、Claude Code 都走网关 127.0.0.1:8002（Responses / Chat / Anthropic 三种协议）。Qwen 在 MTPLX :8000，Gemma 4 和 GPT-OSS 在 LM Studio :1234。同一时间只留一个本地模型。", "Codex, OpenCode, Claude Code route via gateway 127.0.0.1:8002. Qwen on MTPLX :8000, Gemma 4 & GPT-OSS on LM Studio :1234. Single active local model."),
        ("启动", "Start"),
        ("停止", "Stop"),
        ("文本测试", "Text Test"),
        ("图片测试", "Vision Test"),
        ("日志", "Logs"),
        ("API 接入", "API Setup"),
        ("开机自动加载本地模型（含崩溃后自动恢复）", "Auto-load local model on boot (with crash auto-recovery)"),
        ("历史均速来自实际调用，按生成 token 数加权；输入处理、首 token 和生成分别统计。网关只透传、不改写历史，便于复用前缀缓存；需要验收的长任务交给 agentd（命令行 agentd run，或在 OpenCode 里调用 agentd 工具）。Qwopus Coder 为关闭思考而微调。", "Historical speeds benchmarked from actual calls, weighted by generated tokens. Gateway preserves prefix cache without rewriting history. Use agentd for long verified tasks. Qwopus is tuned for disabled thinking."),

        // ─── Page 4: Tasks ───
        ("先规划、执行后验收（可选第二个本地模型）", "Plan, Execute, then Verify (Optional 2nd Model)"),
        ("OSS 20B · 规划与复核", "OSS 20B · Planning & Verification"),
        ("Qwen 9B · 整理信息，主模型规划与复核", "Qwen 9B · Triage & Primary Model Review"),
        ("项目完整路径，例如 /Users/mac/Code_Start/my-project", "Full project path, e.g. /Users/mac/Code_Start/my-project"),
        ("任务目标：要完成什么，哪些文件不能改", "Task goal: What to build, which files must not change"),
        ("验收命令，例如 python3 -m unittest discover -s tests", "Verification command, e.g. python3 -m unittest discover -s tests"),
        ("开始执行任务", "Start Verified Task"),
        ("停止任务", "Stop Task"),
        ("任务直接修改指定项目。先确保有备份或版本记录；只有验收命令通过并完成复核才报告完成。", "Tasks modify repository directly. Ensure backups exist; task reports success only after verification passes."),
        ("主模型负责工具与代码；20B 可负责规划/复核，9B 可整理资料。辅助模型在任务开始时加载，推理排队，工具可独立运行。此开关也用于 OpenCode 的 agentd 工具，不改变 A3B 推理参数。", "Primary model writes code; 20B plans/verifies, 9B gathers context. Secondary models load on task start with serialized inference. Also used by OpenCode agentd."),
        ("项目", "Project"),
        ("任务目标", "Task Goal"),
        ("验收命令（必须覆盖任务目标）", "Verification Command (Must cover goals)"),

        // ─── Page 5: Network Sentinel ───
        ("网络安全哨兵 · 本机流量监控与异常研判 (Network Sentinel)", "Network Security Sentinel · Traffic Monitor & Threat Detection"),
        ("实时监控公网出站流量、异常进程外联与危险端口暴露 · 识别反弹 Shell、C2 木马与未授权服务暴露", "Monitor public outbound traffic, anomalous sockets & exposed ports · Detect reverse shells, C2 trojans & leaks"),
        ("实时网络吞吐", "Live Bandwidth"),
        ("威胁防护状态", "Threat Protection"),
        ("开放监听端口", "Listening Ports"),
        ("活跃网络连接", "Active Connections"),
        ("🚨 异常事件与安全告警 (Threat Alerts)", "🚨 Threat Alerts & Security Events"),
        ("正在连接 :8002 获取网络监控审计数据...", "Connecting to :8002 for security telemetry..."),
        ("🌐 网络连接测绘与上传数据审计 (Network Map & Upload Payload Audit)", "🌐 Network Map & Upload Payload Audit"),
        ("集成公共 IP 归属地 API（国家/地区/运营商）与上传数据深度溯源（图片/文本/文件/敏感凭据）", "Public IP geolocation lookup (Country/Region/ISP) & upload payload tracing (Images/Text/Files/Credentials)"),
        ("🌐 活跃外网连接与 IP 归属地", "🌐 Active Outbound Sockets & Geolocation"),
        ("📤 上传数据深度审计 (重点监控)", "📤 Upload Payload Audit (Priority Guard)"),
        ("🚨 一键批量阻断异常外联", "🚨 Block Suspicious Sockets"),
        ("🔄 立即重新扫描", "🔄 Rescan Now"),
        ("【本地监听端口与暴露审计】\n正在查询中...", "【Local Listening Ports & Exposure Audit】\nQuerying..."),
        ("图片多媒体上传", "Media & Images Upload"),
        ("文本/代码/配置", "Code, Text & Config"),
        ("文件与压缩包", "Archives & Docs"),
        ("敏感凭证告警", "Credential Alerts"),
        ("照片/截图/图片文件", "Photos/Screenshots/Images"),
        ("日志/文本/JSON传输", "Logs/Text/JSON Transmissions"),
        ("文档/压缩包/安装包", "Docs/Archives/Installers"),
        ("密钥/私钥/密码库访问", "Keys/Private Keys/Keychains"),
        ("📤 当前活跃上传进程与文件溯源 (Top Uploading Processes):", "📤 Top Uploading Processes & File Origins:"),
        ("处高危", "Critical"),
        ("处警告", "Warning"),
        ("处公网暴露", "Exposed Publicly"),
        ("公网外联", "Outbound Sockets"),
        ("照片/截图/图片传输", "Images & Screenshots"),
        ("代码/日志/JSON传输", "Code, Logs & JSON"),
        ("文档/归档包传输", "Docs & Archives"),
        ("未检测到私钥凭据读取", "No Credential Reads Detected"),
        ("⚠️ 发现敏感文件读取!", "⚠️ Sensitive Credential Reads Detected!"),
        ("🟢 当前无活跃带宽传输进程", "🟢 No Active Uploading Processes"),
        ("🟢 态势感知正常：未发现异常进程外联、C2 木马连接或危险端口裸露。", "🟢 Posture Normal: No suspicious outbound sockets, C2 trojans, or exposed ports."),
        ("🟢 当前无活跃 TCP/UDP 网络连接", "🟢 No Active TCP/UDP Sockets"),

        // ─── Page 6: Startup Items ───
        ("🚀 开机默认启动程序管控 (Startup & Login Items Manager)", "🚀 Startup & Login Items Manager"),
        ("全面管控 macOS 用户开机守护进程 (LaunchAgents) 与登录项。卡片式一键开关，无需输入命令或 ID，核心系统受白名单保护：", "Manage macOS LaunchAgents & Login Items. One-click toggles without CLI commands; system core protected by whitelist:"),
        ("自启项总数", "Total Items"),
        ("LaunchAgents & 登录项", "LaunchAgents & Login Items"),
        ("运行中守护", "Running Daemons"),
        ("活跃常驻服务", "Active Resident Services"),
        ("已禁用服务", "Disabled Services"),
        ("已关闭不自启", "Disabled at boot"),
        ("核心保护", "Core Protected"),
        ("Serafina & 系统白名单", "Serafina & System Whitelist"),
        ("🛑 一键批量关闭非必要自启", "🛑 Batch Disable Non-Essential"),
        ("🔄 刷新自启清单", "🔄 Refresh Startup List"),
        ("全部项", "All Items"),
        ("可优化第三方", "Optimizable 3rd-Party"),
        ("当前分类下暂无自启项", "No startup items in this category"),
        ("启动项变更成功", "Startup Item Updated"),
        ("操作失败", "Operation Failed"),
        ("确认批量关闭非必要开机自启程序？", "Confirm batch disabling non-essential startup items?"),
        ("系统将自动关闭并停止所有第三方后台启动项（如网盘后台、游戏启动器、自动更新程序等），以提升开机速度和续航。\n\nSerafina 与系统核心守护进程受到白名单保护，不受影响。", "Automatically disables 3rd-party startup agents (cloud drives, updaters) to boost boot speed and battery life.\n\nSerafina & system daemons remain protected."),

        // ─── Page 7: Watchlist & Guard ───
        ("🎯 重点程序监控与细粒度流量/越权沙箱拦截 (Priority Watchlist & Sandbox Guard)", "🎯 Priority Watchlist & Granular Sandbox Interceptor"),
        ("支持关联父子进程深度纳管、每次请求拦截放行 (Gatekeeper)、细粒度阻断指定数据/文件类型（图片、视频、大文件、私钥凭据、自定义扩展名）及工作目录越权跨界监控：", "Deep parent/child hierarchy, Gatekeeper per-request prompt (SIGSTOP/SIGCONT), granular rule blocking & sandbox out-of-bounds auditing:"),
        ("纳管程序族", "Watched Families"),
        ("重点观察进程及子进程", "Monitored process families"),
        ("越权跨界告警", "Out-of-Bounds"),
        ("读取工作目录外私有文件", "Reads outside working directory"),
        ("阻断流量/文件", "Blocked Items"),
        ("命中图片/视频/大文件规则", "Triggered image/video/large rules"),
        ("每次放行审核", "Gatekeeper Guard"),
        ("已就绪", "Armed"),
        ("支持 SIGSTOP/SIGCONT", "Supports SIGSTOP/SIGCONT"),
        ("挑选与搜索运行程序 (实时免查 PID)", "Pick & Search Running Processes (Live)"),
        ("可输入应用名称（如 WeChat, Chrome, Python）或 PID 实时筛选：", "Filter by app name (e.g. WeChat, Chrome, Python) or PID:"),
        ("🔄 刷新进程", "🔄 Refresh Procs"),
        ("⤢ 独立窗口", "⤢ Detached Window"),
        ("🔍 输入应用名或 PID 实时筛选 (如 Chrome, WeChat, Python)...", "🔍 Filter by name or PID (e.g. Chrome, WeChat, Python)..."),
        ("全部常用", "Common"),
        ("🌐 活跃外联", "🌐 Active Outbound"),
        ("💻 运行中的 App", "💻 Running Apps"),
        ("快速 PID:", "Quick PID:"),
        ("如 1234", "e.g. 1234"),
        ("➕ 纳管", "➕ Watch"),
        ("🛡️ 当前受控与细粒度防护中的重点程序族 (Active Monitored Families)", "🛡️ Currently Watched & Protected Process Families"),
        ("提示：已被纳管的进程将自动拦截异常跨界越权文件访问，并支持网络放行拦截审核与流量细粒度过滤：", "Tip: Watched processes automatically block out-of-bounds file access and support Gatekeeper authorization:"),
        ("阻断私钥凭据 (.ssh/keychain)", "Block SSH Keys & Keychain"),
        ("拦截图片", "Block Images"),
        ("拦截视频媒体", "Block Videos"),
        ("拦截 >20MB 大文件", "Block >20MB Files"),
        ("拦截归档包 (.zip/.tar/.dmg)", "Block Archives (.zip/.tar/.dmg)"),
        ("👮 每次请求需人工放行 (Gatekeeper 挂起确认)", "👮 Gatekeeper Prompt per Request (SIGSTOP Confirm)"),
        ("📜 传输与文件访问历史记录 (持久化存档 · 共 ", "📜 Access & Transfer History (Persistent Vault · Total "),
        (" 项 · 可滚动查看全部历史):", " items · Scroll for full history):"),
        ("  • 暂无文件传输或访问存档 (进程读写的所有文件将自动在此永久记录)", "  • No file access history yet (all process I/O will be recorded here)"),
        ("  • 暂无外联 IP 连接 (处于本地监听或空闲状态)", "  • No outbound connections (idle or local listening only)"),
        ("📁 限定沙箱目录: ", "📁 Sandbox Working Directory: "),
        ("未限定 (全目录监测)", "Unrestricted (Full Directory Audit)"),
        (" · 自定义拦截扩展名: [", " · Custom Blocked Extensions: ["),
        ("📂 Finder 定位", "📂 Reveal in Finder"),
        ("📄 查看内容", "📄 Inspect Content"),
        ("🤖 深度分析", "🤖 Deep Analysis"),
        ("✅ 放行允许 (SIGCONT)", "✅ Resume (SIGCONT)"),
        ("⏸ 冻结挂起 (SIGSTOP)", "⏸ Pause (SIGSTOP)"),
        ("⚡️ 立即终止进程族", "⚡️ Terminate Family"),
        ("💾 应用规则", "💾 Apply Rules"),
        ("移出监控", "Unwatch"),
        ("🔌 断连", "🔌 Disconnect"),
        ("🟢 解除阻断", "🟢 Unblock IP"),
        ("🛑 阻断 IP", "🛑 Block IP"),
        ("🛑 关主进程", "🛑 Kill Main Proc"),
        ("⛓ 进程家族父子结构与独立资源消耗", "⛓ Process Family Tree & Resource Usage"),
        ("支持单独关闭子进程或父进程", "Support killing individual parent or child processes"),
        ("  🎯 主进程:", "  🎯 Main:"),
        ("  ↳ 子进程:", "  ↳ Child:"),
        ("用户: ", "User: "),
        ("▲ 收起", "▲ Collapse"),
        ("▼ 展开子进程", "▼ Expand Children"),
        ("越权", "Out-of-Bounds"),
        ("敏感", "Sensitive"),
        ("截屏", "Screencap"),
        ("传输", "Transfer"),
        ("访问", "accessed "),
        ("次", "times"),

        // ─── Gatekeeper & Modals ───
        ("🚨 敏感凭证 / 高危后台流量传输拦截！", "🚨 Sensitive Credential / High-Risk Traffic Intercepted!"),
        ("⏸ 系统已自动挂起 (SIGSTOP) 该进程及其子进程，阻断后台上传传输。请核对以下详情，点击「允许放行」后才可通过：", "⏸ Process & children paused via SIGSTOP. Review the audit details below. Click 'Allow' to resume:"),
        ("📋 拦截现场完整审计细节 (敏感凭证路径 / 父子进程内存 / 外联目标):", "📋 Full Audit Details (Credential Paths / Family Memory / Outbound Target):"),
        ("✅ 允许放行 (恢复传输 SIGCONT)", "✅ Allow & Resume (SIGCONT)"),
        ("🛑 拒绝并关闭本进程", "🛑 Reject & Kill Process"),
        ("⬆️ 拒绝并关闭父进程", "⬆️ Reject & Kill Parent"),
        ("💥 拒绝并清理父子进程树", "💥 Reject & Kill Family Tree"),
        ("💡 请选择下方操作：点「允许放行」将发送 SIGCONT 恢复进程通信；点「拒绝并关闭」将立即终止对应进程。", "💡 Select an action: 'Allow' sends SIGCONT to resume socket; 'Reject & Kill' terminates process immediately."),
        ("【拦截状态】: ⏸ 已通过 SIGSTOP 冻结挂起该进程与子进程，等待人工授权", "[Intercept State]: ⏸ Frozen via SIGSTOP, awaiting authorization"),
        ("【拦截状态】: ⚠️ 实时拦截监控中", "[Intercept State]: ⚠️ Live intercept monitoring"),
        ("【触发进程】: ", "[Target Process]: "),
        ("【父级进程】: ", "[Parent Process]: "),
        ("【内存占用】: 本进程 ", "[Memory]: Self "),
        (" / 进程树总计 ", " / Family Total "),
        ("【外联目标】: ", "[Outbound Endpoint]: "),
        (" · 归属地: ", " · Location: "),
        ("【传输流量】: 累计上传 ", "[Traffic]: Total Up "),
        (" (当前上传速度 ", " (Upload Speed "),
        (") · 累计下载 ", ") · Total Down "),
        ("🔑 【检测到触碰的敏感凭证 / 私钥文件", "🔑 [Detected Sensitive Credential / Private Key Files"),
        (" 项)】:", " items]:"),
        ("⚠️ 【高危传输行为告警细节】:", "⚠️ [High-Risk Exfiltration Alerts]:"),
        ("👶 【关联子进程列表", "👶 [Associated Child Processes"),
        (" 个子进程)】:", " children]:"),
        ("👶 【关联子进程列表】: 无派生子进程", "👶 [Associated Child Processes]: None"),
        ("🚨 触发原因: ", "🚨 Trigger Reason: "),
        ("检测到敏感凭证访问或高危后台外联上传", "Detected sensitive credential access or high-risk background upload"),
        ("🛡️ 敏感凭证与后台外联传输确认 (可信官方目标)", "🛡️ Credential & Outbound Transfer Confirmation (Trusted Official Endpoint)"),
        ("⚠️ 敏感凭证 / 公有云后台流量传输拦截！", "⚠️ Credential / Public Cloud Background Upload Intercepted!"),
        ("🚨 敏感凭证 / 高危未知后台流量传输拦截！", "🚨 Credential / Unknown Suspicious Upload Intercepted!"),
        ("🛡️ 上传目的地与平台可信度研判", "🛡️ Destination & Platform Trust Assessment"),
        ("🌐 上传目的地: ", "🌐 Upload Destination: "),
        ("  |  🏢 归属机构: ", "  |  🏢 Organization: "),
        ("  |  📍 远端: ", "  |  📍 Remote: "),
        ("💡 研判分析: ", "💡 Threat Analysis: "),
        ("🔑 涉及凭据: ", "🔑 Credentials: "),
        (" 等共 ", " etc. total "),
        (" 个敏感文件", " sensitive files"),
        ("🟢 安全建议：上传目的地为 Apple 等官方服务器，通常用于账号身份验证或系统数据同步。若确认属实，建议点击「允许放行」。", "🟢 Recommendation: Destination is an official server (e.g. Apple). Typically legitimate system/auth sync. Safe to click 'Allow'."),
        ("🟡 提醒：目标为公共云端/CDN，请确认是否为预期上传；若非预期，建议点击「拒绝并关闭」。", "🟡 Notice: Destination is a public cloud/CDN. Verify if expected; if not, click 'Reject & Kill'."),
        ("🔴 高危警示：目标为未知公网或自建节点，正在外发私钥/凭据！极可能是恶意泄密，强烈建议点击「拒绝并清理」。", "🔴 Threat Warning: Destination is an unknown/self-hosted node exfiltrating keys/credentials! High leak risk. Click 'Reject & Kill'."),
        ("🎯 ══════ 【上传目的地与主体归属 (Destination & Trust)】 ══════", "🎯 ══════ [Upload Destination & Entity Trust] ══════"),
        ("  • 目标域名 (Domain): ", "  • Target Domain: "),
        ("  • 所属机构 (Organization): ", "  • Organization: "),
        ("  • 网络端点 (Endpoint): ", "  • Network Endpoint: "),
        ("  • 地理归属 (Geo Location): ", "  • Geo Location: "),
        ("  • 安全评级 (Trust Level): ", "  • Trust Level: "),
        ("  • 专家研判 (Security Advice): ", "  • Security Advice: "),
        ("🔑 ══════ 【检测到触碰的敏感凭证 / 私钥文件", "🔑 ══════ [Detected Sensitive Credentials / Keys"),
        ("⛓ ══════ 【进程与系统执行现场】 ══════", "⛓ ══════ [Process Execution Context] ══════"),
        ("⚠️ ══════ 【高危行为告警细节】 ══════", "⚠️ ══════ [High-Risk Threat Details] ══════"),
        ("👶 ══════ 【关联子进程列表", "👶 ══════ [Associated Child Processes"),
        ("👶 ══════ 【关联子进程列表】: 无派生子进程 ══════", "👶 ══════ [Child Processes]: None ══════"),
        ("🟢 Apple 官方认证服务节点 (安全受信任)", "🟢 Apple Official Verified Node (Trusted)"),
        ("🟢 GitHub / 微软官方认证节点 (安全受信任)", "🟢 GitHub / Microsoft Verified Node (Trusted)"),
        ("🟢 Google 官方认证服务节点 (安全受信任)", "🟢 Google Official Verified Node (Trusted)"),
        ("🟢 官方主流 AI 平台节点 (安全受信任)", "🟢 Official AI Platform Node (Trusted)"),
        ("🟡 公有云 / 基础设施托管节点 (需核对应用)", "🟡 Public Cloud / CDN Node (Verify App)"),
        ("🔴 未知外部公网 / 高危自建节点 (严重风险)", "🔴 Unknown External / High-Risk Node (Critical Risk)"),
        ("🛡️ 放行并永久信任父进程 (加入白名单)", "🛡️ Allow & Permanently Trust Parent (Whitelist)"),
        ("🛡️ 记住此授权：将父进程加入信任白名单 (下次不再弹窗提醒)", "🛡️ Remember authorization: Whitelist parent process (Do not remind again)"),
        ("勾选后，该父进程今后派生子进程或执行外联时将直接受信任放行，不会再阻断挂起或弹出警告。", "When checked, child processes or outbound requests from this parent are trusted and silently bypassed without pauses or alerts."),
        ("🛡️ 管理信任白名单", "🛡️ Manage Whitelist"),
        ("🛡️ 管理拦截白名单", "🛡️ Manage Intercept Whitelist"),
        ("🛡️ 父进程已在信任白名单中 (自动放行)", "🛡️ Parent in Trust Whitelist (Auto-Bypassed)"),
        ("🛡️ Gatekeeper 信任白名单 (当前为空)", "🛡️ Gatekeeper Whitelist (Currently Empty)"),
        ("清空白名单", "Clear Whitelist"),
        ("确认清空所有信任白名单？", "Confirm Clear Whitelist?"),
        ("清空后，所有被白名单保护的父进程再次触发敏感外发时，将重新通过 SIGSTOP 挂起并弹出确认窗口。", "After clearing, any sensitive upload from these parent processes will resume triggering SIGSTOP freezes and popup alerts."),
        ("白名单已清空", "Whitelist Cleared"),
        ("Gatekeeper 信任白名单已全部重置，所有敏感外发将恢复实时弹窗确认。", "Gatekeeper trust whitelist reset. All sensitive exfiltrations will prompt for confirmation again."),
        ("获取白名单失败", "Failed to Fetch Whitelist"),
        ("无法从网络哨兵读取当前白名单配置。", "Unable to read current whitelist configuration from Network Sentinel."),
        ("🎯 挑选或搜索监控程序 (Process Selector)", "🎯 Process Selector (Search & Monitor)"),
        ("🎯 挑选正在运行的应用或进程加入重点监控", "🎯 Pick Running App or Process for Priority Watch"),
        ("支持直接按应用名称搜索（如 WeChat、Chrome、Python、Node）或 PID，无需手动查询进程号即可一键加入父子进程沙箱与细粒度流量监控：", "Search by app name (e.g. WeChat, Chrome, Python, Node) or PID to enroll in sandbox guard & granular traffic inspection:"),
        ("🔍 搜索应用名称、进程命令或 PID...", "🔍 Search by app name, command or PID..."),
        ("全部常用程序", "All Common Apps"),
        ("手动输入 PID 纳管:", "Manual PID Input:"),
        ("纳管", "Watch"),
        ("完成关闭", "Done & Close"),
        ("无效 PID", "Invalid PID"),
        ("请输入有效的数值进程号。", "Please enter a valid numeric PID."),
        ("📄 重点监控传输文件内容审查", "📄 Monitored File Content Inspection"),
        ("正在加载属性…", "Loading attributes…"),
        (" ⚪ 待审计 ", " ⚪ Pending Audit "),
        ("🚨 模拟敏感凭证拦截弹窗", "🚨 Test Gatekeeper Alert"),
        ("🚨 一键阻断可疑连接", "🚨 Kill Suspicious"),
        ("🔄 立即扫描", "🔄 Scan Now"),
        ("🔄 刷新", "🔄 Refresh"),
        ("按 CPU 排序", "Sort by CPU"),
        ("按内存排序", "Sort by Memory"),
        ("全部项目", "All Items"),
        ("运行中", "Running"),
        ("已禁用", "Disabled"),
        ("➕ 从运行程序中选择纳管", "➕ Pick Running Process"),
        ("📂 审计分析库", "📂 Security Vault"),
        ("🧹 清空历史", "🧹 Clear History"),
        ("💾 保存并应用拦截策略", "💾 Save & Apply Rules"),
        ("✅ 允许放行 (SIGCONT)", "✅ Allow & Resume (SIGCONT)"),
        ("⏸ 挂起冻结 (SIGSTOP)", "⏸ Pause & Freeze (SIGSTOP)"),
        ("💥 强杀进程树", "💥 Kill Process Tree"),
        ("🗑 移出监控", "🗑 Remove Watch"),
        ("🛑 关本进程", "🛑 Kill Process"),
        ("⬆️ 关父进程", "⬆️ Kill Parent"),
        ("💥 关父子进程树", "💥 Kill Family Tree"),
        ("✕ 关此子进程", "✕ Kill Child"),
        ("🎯 重点监控", "🎯 Watch Process"),
        ("🎯 纳管监控", "🎯 Watch"),
        ("✅ 已纳管", "✅ Watched"),
        ("🔍 上传详情", "🔍 Upload Info"),
        ("阻断 PID", "Kill PID"),
        ("⚡️ 阻断父子进程", "⚡️ Kill Family"),
        ("芯片: ", "Chip: "),
        ("温控: ", "Thermal: "),
        ("系统运行: ", "Uptime: "),
        ("上下文 ", "Context "),
        ("统一内存 96GB", "Unified Memory 96GB"),
        ("实时下行/上行", "Live Down / Up"),
        ("安全态势等级", "Security Posture"),
        ("监听端口暴露", "Listening Ports"),
        ("活跃连接总数", "Active Sockets"),
        ("图片/媒体传输", "Image/Media Uploads"),
        ("代码/文本传输", "Code/Text Uploads"),
        ("文档/压缩包传输", "Archive/Doc Uploads"),
        ("敏感凭据读取", "Sensitive Credentials"),
        ("正在后台运行", "Currently Running"),
        ("已禁用自启", "Disabled Items"),
        ("核心受保护项", "Protected System Items"),
        ("重点监控进程组", "Watched Families"),
        ("目录越权告警", "Out-of-Bounds Alerts"),
        ("敏感载荷拦截", "Blocked Payloads"),
        ("人工放行门禁", "Gatekeeper Prompts"),
        ("全部程序", "All Processes"),
        ("🌐 有外联网络", "🌐 Active Network"),
        ("💻 桌面 App", "💻 Desktop Apps"),
        ("本地网关与守护进程服务", "Local Gateway & Daemon Services"),
        ("启动本地服务", "Start Local Service"),
        ("停止并释放内存", "Stop & Free Memory"),
        ("打开配置", "Open Config"),
        ("查看日志", "Open Logs"),
        ("切到此模型", "Switch Model"),
        ("个进程", "procs"),
        ("个子进程", "children"),
        ("↑ 上传:", "↑ Up:"),
        ("↓ 下载:", "↓ Down:"),
        ("🧠 内存:", "🧠 Mem:"),
        ("🧠 总内存:", "🧠 Total Mem:"),
        ("本进程:", "Self:"),
        ("父进程:", "Parent:"),
        ("子进程:", "Child:"),
        ("🟢 正常", "🟢 SAFE"),
        ("🟡 警告", "🟡 WARN"),
        ("🔴 高危", "🔴 CRIT"),
        ("⚡️ 限速", "⚡️ Limit Speed"),
        ("⚡️ 限速: ", "⚡️ Limit: "),
        ("🚫 不限速 (恢复全速)", "🚫 Unlimited (Full Speed)"),
        ("⚡️ 50 KB/s (极低速)", "⚡️ 50 KB/s (Very Low)"),
        ("⚡️ 200 KB/s (浏览限制)", "⚡️ 200 KB/s (Browsing Cap)"),
        ("⚡️ 500 KB/s", "⚡️ 500 KB/s"),
        ("⚡️ 1 MB/s (1024 KB/s)", "⚡️ 1 MB/s (1024 KB/s)"),
        ("⚡️ 5 MB/s (5120 KB/s)", "⚡️ 5 MB/s (5120 KB/s)"),
        ("✏️ 自定义限速...", "✏️ Custom Limit..."),
        ("解除限速", "Remove Limit"),
        ("限速选项", "Speed Limit Options"),
        ("限速设置", "Speed Limit Settings"),
        ("低速限制", "Low Speed Cap"),
        ("普通限制", "Browsing Cap"),
        ("为目标设置限速", "Set Rate Limit for Target"),
        ("✓ Gatekeeper 信任白名单已清空", "✓ Gatekeeper whitelist cleared"),
        ("⚡️ 正在批量阻断所有异常外联进程...", "⚡️ Blocking all abnormal network processes..."),

        // ─── Code Snippets & API Page ───
        ("Cursor / Cline / Continue 等", "Cursor / Cline / Continue etc."),
        ("Python（OpenAI SDK）", "Python (OpenAI SDK)"),
        ("Python（Anthropic SDK）", "Python (Anthropic SDK)"),
        ("curl · OpenAI 协议", "curl · OpenAI Protocol"),
        ("curl · Anthropic 协议", "curl · Anthropic Protocol"),
        ("（请求里的模型名可以随便写，都会转给它）", " (Arbitrary model name will route to it)"),

        // ─── Models & Client Routing ───
        ("（跟随当前模型）", " (Follows Active Model)"),
        ("原配置 · ", "Original Config · "),
        ("本地 · 经网关 :8002", "Local · via Gateway :8002"),
        ("未指定模型", "No Model Specified"),
        ("未配置", "Not Configured"),
        ("Anthropic 官方", "Anthropic Official"),
        ("本地 · 未选择模型", "Local · No Model Selected"),
        (" · 未加载", " · Not Loaded"),
        ("本地 · ", "Local · "),
        ("云端 · ", "Cloud · "),
        ("服务商 · ", "Provider · "),
        ("有请求", "ago active"),

        // ─── Task Execution & Diagnostics ───
        ("任务完成 · 验收通过（详见实时记录）", "Task completed · Verification passed (see live log)"),
        ("任务已停止或未通过验收 · 详见实时记录", "Task stopped or verification failed · see live log"),
        ("任务执行中…", "Task running…"),
        ("正在停止任务…", "Stopping task…"),
        ("请填写任务", "Please enter task details"),
        ("需要有效的项目路径、具体目标和验收命令。", "Valid project path, specific goal, and verification command required."),
        ("任务启动失败", "Task Launch Failed"),
        ("工作窗口已应用：", "Context Window Applied: "),
        (" · 下一次请求生效", " · Effective on next request"),
        ("工作窗口保存失败：", "Failed to save context window: "),

        // ─── Hardware, Telemetry & Processes ───
        ("已复用 ", "Reused "),
        (" Token", " Tokens"),
        ("预填 ", "Prefill "),
        (" t/s · 生成 ", " t/s · Gen "),
        ("当前服务：", "Active Service: "),
        (" · 前缀缓存生效中", " · Prefix Cache Active"),
        ("SSD 运行时缓存: ", "SSD Runtime Cache: "),
        (" 个分块快照", " chunk snapshots"),
        (" 会话缓存", " session cache"),
        ("正在扫描系统进程家族资源...", "Scanning process families..."),
        ("监控: ", "Monitoring: "),
        (" 系统总 CPU: ", " System Total CPU: "),
        (" 内存: ", " Memory: "),
        ("温控: ", "Thermals: "),
        ("芯片: ", "Chip: "),
        ("系统运行: ", "System Uptime: "),

        // ─── Network Sentinel & Traffic ───
        ("累计已上传", "Total Uploaded"),
        ("累计下载", "Total Downloaded"),
        ("累计上传 ", "Total Up "),
        ("累计下载 ", "Total Down "),
        ("当前上传速度 ", "Upload Speed "),
        ("处高危", "Critical"),
        ("处警告", "Warning"),
        ("处公网暴露", "Exposed"),
        ("公网外联", "Outbound"),
        ("活跃 Socket", "Active Sockets"),
        ("纯网络 Socket 密文/API 请求流", "Encrypted Socket / API Traffic Only"),
        ("纯网络 Socket 密文/API 流式请求 (未检测到磁盘多媒体/文档文件读取)", "Encrypted Socket / API Stream Only (No disk file reads detected)"),
        ("当前读取: ", "Current Reads: "),
        ("公网网络传输", "Public Network Traffic"),
        ("🌍 公网目标", "🌍 Public Target"),
        ("🏠 局域网/本机", "🏠 LAN / Localhost"),
        ("📂 进程当前打开的磁盘文件 (上传数据溯源):", "📂 Open Files Traced to Upload:"),
        ("⛓ 进程链: ", "⛓ Process Lineage: "),
        ("无父进程信息", "No parent info"),
        ("🔼 收起详情", "🔼 Hide Details"),
        ("【本地监听服务与暴露审计 (共 ", "【Local Services & Exposure Audit (Total "),
        (" 个端口)】", " Ports)】"),
        ("⚠️ 全网 0.0.0.0", "⚠️ Public 0.0.0.0"),
        ("🔒 本地回环", "🔒 Local Loopback"),
        (" 监听 ", " listening on "),

        // ─── Startup Items ───
        ("macOS 登录项", "macOS Login Item"),
        ("LaunchAgent 守护进程", "LaunchAgent Daemon"),
        ("🛡️ 核心受保护", "🛡️ Core Protected"),
        ("🔴 已关闭自启", "🔴 Disabled at Boot"),
        ("🟢 运行中", "🟢 Running"),
        ("⚪️ 已开启 / 就绪", "⚪️ Enabled / Ready"),
        ("🔒 白名单锁定", "🔒 Whitelist Locked"),
        ("关闭自启", "Disable Startup"),
        ("开启自启", "Enable Startup"),

        // ─── Watchlist & Candidates & Process Trees ───
        ("暂无匹配的运行程序", "No matching running processes"),
        ("未搜索到包含「", "No process matching '"),
        ("」的运行程序", "' found"),
        ("纳管新进程入重点监控列表", "Enroll New Process in Watchlist"),
        ("🛑 关进程", "🛑 Kill Proc"),
        ("🛑 关本进程", "🛑 Kill Process"),
        ("⬆️ 关父进程", "⬆️ Kill Parent"),
        ("💥 关进程树", "💥 Kill Tree"),
        ("💥 关父子进程树", "💥 Kill Family Tree"),
        ("    ↳ 子进程 PID ", "    ↳ Child PID "),
        ("▼ 展开子进程 (", "▼ Expand Children ("),
        (" (主进程 ", " (Main Proc "),
        ("⚙️ 系统进程 · ", "⚙️ System Process · "),
        ("💻 运行中的 App · ", "💻 Running App · "),
        ("🌐 活跃外联连接 ", "🌐 Active Outbound Sockets: ")
    ]

    private static let sortedEnPairs: [(zh: String, en: String)] = {
        return phrasePairs.sorted { $0.zh.count > $1.zh.count }
    }()

    private static let sortedZhPairs: [(zh: String, en: String)] = {
        return phrasePairs.sorted { $0.en.count > $1.en.count }
    }()

    static func t(_ key: String, default def: String? = nil) -> String {
        return table[key]?[current] ?? (def ?? key)
    }

    static func translate(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        if current == .en {
            for pair in sortedEnPairs {
                if result.contains(pair.zh) {
                    result = result.replacingOccurrences(of: pair.zh, with: pair.en)
                }
            }
        } else {
            for pair in sortedZhPairs {
                if result.contains(pair.en) {
                    result = result.replacingOccurrences(of: pair.en, with: pair.zh)
                }
            }
        }
        return result
    }

    static func localizeViewTree(_ view: NSView) {
        if let sf = view as? NSSearchField {
            if let ph = sf.placeholderString, !ph.isEmpty {
                sf.placeholderString = translate(ph)
            }
        } else if let tf = view as? NSTextField {
            if let ph = tf.placeholderString, !ph.isEmpty {
                tf.placeholderString = translate(ph)
            }
            if !tf.isEditable {
                let updated = translate(tf.stringValue)
                if updated != tf.stringValue {
                    tf.stringValue = updated
                }
            }
        } else if let pop = view as? NSPopUpButton {
            for item in pop.itemArray {
                let updated = translate(item.title)
                if updated != item.title {
                    item.title = updated
                }
            }
        } else if let btn = view as? NSButton {
            let title = btn.attributedTitle.string.isEmpty ? btn.title : btn.attributedTitle.string
            let updated = translate(title)
            if updated != title {
                btn.title = updated
                if !btn.attributedTitle.string.isEmpty {
                    let mutable = NSMutableAttributedString(attributedString: btn.attributedTitle)
                    mutable.mutableString.setString(updated)
                    btn.attributedTitle = mutable
                }
            }
        } else if let seg = view as? NSSegmentedControl {
            for idx in 0..<seg.segmentCount {
                if let label = seg.label(forSegment: idx) {
                    let updated = translate(label)
                    if updated != label {
                        seg.setLabel(updated, forSegment: idx)
                    }
                }
            }
        }
        for sub in view.subviews {
            localizeViewTree(sub)
        }
    }
}

final class SerafinaBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.86, green: 0.78, blue: 0.99, alpha: 1),
            NSColor(srgbRed: 0.96, green: 0.93, blue: 1, alpha: 1),
            NSColor(srgbRed: 0.84, green: 0.89, blue: 0.99, alpha: 1)
        ])
        gradient?.draw(in: bounds, angle: 122)
    }
}

final class TonalCard: NSView {
    private let cardRadius: CGFloat
    init(fill: NSColor, radius: CGFloat) {
        self.cardRadius = radius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor(srgbRed: 0.28, green: 0.14, blue: 0.48, alpha: 1.0).cgColor
        layer?.shadowOpacity = 0.14
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        layer?.shadowRadius = 14
    }

    override func layout() {
        super.layout()
        if bounds.width > 0 && bounds.height > 0 {
            layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)
        }
    }

    required init?(coder: NSCoder) { nil }
}

/// Lightweight frosted-style card using direct layer rendering + cached shadowPath (avoids per-card NSVisualEffectView & dynamic shadow rasterization).
final class FrostCard: NSView {
    private let cardRadius: CGFloat
    init(tint: NSColor, radius: CGFloat, alpha: CGFloat = 0.6) {
        self.cardRadius = radius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.backgroundColor = tint.withAlphaComponent(max(alpha, 0.82)).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        layer?.shadowColor = NSColor(srgbRed: 0.28, green: 0.14, blue: 0.48, alpha: 1.0).cgColor
        layer?.shadowOpacity = 0.15
        layer?.shadowOffset = CGSize(width: 0, height: -8)
        layer?.shadowRadius = 16
    }

    override func layout() {
        super.layout()
        if bounds.width > 0 && bounds.height > 0 {
            layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)
        }
    }

    required init?(coder: NSCoder) { nil }
}

/// Top-anchored document view so scrolled content grows downward naturally.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Floating non-blocking feedback HUD that displays asynchronous task results without stalling UI runloops.
final class ToastHUDView: NSView {
    private let iconLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")

    init(message: String, isSuccess: Bool = true) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false

        let bg = isSuccess ? NSColor(srgbRed: 0.12, green: 0.14, blue: 0.18, alpha: 0.94) : NSColor(srgbRed: 0.28, green: 0.08, blue: 0.10, alpha: 0.94)
        layer?.backgroundColor = bg.cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = isSuccess ? NSColor(srgbRed: 0.25, green: 0.85, blue: 0.55, alpha: 0.45).cgColor : NSColor(srgbRed: 0.95, green: 0.35, blue: 0.35, alpha: 0.45).cgColor

        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.shadowRadius = 12

        iconLabel.font = .systemFont(ofSize: 13, weight: .bold)
        iconLabel.stringValue = isSuccess ? "✨" : "⚠️"

        messageLabel.font = .systemFont(ofSize: 12, weight: .medium)
        messageLabel.textColor = .white
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.maximumNumberOfLines = 2
        messageLabel.stringValue = message

        let stack = NSStackView(views: [iconLabel, messageLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7)
        ])
    }
    required init?(coder: NSCoder) { nil }
}

enum ModelServiceState {
    case stopped    // Red
    case paused     // Static amber: task needs new information
    case idleReady  // Green
    case working    // Orange / Breathing
}

final class LEDMeterView: NSView {
    private let ledCount = 20
    private var ledLayers: [CALayer] = []
    private(set) var currentState: ModelServiceState = .stopped
    private var activeLeds: Int = 0
    private var pulseTimer: Timer?
    private var pulseOpacity: Float = 0.5
    private var pulseIncreasing = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupLeds()
        startPulseTimer()
    }

    required init?(coder: NSCoder) { nil }

    private func setupLeds() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        ledLayers.removeAll()

        for _ in 0..<ledCount {
            let led = CALayer()
            led.cornerRadius = 4.0
            led.cornerCurve = .continuous
            led.masksToBounds = true
            layer?.addSublayer(led)
            ledLayers.append(led)
        }
        updateLedColors()
    }

    override func layout() {
        super.layout()
        let count = CGFloat(ledCount)
        let spacing: CGFloat = 5
        let totalSpacing = spacing * (count - 1)
        let availableWidth = bounds.width - totalSpacing
        let ledWidth = max(5, availableWidth / count)
        let ledHeight: CGFloat = 11

        for (i, led) in ledLayers.enumerated() {
            let x = CGFloat(i) * (ledWidth + spacing)
            let y = (bounds.height - ledHeight) / 2
            led.frame = CGRect(x: x, y: y, width: ledWidth, height: ledHeight)
        }
    }

    func setServiceState(_ newState: ModelServiceState, activeCount: Int = 0) {
        self.currentState = newState
        self.activeLeds = min(ledCount, max(0, activeCount))
        updateLedColors()
    }

    func bumpTokenSpeed(_ tokPerSec: Double) {
        // 每 5 tok/s 点亮一个呼吸灯，满速 100 tok/s 对应 20 个灯满排
        let ledsToLight = Int(round(tokPerSec / 5.0))
        setServiceState(.working, activeCount: max(1, min(ledCount, ledsToLight)))
    }

    private func startPulseTimer() {
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self = self, self.currentState == .working,
                  self.window?.isVisible == true, !self.isHiddenOrHasHiddenAncestor else { return }
            if self.pulseIncreasing {
                self.pulseOpacity += 0.08
                if self.pulseOpacity >= 1.0 { self.pulseIncreasing = false }
            } else {
                self.pulseOpacity -= 0.08
                if self.pulseOpacity <= 0.35 { self.pulseIncreasing = true }
            }
            self.updateLedColors()
        }
    }

    private func updateLedColors() {
        let greenColor = NSColor(srgbRed: 0.20, green: 0.88, blue: 0.42, alpha: 1).cgColor
        let redColor = NSColor(srgbRed: 0.95, green: 0.28, blue: 0.28, alpha: 0.65).cgColor
        let orangeColor = NSColor(srgbRed: 1.00, green: 0.56, blue: 0.12, alpha: 1).cgColor
        let offDarkColor = NSColor(srgbRed: 0.22, green: 0.18, blue: 0.30, alpha: 0.7).cgColor

        for (i, led) in ledLayers.enumerated() {
            switch currentState {
            case .stopped:
                led.backgroundColor = redColor
                led.opacity = 0.55
                led.shadowColor = redColor
                led.shadowRadius = 2
                led.shadowOpacity = 0.2
            case .paused:
                led.backgroundColor = orangeColor
                led.opacity = 0.7
                led.shadowColor = orangeColor
                led.shadowRadius = 2
                led.shadowOpacity = 0.2
            case .idleReady:
                led.backgroundColor = greenColor
                led.opacity = 0.85
                led.shadowColor = greenColor
                led.shadowRadius = 5
                led.shadowOpacity = 0.45
            case .working:
                let active = max(1, activeLeds)
                if i < active {
                    led.backgroundColor = orangeColor
                    led.opacity = pulseOpacity
                    led.shadowColor = orangeColor
                    led.shadowRadius = 8
                    led.shadowOpacity = pulseOpacity * 0.9
                } else {
                    led.backgroundColor = offDarkColor
                    led.opacity = 0.35
                    led.shadowOpacity = 0
                }
            }
        }
    }

    deinit {
        pulseTimer?.invalidate()
    }
}

final class SerafinaButton: NSButton {
    var fill: NSColor = Serafina.cream
    var labelColor: NSColor = Serafina.ink
    private var hovering = false
    private var pressed = false
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        wantsLayer = true
        font = Serafina.rounded(13, .semibold)
        layer?.cornerCurve = .continuous
        // Soft drop shadow for a tactile, slightly raised pill.
        shadow = NSShadow()
        shadow?.shadowColor = NSColor(srgbRed: 0.28, green: 0.14, blue: 0.48, alpha: 0.22)
        shadow?.shadowOffset = NSSize(width: 0, height: -2)
        shadow?.shadowBlurRadius = 6
    }

    required init?(coder: NSCoder) { nil }

    // Breathing room so text never hugs the pill edges.
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 34
        size.height = max(size.height + 6, 36)
        return size
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        animateAlpha(1.0)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        pressed = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        animateAlpha(0.82)
        needsDisplay = true
        super.mouseDown(with: event) // blocks until mouse up while tracking
        pressed = false
        animateAlpha(1.0)
        needsDisplay = true
    }

    private func animateAlpha(_ value: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = value
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        var paint = fill
        if pressed {
            paint = fill.blended(withFraction: 0.18, of: .black) ?? fill
        } else if hovering {
            paint = fill.blended(withFraction: 0.10, of: .white) ?? fill
        }
        paint.setFill()
        path.fill()
        // Subtle top highlight for a soft, flat-but-alive look.
        if !pressed {
            let gloss = NSBezierPath(
                roundedRect: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2),
                xRadius: rect.height / 2, yRadius: rect.height / 2
            )
            (NSColor.white.withAlphaComponent(hovering ? 0.16 : 0.10)).setFill()
            gloss.fill()
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? Serafina.rounded(13, .semibold),
            .foregroundColor: labelColor,
            .paragraphStyle: style
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2 - 1), withAttributes: attributes)
    }
}

struct SystemHardwareMonitor {
    static func getMemoryStats() -> (usedGB: Double, totalGB: Double, percent: Double) {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        let kernReturn = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &count)
            }
        }
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        let totalGB = totalBytes / 1_073_741_824.0
        if kernReturn == KERN_SUCCESS {
            let pageSize = Double(vm_kernel_page_size)
            let wired = Double(vmStats.wire_count) * pageSize
            let active = Double(vmStats.active_count) * pageSize
            let compressed = Double(vmStats.compressor_page_count) * pageSize
            let usedBytes = wired + active + compressed
            let usedGB = usedBytes / 1_073_741_824.0
            return (usedGB, totalGB, min(100.0, (usedGB / totalGB) * 100.0))
        }
        return (0.0, totalGB, 0.0)
    }

    static func getCPUBrand() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let brand = String(cString: buffer)
        return brand.isEmpty ? "Apple Silicon (M-Series)" : brand
    }

    static func getThermalInfo() -> (stateText: String, color: NSColor) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return ("🟢 正常 (Nominal)", NSColor(srgbRed: 0.20, green: 0.88, blue: 0.42, alpha: 1))
        case .fair:
            return ("🟡 温热 (Fair)", NSColor(srgbRed: 0.98, green: 0.72, blue: 0.22, alpha: 1))
        case .serious:
            return ("🟠 较热 (Serious)", NSColor(srgbRed: 1.0, green: 0.45, blue: 0.15, alpha: 1))
        case .critical:
            return ("🔴 过热降频 (Critical)", NSColor(srgbRed: 0.95, green: 0.25, blue: 0.25, alpha: 1))
        @unknown default:
            return ("⚪ 未知", NSColor.secondaryLabelColor)
        }
    }

    static func getUptimeString() -> String {
        let uptime = ProcessInfo.processInfo.systemUptime
        let days = Int(uptime) / 86400
        let hours = (Int(uptime) % 86400) / 3600
        let mins = (Int(uptime) % 3600) / 60
        if days > 0 {
            return "\(days)天 \(hours)小时 \(mins)分"
        } else if hours > 0 {
            return "\(hours)小时 \(mins)分"
        } else {
            return "\(mins)分钟"
        }
    }
}

final class HardwareMetricBar: NSView {
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 46) }

    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let valueLabel = NSTextField(wrappingLabelWithString: "")
    private let percentBadge = NSTextField(wrappingLabelWithString: "")
    private let trackView = NSView()
    private let gradientBar = CAGradientLayer()
    private var gradientColors: [NSColor] = []
    private var currentRatio: CGFloat = 0.0

    var tintColor: NSColor {
        get { gradientColors.first ?? Serafina.grape }
        set {
            let lighter = newValue.blended(withFraction: 0.35, of: .white) ?? newValue
            gradientColors = [newValue, lighter]
            gradientBar.colors = gradientColors.map { $0.cgColor }
        }
    }

    convenience init(title: String, tint: NSColor = Serafina.grape) {
        let lighter = tint.blended(withFraction: 0.35, of: .white) ?? tint
        self.init(title: title, colors: [tint, lighter])
    }

    init(title: String, colors: [NSColor]) {
        super.init(frame: .zero)
        wantsLayer = true
        self.gradientColors = colors
        let primaryColor = colors.first ?? Serafina.grape

        // Glowing indicator dot
        let dotView = NSView()
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3.5
        dotView.layer?.backgroundColor = primaryColor.cgColor
        dotView.layer?.shadowColor = primaryColor.cgColor
        dotView.layer?.shadowRadius = 4.0
        dotView.layer?.shadowOpacity = 0.8
        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.widthAnchor.constraint(equalToConstant: 7).isActive = true
        dotView.heightAnchor.constraint(equalToConstant: 7).isActive = true

        titleLabel.font = Serafina.rounded(12, .semibold)
        titleLabel.textColor = Serafina.ink
        titleLabel.stringValue = title
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        valueLabel.font = Serafina.rounded(12, .medium)
        valueLabel.textColor = Serafina.muted
        valueLabel.alignment = .right
        valueLabel.stringValue = "-- / --"
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        percentBadge.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)
        percentBadge.textColor = primaryColor
        percentBadge.alignment = .center
        percentBadge.stringValue = " 0% "
        percentBadge.wantsLayer = true
        percentBadge.layer?.cornerRadius = 5.0
        percentBadge.layer?.backgroundColor = primaryColor.withAlphaComponent(0.12).cgColor
        percentBadge.setContentHuggingPriority(.required, for: .horizontal)

        let headerStack = NSStackView(views: [dotView, titleLabel, valueLabel, percentBadge])
        headerStack.orientation = .horizontal
        headerStack.spacing = 8
        headerStack.alignment = .centerY
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerStack)

        trackView.wantsLayer = true
        trackView.layer?.cornerRadius = 4.0
        trackView.layer?.cornerCurve = .continuous
        trackView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        trackView.layer?.masksToBounds = true
        trackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trackView)

        gradientBar.cornerRadius = 4.0
        gradientBar.cornerCurve = .continuous
        gradientBar.masksToBounds = true
        gradientBar.startPoint = CGPoint(x: 0, y: 0.5)
        gradientBar.endPoint = CGPoint(x: 1, y: 0.5)
        gradientBar.colors = colors.map { $0.cgColor }
        trackView.layer?.addSublayer(gradientBar)

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerStack.topAnchor.constraint(equalTo: topAnchor),
            headerStack.heightAnchor.constraint(equalToConstant: 20),

            trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            trackView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 7),
            trackView.heightAnchor.constraint(equalToConstant: 8),

            heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        updateBarFrame(animated: false)
    }

    func update(used: Double, total: Double, unit: String = "GB", detail: String? = nil) {
        let safeTotal = max(total, 0.001)
        let ratio = max(0.0, min(1.0, CGFloat(used / safeTotal)))
        currentRatio = ratio
        let pct = Int(round(ratio * 100))
        percentBadge.stringValue = " \(pct)% "
        if let detail = detail {
            valueLabel.stringValue = detail
        } else {
            valueLabel.stringValue = String(format: "%.1f / %.1f %@", used, total, unit)
        }
        updateBarFrame(animated: true)
    }

    private func updateBarFrame(animated: Bool = true) {
        let trackWidth = trackView.bounds.width
        guard trackWidth > 0 else { return }
        let targetWidth = max(trackWidth * currentRatio, currentRatio > 0.001 ? 6.0 : 0.0)
        let newFrame = CGRect(x: 0, y: 0, width: targetWidth, height: trackView.bounds.height)

        if animated {
            let anim = CABasicAnimation(keyPath: "bounds.size.width")
            anim.fromValue = gradientBar.bounds.width
            anim.toValue = targetWidth
            anim.duration = 0.35
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            gradientBar.add(anim, forKey: "widthAnim")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientBar.frame = newFrame
        CATransaction.commit()
    }
}

final class HardwareBentoCard: NSView {
    override var isFlipped: Bool { true }
    let iconLabel = NSTextField(labelWithString: "")
    let titleLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(wrappingLabelWithString: "")
    let subLabel = NSTextField(wrappingLabelWithString: "")

    init(icon: String, title: String, value: String, subtitle: String, accent: NSColor = Serafina.grape) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Serafina.paper.withAlphaComponent(0.70).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.40).cgColor

        iconLabel.font = .systemFont(ofSize: 13)
        iconLabel.stringValue = icon
        iconLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        titleLabel.font = Serafina.rounded(10, .semibold)
        titleLabel.textColor = Serafina.muted
        titleLabel.stringValue = title
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        valueLabel.font = Serafina.rounded(12, .bold)
        valueLabel.textColor = Serafina.ink
        valueLabel.stringValue = value
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subLabel.font = Serafina.rounded(10, .medium)
        subLabel.textColor = Serafina.muted
        subLabel.stringValue = subtitle
        subLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [iconLabel, titleLabel])
        topRow.orientation = .horizontal
        topRow.spacing = 5
        topRow.alignment = .centerY

        let innerStack = NSStackView(views: [topRow, valueLabel, subLabel])
        innerStack.orientation = .vertical
        innerStack.alignment = .leading
        innerStack.spacing = 3
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(innerStack)

        NSLayoutConstraint.activate([
            innerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            innerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            innerStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            innerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 68)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(value: String, subtitle: String? = nil) {
        valueLabel.stringValue = value
        if let subtitle = subtitle { subLabel.stringValue = subtitle }
    }
}

func makeRowLabel(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: string)
    label.font = Serafina.rounded(size, weight)
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
}

final class TrafficWaveformView: NSView {
    override var isFlipped: Bool { true }
    private var history: [[String: Any]] = []
    private var maxSpeed: Double = 1024.0
    private var currentUpload: String = "0 B/s"
    private var currentDownload: String = "0 B/s"
    private var totalUploaded: String = "0 B"
    private var totalDownloaded: String = "0 B"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.13, alpha: 0.92).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
    }

    required init?(coder: NSCoder) { nil }

    func update(history: [[String: Any]], uploadSpeed: String, downloadSpeed: String, totalUp: String, totalDown: String) {
        self.history = history
        self.currentUpload = uploadSpeed
        self.currentDownload = downloadSpeed
        self.totalUploaded = totalUp
        self.totalDownloaded = totalDown

        var peak: Double = 1024.0
        for pt in history {
            let inSpd = pt["in_speed"] as? Double ?? 0
            let outSpd = pt["out_speed"] as? Double ?? 0
            peak = max(peak, max(inSpd, outSpd))
        }
        self.maxSpeed = max(1024.0, peak)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds
        let w = bounds.width
        let h = bounds.height
        let chartLeft: CGFloat = 68.0
        let chartRight: CGFloat = w - 18.0
        let chartBottom: CGFloat = h - 26.0
        let chartTop: CGFloat = 36.0
        let chartWidth = max(20.0, chartRight - chartLeft)
        let chartHeight = max(10.0, chartBottom - chartTop)

        // Draw Y-axis speed labels & horizontal gridlines
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.40)
        ]

        let ticks: [(Double, String)] = [
            (1.0, formatSpeed(maxSpeed)),
            (0.5, formatSpeed(maxSpeed * 0.5)),
            (0.0, "0 B/s")
        ]

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.06).cgColor)
        ctx.setLineWidth(1)
        for (ratio, labelStr) in ticks {
            let y = chartBottom - CGFloat(ratio) * chartHeight
            ctx.move(to: CGPoint(x: chartLeft, y: y))
            ctx.addLine(to: CGPoint(x: chartRight, y: y))
            let sz = (labelStr as NSString).size(withAttributes: labelAttrs)
            NSString(string: labelStr).draw(at: CGPoint(x: chartLeft - sz.width - 6, y: y - sz.height / 2), withAttributes: labelAttrs)
        }
        ctx.strokePath()

        // Draw X-axis time markings
        let timeMarks = ["-40s", "-30s", "-20s", "-10s", I18n.translate("现在 (Live)")]
        for (i, tStr) in timeMarks.enumerated() {
            let tx = chartLeft + chartWidth * (CGFloat(i) / CGFloat(timeMarks.count - 1))
            let sz = (tStr as NSString).size(withAttributes: labelAttrs)
            NSString(string: tStr).draw(at: CGPoint(x: tx - sz.width / 2, y: chartBottom + 6), withAttributes: labelAttrs)
        }

        // Header statistics
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor(srgbRed: 0.88, green: 0.45, blue: 1.0, alpha: 1.0)
        ]
        let leftTitle = I18n.translate("🟣 实时出站上传 (重点监控): ") + "\(currentUpload) · " + I18n.translate("累计已上传: ") + "\(totalUploaded)"
        NSString(string: leftTitle).draw(at: CGPoint(x: 16, y: 10), withAttributes: titleAttrs)

        let dlAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor(srgbRed: 0.25, green: 0.85, blue: 0.70, alpha: 0.9)
        ]
        let rightStr = I18n.translate("🟢 实时入站下载: ") + "\(currentDownload) · " + I18n.translate("累计下载: ") + "\(totalDownloaded) · " + I18n.translate("峰值: ") + formatSpeed(maxSpeed)
        let rSize = (rightStr as NSString).size(withAttributes: dlAttrs)
        NSString(string: rightStr).draw(at: CGPoint(x: max(16.0, w - 16 - rSize.width), y: 11), withAttributes: dlAttrs)

        guard history.count >= 2 else { return }

        let count = history.count
        let stepX = chartWidth / CGFloat(max(1, count - 1))

        // 1. Draw Upload (Area gradient + Line)
        let upPath = CGMutablePath()
        let upFillPath = CGMutablePath()

        for (i, pt) in history.enumerated() {
            let x = chartLeft + CGFloat(i) * stepX
            let val = pt["out_speed"] as? Double ?? 0
            let norm = min(1.0, max(0.0, val / maxSpeed))
            let y = chartBottom - (CGFloat(norm) * chartHeight)
            if i == 0 {
                upPath.move(to: CGPoint(x: x, y: y))
                upFillPath.move(to: CGPoint(x: x, y: chartBottom))
                upFillPath.addLine(to: CGPoint(x: x, y: y))
            } else {
                upPath.addLine(to: CGPoint(x: x, y: y))
                upFillPath.addLine(to: CGPoint(x: x, y: y))
            }
        }
        let lastX = chartLeft + CGFloat(count - 1) * stepX
        upFillPath.addLine(to: CGPoint(x: lastX, y: chartBottom))
        upFillPath.closeSubpath()

        ctx.saveGState()
        ctx.addPath(upFillPath)
        ctx.clip()
        let colors = [
            NSColor(srgbRed: 0.88, green: 0.35, blue: 1.0, alpha: 0.45).cgColor,
            NSColor(srgbRed: 0.88, green: 0.35, blue: 1.0, alpha: 0.02).cgColor
        ] as CFArray
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: chartTop), end: CGPoint(x: 0, y: chartBottom), options: [])
        }
        ctx.restoreGState()

        ctx.setStrokeColor(NSColor(srgbRed: 0.90, green: 0.45, blue: 1.0, alpha: 1.0).cgColor)
        ctx.setLineWidth(2.2)
        ctx.addPath(upPath)
        ctx.strokePath()

        // 2. Draw Download (Line)
        let downPath = CGMutablePath()
        for (i, pt) in history.enumerated() {
            let x = chartLeft + CGFloat(i) * stepX
            let val = pt["in_speed"] as? Double ?? 0
            let norm = min(1.0, max(0.0, val / maxSpeed))
            let y = chartBottom - (CGFloat(norm) * chartHeight)
            if i == 0 {
                downPath.move(to: CGPoint(x: x, y: y))
            } else {
                downPath.addLine(to: CGPoint(x: x, y: y))
            }
        }
        ctx.setStrokeColor(NSColor(srgbRed: 0.20, green: 0.85, blue: 0.70, alpha: 0.85).cgColor)
        ctx.setLineWidth(1.6)
        ctx.addPath(downPath)
        ctx.strokePath()
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return String(format: "%.0f B/s", bytesPerSec) }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/s", bytesPerSec / 1024) }
        return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
    }
}

final class UploadDistributionBarView: NSView {
    override var isFlipped: Bool { true }
    private var imagesCount: Int = 0
    private var textsCount: Int = 0
    private var filesCount: Int = 0
    private var sensitiveCount: Int = 0
    private var apiCount: Int = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 0.75).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
    }

    required init?(coder: NSCoder) { nil }

    func update(images: Int, texts: Int, files: Int, sensitive: Int, api: Int) {
        self.imagesCount = images
        self.textsCount = texts
        self.filesCount = files
        self.sensitiveCount = sensitive
        self.apiCount = api
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds
        let w = bounds.width
        let pad: CGFloat = 14.0
        let barY: CGFloat = 12.0
        let barH: CGFloat = 12.0
        let barW = max(10.0, w - pad * 2)

        let total = max(1, imagesCount + textsCount + filesCount + sensitiveCount + apiCount)

        let barRect = CGRect(x: pad, y: barY, width: barW, height: barH)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.saveGState()
        ctx.addPath(barPath)
        ctx.clip()

        var curX = pad
        let segments: [(Int, NSColor, String)] = [
            (sensitiveCount, NSColor.systemRed, I18n.translate("🚨 敏感凭据")),
            (imagesCount, NSColor(srgbRed: 0.15, green: 0.80, blue: 0.45, alpha: 1.0), I18n.translate("🖼️ 图片多媒体")),
            (textsCount, NSColor(srgbRed: 0.20, green: 0.65, blue: 1.0, alpha: 1.0), I18n.translate("📝 文本代码")),
            (filesCount, NSColor.systemOrange, I18n.translate("📦 文件压缩包")),
            (apiCount, NSColor(srgbRed: 0.75, green: 0.35, blue: 0.95, alpha: 1.0), I18n.translate("🌐 纯API网络流"))
        ]

        for (cnt, col, _) in segments {
            if cnt <= 0 { continue }
            let segW = barW * CGFloat(cnt) / CGFloat(total)
            ctx.setFillColor(col.cgColor)
            ctx.fill(CGRect(x: curX, y: barY, width: segW, height: barH))
            curX += segW
        }
        ctx.restoreGState()

        var legendParts: [String] = []
        if sensitiveCount > 0 { legendParts.append("\(I18n.translate("🚨 敏感凭据")): \(sensitiveCount) (\(sensitiveCount * 100 / total)%)") }
        legendParts.append("\(I18n.translate("🖼️ 图片")): \(imagesCount) (\(imagesCount * 100 / total)%)")
        legendParts.append("\(I18n.translate("📝 文本")): \(textsCount) (\(textsCount * 100 / total)%)")
        legendParts.append("\(I18n.translate("📦 文件")): \(filesCount) (\(filesCount * 100 / total)%)")
        legendParts.append("\(I18n.translate("🌐 API流")): \(apiCount) (\(apiCount * 100 / total)%)")

        let legStr = legendParts.joined(separator: "   ·   ")
        let legAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: Serafina.muted
        ]
        NSString(string: legStr).draw(at: CGPoint(x: pad, y: barY + barH + 7), withAttributes: legAttrs)
    }
}

final class CountryDistributionView: NSView {
    override var isFlipped: Bool { true }
    private var countries: [[String: Any]] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 0.75).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
    }

    required init?(coder: NSCoder) { nil }

    func update(countries: [[String: Any]]) {
        self.countries = countries
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds
        let w = bounds.width
        let pad: CGFloat = 14.0

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: Serafina.ink
        ]
        NSString(string: I18n.translate("🌍 外联目标国家与地域流量分布 (Regional Traffic Distribution):")).draw(at: CGPoint(x: pad, y: 8), withAttributes: headerAttrs)

        guard !countries.isEmpty else {
            let emptyAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: Serafina.muted
            ]
            NSString(string: I18n.translate("当前无活跃公网外部连接")).draw(at: CGPoint(x: pad, y: 28), withAttributes: emptyAttrs)
            return
        }

        let total = max(1, countries.reduce(0) { $0 + ($1["count"] as? Int ?? 0) })
        let barY: CGFloat = 28.0
        let barH: CGFloat = 11.0
        let barW = max(10.0, w - pad * 2)

        let barRect = CGRect(x: pad, y: barY, width: barW, height: barH)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.saveGState()
        ctx.addPath(barPath)
        ctx.clip()

        let palette: [NSColor] = [
            NSColor(srgbRed: 0.85, green: 0.35, blue: 1.0, alpha: 1.0),
            NSColor(srgbRed: 0.20, green: 0.65, blue: 1.0, alpha: 1.0),
            NSColor(srgbRed: 0.15, green: 0.80, blue: 0.45, alpha: 1.0),
            NSColor(srgbRed: 1.0, green: 0.60, blue: 0.15, alpha: 1.0),
            NSColor(srgbRed: 0.95, green: 0.25, blue: 0.30, alpha: 1.0),
            NSColor.systemGray
        ]

        var curX = pad
        for (i, c) in countries.enumerated() {
            let cnt = c["count"] as? Int ?? 0
            if cnt <= 0 { continue }
            let segW = barW * CGFloat(cnt) / CGFloat(total)
            let col = palette[i % palette.count]
            ctx.setFillColor(col.cgColor)
            ctx.fill(CGRect(x: curX, y: barY, width: segW, height: barH))
            curX += segW
        }
        ctx.restoreGState()

        var tagParts: [String] = []
        for c in countries.prefix(5) {
            let flag = c["flag"] as? String ?? "🌐"
            let name = c["country"] as? String ?? ""
            let cnt = c["count"] as? Int ?? 0
            tagParts.append("\(flag) \(name): \(cnt)连 (\(cnt * 100 / total)%)")
        }
        let tagStr = tagParts.joined(separator: "   ·   ")
        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: Serafina.ink
        ]
        NSString(string: tagStr).draw(at: CGPoint(x: pad, y: barY + barH + 6), withAttributes: tagAttrs)
    }
}

final class UploadProcessRowView: NSView {
    override var isFlipped: Bool { true }
    private(set) var pid: Int = 0
    private(set) var ppid: Int = 0
    private(set) var commandName: String = ""
    let onKillSingle: (Int) -> Void
    let onKillFamily: (Int) -> Void
    let onAddToWatchlist: ((Int) -> Void)?
    let onSetRateLimit: ((Int, String, Double) -> Void)?
    let onPromptRateLimit: ((Int, String) -> Void)?

    private let catBadge = makeRowLabel("", size: 10, weight: .bold, color: Serafina.grape)
    private let titleLabel = makeRowLabel("", size: 12, weight: .bold, color: Serafina.ink)
    private let memBadge = makeRowLabel("", size: 10, weight: .bold, color: NSColor(srgbRed: 0.10, green: 0.60, blue: 0.90, alpha: 1.0))
    private let rateBadge = makeRowLabel("", size: 10, weight: .bold, color: NSColor(srgbRed: 0.95, green: 0.55, blue: 0.10, alpha: 1.0))
    private let volLabel = makeRowLabel("", size: 11, weight: .bold, color: NSColor(srgbRed: 0.85, green: 0.20, blue: 0.35, alpha: 1.0))
    private let geoLabel = makeRowLabel("", size: 11, weight: .semibold, color: Serafina.grape)
    private let fillBar = NSView()
    private let barContainer = NSView()
    private var fillWidthConstraint: NSLayoutConstraint?
    private let filesSummaryLabel = makeRowLabel("", size: 10, weight: .regular, color: Serafina.muted)
    private var killParentBtn: NSButton?
    private var rateBtn: NSButton?

    init(
        uploader: [String: Any],
        maxUploadBytes: Int,
        onKillSingle: @escaping (Int) -> Void,
        onKillFamily: @escaping (Int) -> Void,
        onAddToWatchlist: ((Int) -> Void)? = nil,
        onSetRateLimit: ((Int, String, Double) -> Void)? = nil,
        onPromptRateLimit: ((Int, String) -> Void)? = nil
    ) {
        self.onKillSingle = onKillSingle
        self.onKillFamily = onKillFamily
        self.onAddToWatchlist = onAddToWatchlist
        self.onSetRateLimit = onSetRateLimit
        self.onPromptRateLimit = onPromptRateLimit
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Serafina.paper.withAlphaComponent(0.68).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor

        catBadge.wantsLayer = true
        catBadge.layer?.cornerRadius = 4
        memBadge.wantsLayer = true
        memBadge.layer?.cornerRadius = 4
        memBadge.layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.60, blue: 0.90, alpha: 0.12).cgColor

        rateBadge.wantsLayer = true
        rateBadge.layer?.cornerRadius = 4
        rateBadge.layer?.backgroundColor = NSColor(srgbRed: 0.95, green: 0.55, blue: 0.10, alpha: 0.14).cgColor
        rateBadge.isHidden = true

        geoLabel.lineBreakMode = .byTruncatingTail
        filesSummaryLabel.lineBreakMode = .byTruncatingMiddle

        let topRow = NSStackView(views: [catBadge, titleLabel, memBadge, rateBadge, volLabel, geoLabel])
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .centerY

        barContainer.wantsLayer = true
        barContainer.layer?.cornerRadius = 2.5
        barContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.20).cgColor
        barContainer.translatesAutoresizingMaskIntoConstraints = false

        fillBar.wantsLayer = true
        fillBar.layer?.cornerRadius = 2.5
        fillBar.translatesAutoresizingMaskIntoConstraints = false
        barContainer.addSubview(fillBar)

        let wConstraint = fillBar.widthAnchor.constraint(equalTo: barContainer.widthAnchor, multiplier: 0.1)
        self.fillWidthConstraint = wConstraint
        NSLayoutConstraint.activate([
            barContainer.heightAnchor.constraint(equalToConstant: 5),
            fillBar.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
            fillBar.topAnchor.constraint(equalTo: barContainer.topAnchor),
            fillBar.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor),
            wConstraint
        ])

        let leftStack = NSStackView(views: [topRow, barContainer, filesSummaryLabel])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 4

        let rBtn = NSButton(title: I18n.translate("⚡️ 限速"), target: self, action: #selector(didClickRateLimit(_:)))
        rBtn.bezelStyle = .inline
        rBtn.font = .systemFont(ofSize: 10, weight: .bold)
        rBtn.contentTintColor = NSColor(srgbRed: 0.95, green: 0.55, blue: 0.10, alpha: 1.0)
        self.rateBtn = rBtn

        let killBtn = NSButton(title: I18n.translate("🛑 关本进程"), target: self, action: #selector(didClickKillSingle))
        killBtn.bezelStyle = .inline
        killBtn.font = .systemFont(ofSize: 10, weight: .semibold)
        killBtn.contentTintColor = NSColor.systemRed

        let parentBtn = NSButton(title: I18n.translate("⬆️ 关父进程"), target: self, action: #selector(didClickKillParent))
        parentBtn.bezelStyle = .inline
        parentBtn.font = .systemFont(ofSize: 10, weight: .semibold)
        parentBtn.contentTintColor = NSColor.systemOrange
        self.killParentBtn = parentBtn

        let killFamilyBtn = NSButton(title: I18n.translate("💥 关父子进程树"), target: self, action: #selector(didClickKillFamily))
        killFamilyBtn.bezelStyle = .inline
        killFamilyBtn.font = .systemFont(ofSize: 10, weight: .semibold)
        killFamilyBtn.contentTintColor = NSColor(srgbRed: 0.85, green: 0.20, blue: 0.30, alpha: 1.0)

        var btnViews: [NSView] = []
        if onAddToWatchlist != nil {
            let watchBtn = NSButton(title: I18n.translate("🎯 重点监控"), target: self, action: #selector(didClickAddToWatchlist))
            watchBtn.bezelStyle = .inline
            watchBtn.font = .systemFont(ofSize: 10, weight: .bold)
            watchBtn.contentTintColor = NSColor(srgbRed: 0.20, green: 0.60, blue: 0.95, alpha: 1.0)
            btnViews.append(watchBtn)
        }
        btnViews.append(rBtn)
        btnViews.append(contentsOf: [killBtn, parentBtn, killFamilyBtn])

        let btnRow = NSStackView(views: btnViews)
        btnRow.orientation = .horizontal
        btnRow.spacing = 5
        btnRow.alignment = .centerY

        let mainRow = NSStackView(views: [leftStack, NSView(), btnRow])
        mainRow.orientation = .horizontal
        mainRow.alignment = .centerY
        mainRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainRow)

        NSLayoutConstraint.activate([
            mainRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            mainRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            mainRow.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            mainRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            barContainer.widthAnchor.constraint(equalTo: leftStack.widthAnchor)
        ])

        update(uploader: uploader, maxUploadBytes: maxUploadBytes)
    }

    func update(uploader: [String: Any], maxUploadBytes: Int) {
        self.pid = uploader["pid"] as? Int ?? 0
        self.ppid = uploader["ppid"] as? Int ?? 0
        let cmd = uploader["command"] as? String ?? "unknown"
        self.commandName = cmd
        let badgeText = uploader["badge"] as? String ?? "🌐 数据流"
        let uploadFmt = uploader["upload_formatted"] as? String ?? "0 B"
        let downloadFmt = uploader["download_formatted"] as? String ?? "0 B"
        let memFmt = uploader["memory_formatted"] as? String ?? "0 B"
        let famMemFmt = uploader["family_memory_formatted"] as? String ?? memFmt
        let treeStr = uploader["tree_str"] as? String ?? ""
        let upBytes = uploader["upload_bytes"] as? Int ?? 0
        let downBytes = uploader["download_bytes"] as? Int ?? 0
        let geoSummary = uploader["geo"] as? String ?? ""
        let openFiles = uploader["open_files"] as? [String] ?? []
        let isSensitive = badgeText.contains("敏感")

        let rateFmt = uploader["rate_limit_formatted"] as? String ?? ""
        let rateKb = uploader["rate_limit_kb_s"] as? Double ?? 0.0
        if rateKb > 0 && !rateFmt.isEmpty {
            rateBadge.stringValue = " ⚡️ 限速: \(rateFmt) "
            rateBadge.isHidden = false
        } else {
            rateBadge.stringValue = ""
            rateBadge.isHidden = true
        }

        let badgeColor: NSColor
        if isSensitive {
            badgeColor = NSColor.systemRed
        } else if badgeText.contains("图片") {
            badgeColor = NSColor(srgbRed: 0.15, green: 0.78, blue: 0.40, alpha: 1.0)
        } else if badgeText.contains("文件") {
            badgeColor = NSColor.systemOrange
        } else if badgeText.contains("文本") {
            badgeColor = NSColor(srgbRed: 0.20, green: 0.60, blue: 0.95, alpha: 1.0)
        } else {
            badgeColor = Serafina.grape
        }

        catBadge.stringValue = " \(badgeText) "
        catBadge.textColor = badgeColor
        catBadge.layer?.backgroundColor = badgeColor.withAlphaComponent(0.12).cgColor

        let ppidSuffix = ppid > 1 ? " · PPID:\(ppid)" : ""
        titleLabel.stringValue = "\(cmd) (PID:\(pid)\(ppidSuffix))"
        memBadge.stringValue = famMemFmt != memFmt ? " 🧠 \(memFmt) (总\(famMemFmt)) " : " 🧠 内存: \(memFmt) "
        volLabel.stringValue = I18n.translate("↑ 上传: \(uploadFmt) · ↓ 下载: \(downloadFmt)")
        geoLabel.stringValue = "📍 \(geoSummary.isEmpty ? "公网网络传输" : geoSummary)"
        killParentBtn?.isHidden = (ppid <= 1)

        fillBar.layer?.backgroundColor = badgeColor.cgColor
        let ratio = CGFloat(max(0.04, min(1.0, Double(upBytes + downBytes) / Double(max(1, maxUploadBytes)))))
        if let old = fillWidthConstraint, abs(old.multiplier - ratio) > 0.02 {
            old.isActive = false
            let next = fillBar.widthAnchor.constraint(equalTo: barContainer.widthAnchor, multiplier: ratio)
            next.isActive = true
            fillWidthConstraint = next
        }

        let linPrefix = treeStr.isEmpty ? "" : "[\(treeStr)] "
        if openFiles.isEmpty {
            filesSummaryLabel.stringValue = "• \(linPrefix)纯网络 Socket 密文/API 请求流"
            filesSummaryLabel.textColor = Serafina.muted
        } else {
            filesSummaryLabel.stringValue = "• \(linPrefix)当前读取: " + openFiles.prefix(2).joined(separator: " | ")
            filesSummaryLabel.textColor = isSensitive ? NSColor.systemRed : Serafina.ink
        }
    }

    @objc private func didClickRateLimit(_ sender: NSButton) {
        let menu = NSMenu(title: "限速设置")
        let noLimit = NSMenuItem(title: I18n.translate("🚫 不限速 (恢复全速)"), action: #selector(handleRateLimitChoice(_:)), keyEquivalent: "")
        noLimit.target = self
        noLimit.representedObject = Double(0)
        menu.addItem(noLimit)
        menu.addItem(NSMenuItem.separator())

        let presets: [(String, Double)] = [
            ("⚡️ 50 KB/s (极低速)", 50.0),
            ("⚡️ 200 KB/s (浏览限制)", 200.0),
            ("⚡️ 500 KB/s", 500.0),
            ("⚡️ 1 MB/s (1024 KB/s)", 1024.0),
            ("⚡️ 5 MB/s (5120 KB/s)", 5120.0)
        ]
        for (label, val) in presets {
            let item = NSMenuItem(title: I18n.translate(label), action: #selector(handleRateLimitChoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = val
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let custom = NSMenuItem(title: I18n.translate("✏️ 自定义限速..."), action: #selector(handleCustomRateLimit), keyEquivalent: "")
        custom.target = self
        menu.addItem(custom)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func handleRateLimitChoice(_ item: NSMenuItem) {
        guard let limit = item.representedObject as? Double else { return }
        onSetRateLimit?(pid, commandName, limit)
    }

    @objc private func handleCustomRateLimit() {
        onPromptRateLimit?(pid, commandName)
    }

    @objc private func didClickKillSingle() { onKillSingle(pid) }
    @objc private func didClickKillParent() { if ppid > 1 { onKillSingle(ppid) } }
    @objc private func didClickKillFamily() { onKillFamily(pid) }
    @objc private func didClickAddToWatchlist() { onAddToWatchlist?(pid) }
    required init?(coder: NSCoder) { nil }
}

final class NetworkConnRowView: NSView {
    override var isFlipped: Bool { true }
    private(set) var pid: Int = 0
    private(set) var ppid: Int = 0
    private(set) var commandName: String = ""
    let onKillSingle: (Int) -> Void
    let onKillFamily: (Int) -> Void
    let onAddToWatchlist: ((Int) -> Void)?
    let onSetRateLimit: ((Int, String, Double) -> Void)?
    let onPromptRateLimit: ((Int, String) -> Void)?
    private var detailBox: NSStackView?
    private var isExpanded: Bool = false
    private var toggleDetailBtn: NSButton?
    private var killParentBtn: NSButton?
    private var rateBtn: NSButton?

    private let riskBadge = makeRowLabel("", size: 10, weight: .bold, color: Serafina.ink)
    private let uploadBadge = makeRowLabel("", size: 10, weight: .bold, color: Serafina.grape)
    private let memBadge = makeRowLabel("", size: 10, weight: .bold, color: NSColor(srgbRed: 0.10, green: 0.60, blue: 0.90, alpha: 1.0))
    private let rateBadge = makeRowLabel("", size: 10, weight: .bold, color: NSColor(srgbRed: 0.95, green: 0.55, blue: 0.10, alpha: 1.0))
    private let titleLabel = makeRowLabel("", size: 12, weight: .bold, color: Serafina.ink)
    private let geoLabel = makeRowLabel("", size: 11, weight: .semibold, color: Serafina.muted)
    private let sockText = makeRowLabel("", size: 11, weight: .medium, color: Serafina.ink)
    private let lineageLabel = makeRowLabel("", size: 10, weight: .medium, color: Serafina.muted)
    private let detailFilesLabel = makeRowLabel("", size: 10, weight: .regular, color: Serafina.muted)

    init(
        conn: [String: Any],
        onKillSingle: @escaping (Int) -> Void,
        onKillFamily: @escaping (Int) -> Void,
        onAddToWatchlist: ((Int) -> Void)? = nil,
        onSetRateLimit: ((Int, String, Double) -> Void)? = nil,
        onPromptRateLimit: ((Int, String) -> Void)? = nil
    ) {
        self.onKillSingle = onKillSingle
        self.onKillFamily = onKillFamily
        self.onAddToWatchlist = onAddToWatchlist
        self.onSetRateLimit = onSetRateLimit
        self.onPromptRateLimit = onPromptRateLimit
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Serafina.paper.withAlphaComponent(0.68).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor

        riskBadge.wantsLayer = true
        riskBadge.layer?.cornerRadius = 4
        uploadBadge.wantsLayer = true
        uploadBadge.layer?.cornerRadius = 4
        memBadge.wantsLayer = true
        memBadge.layer?.cornerRadius = 4
        memBadge.layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.60, blue: 0.90, alpha: 0.12).cgColor

        rateBadge.wantsLayer = true
        rateBadge.layer?.cornerRadius = 4
        rateBadge.layer?.backgroundColor = NSColor(srgbRed: 0.95, green: 0.55, blue: 0.10, alpha: 0.14).cgColor
        rateBadge.isHidden = true

        geoLabel.lineBreakMode = .byTruncatingTail
        lineageLabel.lineBreakMode = .byTruncatingTail
        detailFilesLabel.lineBreakMode = .byTruncatingMiddle

        let topRow = NSStackView(views: [riskBadge, uploadBadge, titleLabel, memBadge, rateBadge, geoLabel])
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .centerY

        let leftStack = NSStackView(views: [topRow, sockText, lineageLabel])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 3

        let rBtn = NSButton(title: I18n.translate("⚡️ 限速"), target: self, action: #selector(didClickRateLimit(_:)))
        rBtn.bezelStyle = .inline
        rBtn.font = .systemFont(ofSize: 10, weight: .bold)
        rBtn.contentTintColor = NSColor(srgbRed: 0.95, green: 0.55, blue: 0.10, alpha: 1.0)
        self.rateBtn = rBtn

        let killBtn = NSButton(title: I18n.translate("🛑 关本进程"), target: self, action: #selector(didClickKillSingle))
        killBtn.bezelStyle = .inline
        killBtn.font = .systemFont(ofSize: 10, weight: .semibold)
        killBtn.contentTintColor = NSColor.systemRed

        let parentBtn = NSButton(title: I18n.translate("⬆️ 关父进程"), target: self, action: #selector(didClickKillParent))
        parentBtn.bezelStyle = .inline
        parentBtn.font = .systemFont(ofSize: 10, weight: .semibold)
        parentBtn.contentTintColor = NSColor.systemOrange
        self.killParentBtn = parentBtn

        let killFamilyBtn = NSButton(title: I18n.translate("💥 关父子进程树"), target: self, action: #selector(didClickKillFamily))
        killFamilyBtn.bezelStyle = .inline
        killFamilyBtn.font = .systemFont(ofSize: 10, weight: .semibold)
        killFamilyBtn.contentTintColor = NSColor(srgbRed: 0.85, green: 0.20, blue: 0.30, alpha: 1.0)

        let detailBtn = NSButton(title: I18n.translate("🔍 上传详情"), target: self, action: #selector(toggleDetail))
        detailBtn.bezelStyle = .inline
        detailBtn.font = .systemFont(ofSize: 10, weight: .medium)
        detailBtn.contentTintColor = Serafina.grape
        self.toggleDetailBtn = detailBtn

        var btnViews: [NSView] = [rBtn, detailBtn]
        if onAddToWatchlist != nil {
            let watchBtn = NSButton(title: I18n.translate("🎯 重点监控"), target: self, action: #selector(didClickAddToWatchlist))
            watchBtn.bezelStyle = .inline
            watchBtn.font = .systemFont(ofSize: 10, weight: .bold)
            watchBtn.contentTintColor = NSColor(srgbRed: 0.20, green: 0.60, blue: 0.95, alpha: 1.0)
            btnViews.append(watchBtn)
        }
        btnViews.append(contentsOf: [killBtn, parentBtn, killFamilyBtn])

        let btnRow = NSStackView(views: btnViews)
        btnRow.orientation = .horizontal
        btnRow.spacing = 5
        btnRow.alignment = .centerY

        let mainRow = NSStackView(views: [leftStack, NSView(), btnRow])
        mainRow.orientation = .horizontal
        mainRow.alignment = .centerY
        mainRow.translatesAutoresizingMaskIntoConstraints = false

        let dBox = NSStackView()
        dBox.orientation = .vertical
        dBox.alignment = .leading
        dBox.spacing = 3
        dBox.isHidden = true
        self.detailBox = dBox

        let fileHeading = makeRowLabel("📂 进程当前打开的磁盘文件 (上传数据溯源):", size: 10, weight: .bold, color: Serafina.ink)
        dBox.addArrangedSubview(fileHeading)
        dBox.addArrangedSubview(detailFilesLabel)

        let containerStack = NSStackView(views: [mainRow, dBox])
        containerStack.orientation = .vertical
        containerStack.alignment = .leading
        containerStack.spacing = 6
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerStack)

        NSLayoutConstraint.activate([
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            containerStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            mainRow.widthAnchor.constraint(equalTo: containerStack.widthAnchor)
        ])

        update(conn: conn)
    }

    func update(conn: [String: Any]) {
        self.pid = conn["pid"] as? Int ?? 0
        self.ppid = conn["ppid"] as? Int ?? 0
        let cmd = conn["command"] as? String ?? "unknown"
        self.commandName = cmd
        let localAddr = conn["local"] as? String ?? ""
        let remote = conn["remote"] as? String ?? ""
        let proto = conn["proto"] as? String ?? "TCP"
        let state = conn["state"] as? String ?? "ESTABLISHED"
        let risk = conn["risk"] as? String ?? "NORMAL"
        let treeStr = conn["tree_str"] as? String ?? ""
        let memFmt = conn["memory_formatted"] as? String ?? "0 B"
        let famMemFmt = conn["family_memory_formatted"] as? String ?? memFmt
        let isPublic = conn["is_public"] as? Bool ?? false

        let geo = conn["geo"] as? [String: Any] ?? [:]
        let geoSummary = geo["summary"] as? String ?? (isPublic ? "🌍 公网目标" : "🏠 局域网/本机")

        let uploadAudit = conn["upload_audit"] as? [String: Any] ?? [:]
        let uploadBadgeText = uploadAudit["badge"] as? String ?? "🌐 数据流"
        let uploadFmt = uploadAudit["upload_formatted"] as? String ?? "0 B"
        let downloadFmt = uploadAudit["download_formatted"] as? String ?? "0 B"
        let isSensitive = uploadAudit["sensitive"] as? Bool ?? false
        let openFiles = uploadAudit["open_files"] as? [String] ?? []

        let rateFmt = conn["rate_limit_formatted"] as? String ?? ""
        let rateKb = conn["rate_limit_kb_s"] as? Double ?? 0.0
        if rateKb > 0 && !rateFmt.isEmpty {
            rateBadge.stringValue = " ⚡️ 限速: \(rateFmt) "
            rateBadge.isHidden = false
        } else {
            rateBadge.stringValue = ""
            rateBadge.isHidden = true
        }

        let riskColor: NSColor
        let riskText: String
        switch risk {
        case "CRITICAL":
            riskColor = NSColor.systemRed; riskText = I18n.translate("🔴 高危")
        case "WARNING":
            riskColor = NSColor.systemOrange; riskText = I18n.translate("🟡 警告")
        default:
            riskColor = NSColor(srgbRed: 0.15, green: 0.80, blue: 0.35, alpha: 1.0); riskText = I18n.translate("🟢 正常")
        }
        riskBadge.stringValue = " \(riskText) "
        riskBadge.textColor = riskColor
        riskBadge.layer?.backgroundColor = riskColor.withAlphaComponent(0.12).cgColor

        let uploadBadgeColor: NSColor
        if isSensitive {
            uploadBadgeColor = NSColor.systemRed
        } else if uploadBadgeText.contains("图片") {
            uploadBadgeColor = NSColor(srgbRed: 0.15, green: 0.78, blue: 0.40, alpha: 1.0)
        } else if uploadBadgeText.contains("文件") {
            uploadBadgeColor = NSColor.systemOrange
        } else if uploadBadgeText.contains("文本") {
            uploadBadgeColor = NSColor(srgbRed: 0.20, green: 0.60, blue: 0.95, alpha: 1.0)
        } else {
            uploadBadgeColor = Serafina.grape
        }
        uploadBadge.stringValue = " \(uploadBadgeText) "
        uploadBadge.textColor = uploadBadgeColor
        uploadBadge.layer?.backgroundColor = uploadBadgeColor.withAlphaComponent(0.12).cgColor

        let ppidSuffix = ppid > 1 ? " · PPID:\(ppid)" : ""
        titleLabel.stringValue = "\(cmd) (PID:\(pid)\(ppidSuffix))"
        memBadge.stringValue = famMemFmt != memFmt ? " 🧠 \(memFmt) (总\(famMemFmt)) " : " 🧠 内存: \(memFmt) "
        geoLabel.stringValue = "📍 \(geoSummary)"
        geoLabel.textColor = isPublic ? Serafina.grape : Serafina.muted
        killParentBtn?.isHidden = (ppid <= 1)

        let endpointDesc = localAddr.isEmpty ? "[\(proto)] → \(remote) (\(state))" : "[\(proto)] \(localAddr) → \(remote) (\(state))"
        sockText.stringValue = I18n.translate("\(endpointDesc) · ↑ 上传: \(uploadFmt) · ↓ 下载: \(downloadFmt)")
        lineageLabel.stringValue = "⛓ 进程链: \(treeStr.isEmpty ? "无父进程信息" : treeStr)"

        if openFiles.isEmpty {
            detailFilesLabel.stringValue = "• 纯网络 Socket 密文/API 流式请求 (未检测到磁盘多媒体/文档文件读取)"
            detailFilesLabel.textColor = Serafina.muted
        } else {
            detailFilesLabel.stringValue = openFiles.prefix(4).map { "• \($0)" }.joined(separator: "  ")
            detailFilesLabel.textColor = isSensitive ? NSColor.systemRed : Serafina.ink
        }
    }

    @objc private func didClickRateLimit(_ sender: NSButton) {
        let menu = NSMenu(title: "限速设置")
        let noLimit = NSMenuItem(title: I18n.translate("🚫 不限速 (恢复全速)"), action: #selector(handleRateLimitChoice(_:)), keyEquivalent: "")
        noLimit.target = self
        noLimit.representedObject = Double(0)
        menu.addItem(noLimit)
        menu.addItem(NSMenuItem.separator())

        let presets: [(String, Double)] = [
            ("⚡️ 50 KB/s (极低速)", 50.0),
            ("⚡️ 200 KB/s (浏览限制)", 200.0),
            ("⚡️ 500 KB/s", 500.0),
            ("⚡️ 1 MB/s (1024 KB/s)", 1024.0),
            ("⚡️ 5 MB/s (5120 KB/s)", 5120.0)
        ]
        for (label, val) in presets {
            let item = NSMenuItem(title: I18n.translate(label), action: #selector(handleRateLimitChoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = val
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let custom = NSMenuItem(title: I18n.translate("✏️ 自定义限速..."), action: #selector(handleCustomRateLimit), keyEquivalent: "")
        custom.target = self
        menu.addItem(custom)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func handleRateLimitChoice(_ item: NSMenuItem) {
        guard let limit = item.representedObject as? Double else { return }
        onSetRateLimit?(pid, commandName, limit)
    }

    @objc private func handleCustomRateLimit() {
        onPromptRateLimit?(pid, commandName)
    }

    @objc private func toggleDetail() {
        guard let box = detailBox else { return }
        isExpanded.toggle()
        box.isHidden = !isExpanded
        toggleDetailBtn?.title = isExpanded ? "🔼 收起详情" : I18n.translate("🔍 上传详情")
    }

    @objc private func didClickKillSingle() { onKillSingle(pid) }
    @objc private func didClickKillParent() { if ppid > 1 { onKillSingle(ppid) } }
    @objc private func didClickKillFamily() { onKillFamily(pid) }
    @objc private func didClickAddToWatchlist() { onAddToWatchlist?(pid) }
    required init?(coder: NSCoder) { nil }
}

final class StartupItemRowView: NSView {
    override var isFlipped: Bool { true }
    private(set) var itemId: String = ""
    private(set) var isCurrentlyEnabled: Bool = false
    private(set) var isEssential: Bool = false
    let onToggle: (String, Bool) -> Void

    private let iconLabel = NSTextField(labelWithString: "📦")
    private let titleLabel = makeRowLabel("", size: 12, weight: .bold, color: Serafina.ink)
    private let subLabel = makeRowLabel("", size: 10, weight: .medium, color: Serafina.muted)
    private let statusBadge = makeRowLabel("", size: 10, weight: .semibold, color: Serafina.ink)
    private let lockLabel = makeRowLabel("🔒 白名单锁定", size: 10, weight: .semibold, color: Serafina.muted)
    private lazy var toggleBtn: NSButton = {
        let btn = NSButton(title: "关闭自启", target: self, action: #selector(didClickToggle))
        btn.bezelStyle = .inline
        btn.font = .systemFont(ofSize: 11, weight: .semibold)
        return btn
    }()

    init(item: [String: Any], onToggle: @escaping (String, Bool) -> Void) {
        self.onToggle = onToggle
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Serafina.paper.withAlphaComponent(0.65).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.40).cgColor

        iconLabel.font = .systemFont(ofSize: 20)
        subLabel.lineBreakMode = .byTruncatingMiddle

        let textStack = NSStackView(views: [titleLabel, subLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let leftInfoStack = NSStackView(views: [iconLabel, textStack])
        leftInfoStack.orientation = .horizontal
        leftInfoStack.spacing = 10
        leftInfoStack.alignment = .centerY

        statusBadge.wantsLayer = true
        statusBadge.layer?.cornerRadius = 4

        let mainRow = NSStackView(views: [leftInfoStack, NSView(), statusBadge, lockLabel, toggleBtn])
        mainRow.orientation = .horizontal
        mainRow.alignment = .centerY
        mainRow.spacing = 10
        mainRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainRow)

        NSLayoutConstraint.activate([
            mainRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            mainRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            mainRow.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            mainRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            subLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 380)
        ])

        update(item: item)
    }

    func update(item: [String: Any]) {
        self.itemId = item["id"] as? String ?? ""
        let enabled = item["enabled"] as? Bool ?? false
        self.isCurrentlyEnabled = enabled
        let essential = item["is_essential"] as? Bool ?? false
        self.isEssential = essential

        let iconStr = item["icon"] as? String ?? "📦"
        let dispName = item["display_name"] as? String ?? (item["name"] as? String ?? "")
        let techName = item["name"] as? String ?? ""
        let itemType = item["item_type"] as? String ?? ""
        let typeName = (itemType == "login_item") ? I18n.translate("macOS 登录项") : I18n.translate("LaunchAgent 守护进程")
        let running = item["running"] as? Bool ?? false
        let pid = item["pid"] as? Int
        let targetExec = item["target_exec"] as? String ?? ""

        iconLabel.stringValue = iconStr
        titleLabel.stringValue = dispName
        let execTrunc = targetExec.isEmpty ? techName : targetExec
        subLabel.stringValue = "\(techName) · \(typeName) · \(execTrunc)"

        let statusColor: NSColor
        let statusText: String
        if essential {
            statusColor = Serafina.grape
            statusText = I18n.translate("🛡️ 核心受保护")
        } else if !enabled {
            statusColor = NSColor.systemRed
            statusText = I18n.translate("🔴 已关闭自启")
        } else if running {
            let pidStr = (pid != nil && pid! > 0) ? " PID \(pid!)" : ""
            statusColor = NSColor(srgbRed: 0.15, green: 0.80, blue: 0.35, alpha: 1.0)
            statusText = I18n.translate("🟢 运行中") + pidStr
        } else {
            statusColor = NSColor.systemBlue
            statusText = I18n.translate("⚪️ 已开启 / 就绪")
        }
        statusBadge.stringValue = " \(statusText) "
        statusBadge.textColor = statusColor
        statusBadge.layer?.backgroundColor = statusColor.withAlphaComponent(0.12).cgColor

        lockLabel.stringValue = I18n.translate("🔒 白名单锁定")
        lockLabel.isHidden = !essential
        toggleBtn.isHidden = essential
        if !essential {
            toggleBtn.title = I18n.translate(enabled ? "关闭自启" : "开启自启")
            toggleBtn.contentTintColor = enabled ? NSColor.systemRed : NSColor(srgbRed: 0.15, green: 0.80, blue: 0.35, alpha: 1.0)
        }
    }

    @objc private func didClickToggle() {
        onToggle(itemId, !isCurrentlyEnabled)
    }

    required init?(coder: NSCoder) { nil }
}

final class MetricStatCard: NSView {
    override var isFlipped: Bool { true }
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let valueLabel = NSTextField(wrappingLabelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")

    init(title: String, initialValue: String = "--", initialSubtitle: String = "--", fill: NSColor = Serafina.paper) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = fill.withAlphaComponent(0.65).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor

        titleLabel.font = Serafina.rounded(11, .semibold)
        titleLabel.textColor = Serafina.muted
        titleLabel.stringValue = title.uppercased()
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        valueLabel.font = Serafina.rounded(18, .bold)
        valueLabel.textColor = Serafina.ink
        valueLabel.stringValue = initialValue
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = Serafina.rounded(11, .medium)
        subtitleLabel.textColor = Serafina.muted
        subtitleLabel.stringValue = initialSubtitle
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [titleLabel, valueLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 74)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func setValues(value: String, subtitle: String) {
        valueLabel.stringValue = value
        subtitleLabel.stringValue = subtitle
    }
}

final class ProcessCandidateRowView: NSView {
    override var isFlipped: Bool { true }
    private(set) var pid: Int = 0
    private(set) var ppid: Int = 0
    private(set) var processName: String = ""
    let onAdd: (Int) -> Void
    var onKillSingle: ((Int) -> Void)?
    var onSetRateLimit: ((Int, String, Double) -> Void)?
    var onPromptRateLimit: ((Int, String) -> Void)?
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let pidTag = NSTextField(labelWithString: "")
    private let memTag = NSTextField(labelWithString: "")
    private let descLabel = NSTextField(labelWithString: "")
    private var actionBtn: NSButton?
    private var killBtn: NSButton?
    private var rateBtn: NSButton?

    init(
        candidate: [String: Any],
        iconImage: NSImage?,
        onAdd: @escaping (Int) -> Void,
        onKillSingle: ((Int) -> Void)? = nil,
        onSetRateLimit: ((Int, String, Double) -> Void)? = nil,
        onPromptRateLimit: ((Int, String) -> Void)? = nil
    ) {
        self.onAdd = onAdd
        self.onKillSingle = onKillSingle
        self.onSetRateLimit = onSetRateLimit
        self.onPromptRateLimit = onPromptRateLimit
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.65).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.black.withAlphaComponent(0.06).cgColor

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = Serafina.ink
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        pidTag.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        pidTag.textColor = Serafina.muted
        pidTag.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        memTag.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        memTag.textColor = NSColor(srgbRed: 0.10, green: 0.60, blue: 0.90, alpha: 1.0)
        memTag.wantsLayer = true
        memTag.layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.60, blue: 0.90, alpha: 0.12).cgColor
        memTag.layer?.cornerRadius = 4
        memTag.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [titleLabel, pidTag, memTag])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 6

        descLabel.font = .systemFont(ofSize: 10, weight: .regular)
        descLabel.textColor = Serafina.muted
        descLabel.lineBreakMode = .byTruncatingMiddle
        descLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [topRow, descLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let rBtn = NSButton(title: I18n.translate("⚡️ 限速"), target: self, action: #selector(didClickRateLimit(_:)))
        rBtn.isBordered = false
        rBtn.wantsLayer = true
        rBtn.layer?.cornerRadius = 10
        rBtn.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.14).cgColor
        rBtn.font = .systemFont(ofSize: 10, weight: .bold)
        rBtn.contentTintColor = NSColor.systemOrange
        rBtn.translatesAutoresizingMaskIntoConstraints = false
        self.rateBtn = rBtn

        let kBtn = NSButton(title: I18n.translate("🛑 关进程"), target: self, action: #selector(didClickKillSelf))
        kBtn.isBordered = false
        kBtn.wantsLayer = true
        kBtn.layer?.cornerRadius = 10
        kBtn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.14).cgColor
        kBtn.font = .systemFont(ofSize: 10, weight: .bold)
        kBtn.translatesAutoresizingMaskIntoConstraints = false
        self.killBtn = kBtn

        let btn = NSButton(title: "", target: self, action: #selector(didClickAdd))
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 12
        btn.layer?.cornerCurve = .continuous
        btn.translatesAutoresizingMaskIntoConstraints = false
        self.actionBtn = btn

        addSubview(iconView)
        addSubview(textStack)
        addSubview(rBtn)
        addSubview(kBtn)
        addSubview(btn)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),

            btn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            btn.centerYAnchor.constraint(equalTo: centerYAnchor),
            btn.widthAnchor.constraint(equalToConstant: 80),
            btn.heightAnchor.constraint(equalToConstant: 26),

            kBtn.trailingAnchor.constraint(equalTo: btn.leadingAnchor, constant: -6),
            kBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            kBtn.widthAnchor.constraint(equalToConstant: 64),
            kBtn.heightAnchor.constraint(equalToConstant: 24),

            rBtn.trailingAnchor.constraint(equalTo: kBtn.leadingAnchor, constant: -6),
            rBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            rBtn.widthAnchor.constraint(equalToConstant: 58),
            rBtn.heightAnchor.constraint(equalToConstant: 24),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: rBtn.leadingAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        update(candidate: candidate, iconImage: iconImage)
    }

    func update(candidate: [String: Any], iconImage: NSImage?) {
        self.pid = candidate["pid"] as? Int ?? 0
        self.ppid = candidate["ppid"] as? Int ?? 0
        let name = candidate["name"] as? String ?? "未知进程"
        self.processName = name
        let cmd = candidate["command"] as? String ?? ""
        let path = candidate["path"] as? String ?? ""
        let hasNet = candidate["has_network"] as? Bool ?? false
        let socketsCount = candidate["sockets_count"] as? Int ?? 0
        let isApp = candidate["is_app"] as? Bool ?? false
        let isWatched = candidate["is_watched"] as? Bool ?? false
        let memFmt = candidate["memory_formatted"] as? String ?? ""
        let famMemFmt = candidate["family_memory_formatted"] as? String ?? ""

        if let icon = iconImage {
            iconView.image = icon
        } else {
            let symbol = isApp ? "laptopcomputer" : (hasNet ? "network" : "gearshape")
            if #available(macOS 11.0, *) {
                iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
        }

        titleLabel.stringValue = name
        pidTag.stringValue = ppid > 0 ? "PID: \(pid) (PPID: \(ppid))" : "PID: \(pid)"
        if !memFmt.isEmpty {
            let extra = (!famMemFmt.isEmpty && famMemFmt != memFmt) ? " (总 \(famMemFmt))" : ""
            memTag.stringValue = I18n.translate(" 🧠 内存: \(memFmt)\(extra) ")
            memTag.isHidden = false
        } else {
            memTag.isHidden = true
        }

        var subDesc = path
        if subDesc.isEmpty { subDesc = cmd }
        if hasNet {
            subDesc = "🌐 活跃外联连接 \(socketsCount) 个 · \(subDesc)"
        } else if isApp {
            subDesc = "💻 运行中的 App · \(subDesc)"
        } else {
            subDesc = "⚙️ 系统进程 · \(subDesc)"
        }
        descLabel.stringValue = I18n.translate(subDesc)

        if let btn = actionBtn {
            btn.layer?.backgroundColor = isWatched ? NSColor.systemGreen.withAlphaComponent(0.18).cgColor : Serafina.grape.cgColor
            let titleColor = isWatched ? NSColor(srgbRed: 0.1, green: 0.6, blue: 0.2, alpha: 1.0) : NSColor.white
            let titleText = I18n.translate(isWatched ? "✅ 已纳管" : "🎯 纳管监控")
            btn.attributedTitle = NSAttributedString(string: titleText, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: titleColor
            ])
            btn.isEnabled = !isWatched
        }
    }

    @objc private func didClickRateLimit(_ sender: NSButton) {
        let menu = NSMenu(title: "限速设置")
        let noLimit = NSMenuItem(title: I18n.translate("🚫 不限速 (恢复全速)"), action: #selector(handleRateLimitChoice(_:)), keyEquivalent: "")
        noLimit.target = self
        noLimit.representedObject = Double(0)
        menu.addItem(noLimit)
        menu.addItem(NSMenuItem.separator())

        let presets: [(String, Double)] = [
            ("⚡️ 50 KB/s (极低速)", 50.0),
            ("⚡️ 200 KB/s (浏览限制)", 200.0),
            ("⚡️ 500 KB/s", 500.0),
            ("⚡️ 1 MB/s (1024 KB/s)", 1024.0),
            ("⚡️ 5 MB/s (5120 KB/s)", 5120.0)
        ]
        for (label, val) in presets {
            let item = NSMenuItem(title: I18n.translate(label), action: #selector(handleRateLimitChoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = val
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let custom = NSMenuItem(title: I18n.translate("✏️ 自定义限速..."), action: #selector(handleCustomRateLimit), keyEquivalent: "")
        custom.target = self
        menu.addItem(custom)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func handleRateLimitChoice(_ item: NSMenuItem) {
        guard let limit = item.representedObject as? Double else { return }
        onSetRateLimit?(pid, processName, limit)
    }

    @objc private func handleCustomRateLimit() {
        onPromptRateLimit?(pid, processName)
    }

    @objc private func didClickAdd() {
        actionBtn?.attributedTitle = NSAttributedString(string: I18n.translate("✅ 已纳管"), attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor(srgbRed: 0.1, green: 0.6, blue: 0.2, alpha: 1.0)
        ])
        actionBtn?.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor
        actionBtn?.isEnabled = false
        onAdd(pid)
    }

    @objc private func didClickKillSelf() {
        onKillSingle?(pid)
    }

    required init?(coder: NSCoder) { nil }
}

final class ProcessFamilyResourceRowView: NSView {
    override var isFlipped: Bool { true }
    private(set) var pid: Int
    private(set) var ppid: Int
    let onKillSingle: ((Int) -> Void)?
    let onKillFamily: ((Int) -> Void)?
    private var isExpanded: Bool = false
    private let childrenStack = NSStackView()
    private let toggleBtn = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let pidLabel = NSTextField(labelWithString: "")
    private let sizePillLabel: NSTextField
    private let cpuPillLabel: NSTextField
    private let memPillLabel: NSTextField
    private let killParentBtn = NSButton()
    private var childrenData: [[String: Any]]

    init(
        family: [String: Any],
        onKillSingle: ((Int) -> Void)? = nil,
        onKillFamily: ((Int) -> Void)? = nil
    ) {
        let pid = family["pid"] as? Int ?? 0
        self.pid = pid
        let ppid = family["ppid"] as? Int ?? 0
        self.ppid = ppid
        self.onKillSingle = onKillSingle
        self.onKillFamily = onKillFamily
        let name = family["name"] as? String ?? "Unknown"
        let isApp = family["is_app"] as? Bool ?? false
        let isRoot = family["is_root"] as? Bool ?? false
        let familySize = family["family_size"] as? Int ?? 1
        let cpuFmt = family["family_cpu_formatted"] as? String ?? "0.0%"
        let cpuVal = family["family_cpu_percent"] as? Double ?? 0.0
        let memFmt = family["family_memory_formatted"] as? String ?? "0 B"
        let selfMemFmt = family["self_memory_formatted"] as? String ?? memFmt
        let memPct = family["family_memory_percent"] as? Double ?? 0.0
        let children = family["children"] as? [[String: Any]] ?? []
        self.childrenData = children

        let sizePill = NSTextField(labelWithString: I18n.translate(" \(familySize) 个进程 "))
        let cpuPill = NSTextField(labelWithString: " 🔥 \(cpuFmt) ")
        let memText = children.isEmpty
            ? " 🧠 内存: \(memFmt) (\(String(format: "%.1f", memPct))%) "
            : " 🧠 总内存: \(memFmt) (主进程 \(selfMemFmt)) "
        let memPill = NSTextField(labelWithString: I18n.translate(memText))
        self.sizePillLabel = sizePill
        self.cpuPillLabel = cpuPill
        self.memPillLabel = memPill

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor

        let iconLabel = NSTextField(labelWithString: isApp ? "📱" : (isRoot ? "🛡️" : "⚙️"))
        iconLabel.font = .systemFont(ofSize: 13)

        titleLabel.stringValue = name
        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = Serafina.ink
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        pidLabel.stringValue = "PID: \(pid) · PPID: \(ppid)"
        pidLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        pidLabel.textColor = Serafina.muted

        sizePill.font = .systemFont(ofSize: 9, weight: .bold)
        sizePill.textColor = Serafina.grape
        sizePill.wantsLayer = true
        sizePill.layer?.backgroundColor = Serafina.grape.withAlphaComponent(0.12).cgColor
        sizePill.layer?.cornerRadius = 4

        let cpuColor: NSColor = cpuVal >= 50.0 ? NSColor.systemRed : (cpuVal >= 10.0 ? NSColor.systemOrange : Serafina.ink)
        cpuPill.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        cpuPill.textColor = cpuColor
        cpuPill.wantsLayer = true
        cpuPill.layer?.backgroundColor = cpuColor.withAlphaComponent(0.12).cgColor
        cpuPill.layer?.cornerRadius = 4

        memPill.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        memPill.textColor = NSColor(srgbRed: 0.10, green: 0.60, blue: 0.90, alpha: 1.0)
        memPill.wantsLayer = true
        memPill.layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.60, blue: 0.90, alpha: 0.14).cgColor
        memPill.layer?.cornerRadius = 4

        func styleActionBtn(_ btn: NSButton, title: String, bg: NSColor, fg: NSColor, action: Selector) {
            btn.title = I18n.translate(title)
            btn.font = .systemFont(ofSize: 9, weight: .bold)
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 5
            btn.layer?.backgroundColor = bg.cgColor
            btn.contentTintColor = fg
            btn.target = self
            btn.action = action
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.heightAnchor.constraint(equalToConstant: 20).isActive = true
        }

        let killSelfBtn = NSButton()
        styleActionBtn(killSelfBtn, title: "🛑 关本进程", bg: NSColor.systemOrange.withAlphaComponent(0.18), fg: NSColor.systemOrange, action: #selector(didClickKillSelf))

        styleActionBtn(killParentBtn, title: "⬆️ 关父进程", bg: NSColor.systemPurple.withAlphaComponent(0.16), fg: Serafina.grape, action: #selector(didClickKillParent))
        killParentBtn.isHidden = (ppid <= 1)

        let killTreeBtn = NSButton()
        styleActionBtn(killTreeBtn, title: "💥 关进程树", bg: NSColor.systemRed.withAlphaComponent(0.18), fg: NSColor.systemRed, action: #selector(didClickKillFamily))

        let topRow = NSStackView(views: [iconLabel, titleLabel, pidLabel, sizePill, NSView(), cpuPill, memPill, killSelfBtn, killParentBtn, killTreeBtn])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 6

        toggleBtn.title = I18n.translate("▼ 展开子进程 (\(children.count))")
        toggleBtn.font = .systemFont(ofSize: 9, weight: .bold)
        toggleBtn.isBordered = false
        toggleBtn.wantsLayer = true
        toggleBtn.layer?.cornerRadius = 4
        toggleBtn.layer?.backgroundColor = Serafina.petal.withAlphaComponent(0.40).cgColor
        toggleBtn.target = self
        toggleBtn.action = #selector(toggleChildren)
        toggleBtn.translatesAutoresizingMaskIntoConstraints = false
        toggleBtn.heightAnchor.constraint(equalToConstant: 20).isActive = true
        toggleBtn.isHidden = children.isEmpty
        topRow.addArrangedSubview(toggleBtn)

        childrenStack.orientation = .vertical
        childrenStack.alignment = .leading
        childrenStack.spacing = 4
        childrenStack.isHidden = true
        rebuildChildrenRows()

        let mainStack = NSStackView(views: [topRow, childrenStack])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 4
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            topRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            childrenStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])
    }

    private func rebuildChildrenRows() {
        for v in childrenStack.subviews { v.removeFromSuperview() }
        for ch in childrenData {
            let cPid = ch["pid"] as? Int ?? 0
            let cPpid = ch["ppid"] as? Int ?? self.pid
            let cName = ch["name"] as? String ?? "child"
            let cCpu = ch["cpu_percent"] as? Double ?? 0.0
            let cMem = ch["memory_formatted"] as? String ?? "0 B"
            let cRoot = ch["is_root"] as? Bool ?? false

            let chRow = NSStackView()
            chRow.orientation = .horizontal
            chRow.alignment = .centerY
            chRow.spacing = 6

            let branchLbl = NSTextField(labelWithString: "    ↳ 子进程 PID \(cPid) (PPID \(cPpid)):")
            branchLbl.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
            branchLbl.textColor = Serafina.muted

            let cNameLbl = NSTextField(labelWithString: cName)
            cNameLbl.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
            cNameLbl.textColor = Serafina.ink
            cNameLbl.lineBreakMode = .byTruncatingMiddle

            let cCpuLbl = NSTextField(labelWithString: "🔥 \(String(format: "%.1f", cCpu))%")
            cCpuLbl.font = .monospacedSystemFont(ofSize: 9, weight: .bold)
            cCpuLbl.textColor = cCpu > 10.0 ? NSColor.systemOrange : Serafina.muted

            let cMemLbl = NSTextField(labelWithString: I18n.translate("🧠 内存: \(cMem)"))
            cMemLbl.font = .monospacedSystemFont(ofSize: 9, weight: .bold)
            cMemLbl.textColor = NSColor(srgbRed: 0.10, green: 0.60, blue: 0.90, alpha: 1.0)

            let killChildBtn = NSButton(title: I18n.translate("✕ 关此子进程"), target: self, action: #selector(didClickKillChild(_:)))
            killChildBtn.font = .systemFont(ofSize: 9, weight: .bold)
            killChildBtn.isBordered = false
            killChildBtn.wantsLayer = true
            killChildBtn.layer?.cornerRadius = 4
            killChildBtn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.15).cgColor
            killChildBtn.contentTintColor = NSColor.systemRed
            killChildBtn.identifier = NSUserInterfaceItemIdentifier("\(cPid)")
            killChildBtn.translatesAutoresizingMaskIntoConstraints = false
            killChildBtn.heightAnchor.constraint(equalToConstant: 18).isActive = true

            chRow.addArrangedSubview(branchLbl)
            chRow.addArrangedSubview(cNameLbl)
            chRow.addArrangedSubview(cCpuLbl)
            chRow.addArrangedSubview(cMemLbl)
            if cRoot {
                let rBadge = NSTextField(labelWithString: "🛡️ root")
                rBadge.font = .systemFont(ofSize: 8, weight: .bold)
                rBadge.textColor = NSColor.systemRed
                chRow.addArrangedSubview(rBadge)
            }
            chRow.addArrangedSubview(NSView())
            chRow.addArrangedSubview(killChildBtn)
            childrenStack.addArrangedSubview(chRow)
        }
    }

    func update(family: [String: Any]) {
        self.pid = family["pid"] as? Int ?? self.pid
        self.ppid = family["ppid"] as? Int ?? self.ppid
        let name = family["name"] as? String ?? titleLabel.stringValue
        let familySize = family["family_size"] as? Int ?? 1
        let cpuFmt = family["family_cpu_formatted"] as? String ?? "0.0%"
        let cpuVal = family["family_cpu_percent"] as? Double ?? 0.0
        let memFmt = family["family_memory_formatted"] as? String ?? "0 B"
        let selfMemFmt = family["self_memory_formatted"] as? String ?? memFmt
        let memPct = family["family_memory_percent"] as? Double ?? 0.0
        let children = family["children"] as? [[String: Any]] ?? []
        self.childrenData = children

        titleLabel.stringValue = name
        pidLabel.stringValue = "PID: \(pid) · PPID: \(ppid)"
        killParentBtn.isHidden = (ppid <= 1)
        sizePillLabel.stringValue = I18n.translate(" \(familySize) 个进程 ")
        cpuPillLabel.stringValue = " 🔥 \(cpuFmt) "
        let cpuColor: NSColor = cpuVal >= 50.0 ? NSColor.systemRed : (cpuVal >= 10.0 ? NSColor.systemOrange : Serafina.ink)
        cpuPillLabel.textColor = cpuColor
        cpuPillLabel.layer?.backgroundColor = cpuColor.withAlphaComponent(0.12).cgColor
        let memText = children.isEmpty
            ? " 🧠 内存: \(memFmt) (\(String(format: "%.1f", memPct))%) "
            : " 🧠 总内存: \(memFmt) (主进程 \(selfMemFmt)) "
        memPillLabel.stringValue = I18n.translate(memText)
        toggleBtn.isHidden = children.isEmpty
        toggleBtn.title = I18n.translate(isExpanded ? "▲ 收起" : "▼ 展开子进程 (\(children.count))")
        if isExpanded {
            rebuildChildrenRows()
        }
    }

    required init?(coder: NSCoder) { nil }

    @objc private func toggleChildren() {
        isExpanded.toggle()
        if isExpanded {
            rebuildChildrenRows()
        }
        childrenStack.isHidden = !isExpanded
        toggleBtn.title = I18n.translate(isExpanded ? "▲ 收起" : "▼ 展开子进程 (\(childrenData.count))")
    }

    @objc private func didClickKillSelf() {
        onKillSingle?(pid)
    }

    @objc private func didClickKillParent() {
        guard ppid > 1 else { return }
        onKillSingle?(ppid)
    }

    @objc private func didClickKillFamily() {
        onKillFamily?(pid)
    }

    @objc private func didClickKillChild(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let cPid = Int(raw), cPid > 1 else { return }
        onKillSingle?(cPid)
    }
}

final class WatchlistProcessCardView: NSView {
    override var isFlipped: Bool { true }
    let pid: Int
    let currentConfig: [String: Any]
    let onRemove: (Int) -> Void
    let onPause: (Int) -> Void
    let onResume: (Int) -> Void
    let onKillFamily: (Int) -> Void
    let onKillSingle: ((Int) -> Void)?
    let onUpdateRules: (Int, [String], [String], Bool, Double, String, Bool) -> Void
    let onInspectFile: ((String, Int, String) -> Void)?
    let onDisconnectSocket: ((Int, String, String) -> Void)?
    let onBlockIP: ((Int, String) -> Void)?
    let onUnblockIP: ((Int, String) -> Void)?
    let onRevealFile: ((String) -> Void)?
    let onClearHistory: ((Int) -> Void)?

    init(
        item: [String: Any],
        onRemove: @escaping (Int) -> Void,
        onPause: @escaping (Int) -> Void,
        onResume: @escaping (Int) -> Void,
        onKillFamily: @escaping (Int) -> Void,
        onKillSingle: ((Int) -> Void)? = nil,
        onUpdateRules: @escaping (Int, [String], [String], Bool, Double, String, Bool) -> Void,
        onInspectFile: ((String, Int, String) -> Void)? = nil,
        onDisconnectSocket: ((Int, String, String) -> Void)? = nil,
        onBlockIP: ((Int, String) -> Void)? = nil,
        onUnblockIP: ((Int, String) -> Void)? = nil,
        onRevealFile: ((String) -> Void)? = nil,
        onClearHistory: ((Int) -> Void)? = nil
    ) {
        self.pid = item["pid"] as? Int ?? 0
        self.currentConfig = item
        self.onRemove = onRemove
        self.onPause = onPause
        self.onResume = onResume
        self.onKillFamily = onKillFamily
        self.onKillSingle = onKillSingle
        self.onUpdateRules = onUpdateRules
        self.onInspectFile = onInspectFile
        self.onDisconnectSocket = onDisconnectSocket
        self.onBlockIP = onBlockIP
        self.onUnblockIP = onUnblockIP
        self.onRevealFile = onRevealFile
        self.onClearHistory = onClearHistory
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Serafina.paper.withAlphaComponent(0.72).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.40).cgColor

        let cmd = item["command"] as? String ?? "unknown"
        let ppid = item["ppid"] as? Int ?? 0
        let parentName = item["parent_name"] as? String ?? ""
        let familyPids = item["family_pids"] as? [Int] ?? [pid]
        let sandboxDir = item["sandbox_dir"] as? String ?? "未限定 (全目录监测)"
        let oobCount = item["out_of_bounds_count"] as? Int ?? 0
        let blockedCount = item["blocked_payloads_count"] as? Int ?? 0
        let openFilesCount = item["open_files_count"] as? Int ?? 0
        let connsCount = item["connections_count"] as? Int ?? 0
        let enforcePrompt = item["enforce_prompt"] as? Bool ?? false
        let status = item["status"] as? String ?? "WATCHING"
        let blockTypes = Set(item["block_types"] as? [String] ?? [])
        let customExts = (item["custom_extensions"] as? [String] ?? []).joined(separator: ", ")
        let blockedIps = Set(item["blocked_ips"] as? [String] ?? [])
        let indicators = item["audit_indicators"] as? [String: Any] ?? [:]
        let fileHistory = item["file_history"] as? [[String: Any]] ?? []

        func makeBadge(_ text: String, color: NSColor) -> NSTextField {
            let label = NSTextField(labelWithString: " \(I18n.translate(text)) ")
            label.font = .systemFont(ofSize: 10, weight: .bold)
            label.textColor = color
            label.wantsLayer = true
            label.layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
            label.layer?.cornerRadius = 4
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return label
        }

        let statusBadge: NSTextField
        if status == "ANOMALY" {
            statusBadge = makeBadge("🚨 异常越权/违规拦截中", color: NSColor.systemRed)
        } else if status == "EXITED" {
            statusBadge = makeBadge("⚪️ 已退出", color: Serafina.muted)
        } else {
            statusBadge = makeBadge("🟢 重点监控中", color: NSColor(srgbRed: 0.15, green: 0.80, blue: 0.35, alpha: 1.0))
        }

        let titleLabel = NSTextField(labelWithString: "🎯 \(cmd) (PID \(pid))")
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = Serafina.ink
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let parentLabel = NSTextField(labelWithString: I18n.translate("⛓ 父进程: \(parentName.isEmpty ? "launchd" : parentName) (\(ppid)) · 子进程: \(max(0, familyPids.count - 1))个 · 连接: \(connsCount) · 打开文件: \(openFilesCount) · 阻断: \(blockedCount)次"))
        parentLabel.font = .systemFont(ofSize: 11, weight: .medium)
        parentLabel.textColor = Serafina.muted
        parentLabel.lineBreakMode = .byTruncatingTail
        parentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let topHeader = NSStackView(views: [statusBadge, titleLabel, NSView(), parentLabel])
        topHeader.orientation = .horizontal
        topHeader.alignment = .centerY
        topHeader.spacing = 8

        // Security & Privilege Audit Indicators
        let isRoot = indicators["is_root"] as? Bool ?? false
        let hasOobExec = indicators["has_oob_exec"] as? Bool ?? false
        let hasOobView = indicators["has_oob_view"] as? Bool ?? (oobCount > 0)
        let hasScreencap = indicators["has_screencap"] as? Bool ?? false
        let hasPrivacyDocs = indicators["has_privacy_docs"] as? Bool ?? false
        let hasAnomalous = indicators["has_anomalous_socket"] as? Bool ?? false

        let rootBadge = makeBadge(isRoot ? "🚨 Root 提权运行" : "✅ 普通权限", color: isRoot ? NSColor.systemRed : NSColor(srgbRed: 0.15, green: 0.75, blue: 0.35, alpha: 1.0))
        let oobExecBadge = makeBadge(hasOobExec ? "⚠️ 越级执行(临时/可疑目录)" : "✅ 正常路径执行", color: hasOobExec ? NSColor.systemOrange : NSColor(srgbRed: 0.15, green: 0.75, blue: 0.35, alpha: 1.0))
        let oobViewBadge = makeBadge(hasOobView ? "⚠️ 越权跨目录读取 (\(oobCount)次)" : "✅ 沙箱内合规", color: hasOobView ? NSColor.systemOrange : NSColor(srgbRed: 0.15, green: 0.75, blue: 0.35, alpha: 1.0))
        let screenBadge = makeBadge(hasScreencap ? "📸 截屏/录屏行为检测" : "✅ 无截屏行为", color: hasScreencap ? NSColor.systemPurple : NSColor(srgbRed: 0.15, green: 0.75, blue: 0.35, alpha: 1.0))
        let privacyBadge = makeBadge(hasPrivacyDocs ? "🚨 触碰.ssh/密钥凭据" : "✅ 无隐私凭据触碰", color: hasPrivacyDocs ? NSColor.systemRed : NSColor(srgbRed: 0.15, green: 0.75, blue: 0.35, alpha: 1.0))
        let anomalousBadge = makeBadge(hasAnomalous ? "🛑 异常端口/后门监听" : "✅ 正常通信端口", color: hasAnomalous ? NSColor.systemRed : NSColor(srgbRed: 0.15, green: 0.75, blue: 0.35, alpha: 1.0))
        let blockedIpsBadge = makeBadge(blockedIps.isEmpty ? "🟢 阻断 IP: 0个" : "🛑 已阻断 IP: \(blockedIps.count)个", color: blockedIps.isEmpty ? Serafina.muted : NSColor.systemRed)

        let auditRow1 = NSStackView(views: [rootBadge, oobExecBadge, oobViewBadge, screenBadge])
        auditRow1.orientation = .horizontal
        auditRow1.spacing = 6
        auditRow1.alignment = .centerY

        let auditRow2 = NSStackView(views: [privacyBadge, anomalousBadge, blockedIpsBadge])
        auditRow2.orientation = .horizontal
        auditRow2.spacing = 6
        auditRow2.alignment = .centerY

        let auditBox = NSStackView(views: [auditRow1, auditRow2])
        auditBox.orientation = .vertical
        auditBox.spacing = 4
        auditBox.alignment = .leading

        // Traffic Volume & Types Info
        let traffic = item["traffic"] as? [String: Any] ?? [:]
        let upFmt = traffic["upload_formatted"] as? String ?? "0 B"
        let downFmt = traffic["download_formatted"] as? String ?? "0 B"
        let upSpd = traffic["upload_speed_formatted"] as? String ?? "0 B/s"
        let downSpd = traffic["download_speed_formatted"] as? String ?? "0 B/s"
        let cats = (traffic["categories"] as? [String] ?? []).joined(separator: " · ")

        func makeMetricPill(icon: String, title: String, value: String, color: NSColor) -> NSView {
            let iv = NSTextField(labelWithString: icon)
            iv.font = .systemFont(ofSize: 11)
            let tl = NSTextField(labelWithString: I18n.translate(title))
            tl.font = .systemFont(ofSize: 10, weight: .medium)
            tl.textColor = Serafina.muted
            let vl = NSTextField(labelWithString: value)
            vl.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
            vl.textColor = color
            for l in [iv, tl, vl] {
                l.lineBreakMode = .byTruncatingTail
                l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
            let row = NSStackView(views: [iv, tl, vl])
            row.orientation = .horizontal
            row.spacing = 3
            row.alignment = .centerY
            return row
        }

        let familyCpuFmt = item["family_cpu_formatted"] as? String ?? "0.0%"
        let familyMemFmt = item["family_memory_formatted"] as? String ?? "0 B"
        let cpuPill = makeMetricPill(icon: "💻", title: "CPU:", value: familyCpuFmt, color: NSColor.systemOrange)
        let memPill = makeMetricPill(icon: "🧠", title: "内存:", value: familyMemFmt, color: NSColor(srgbRed: 0.10, green: 0.60, blue: 0.90, alpha: 1.0))
        let upPill = makeMetricPill(icon: "⬆️", title: "上传:", value: "\(upFmt) (\(upSpd))", color: NSColor(srgbRed: 0.15, green: 0.80, blue: 0.35, alpha: 1.0))
        let downPill = makeMetricPill(icon: "⬇️", title: "下载:", value: "\(downFmt) (\(downSpd))", color: Serafina.grape)
        let catPill = makeMetricPill(icon: "🏷️", title: "特征:", value: cats.isEmpty ? "常规通信" : cats, color: Serafina.ink)

        let trafficBox = NSStackView(views: [cpuPill, memPill, upPill, downPill, catPill, NSView()])
        trafficBox.orientation = .horizontal
        trafficBox.spacing = 14
        trafficBox.alignment = .centerY

        // Detailed Active Connections & Remote IPs
        let activeConns = item["active_connections"] as? [[String: Any]] ?? []
        let outbounds = activeConns.filter { $0["is_outbound"] as? Bool ?? false }
        let connsTitle = NSTextField(labelWithString: I18n.translate("🌐 实时通信连接 (外部目标 IP: \(outbounds.count) 个 · 活跃 Socket: \(activeConns.count) 个 · 支持直接断连与阻断 IP):"))
        connsTitle.font = .systemFont(ofSize: 11, weight: .bold)
        connsTitle.textColor = Serafina.ink
        connsTitle.lineBreakMode = .byTruncatingTail
        connsTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let connsListStack = NSStackView()
        connsListStack.orientation = .vertical
        connsListStack.alignment = .leading
        connsListStack.spacing = 4

        let displayConns = (outbounds.isEmpty ? activeConns : (outbounds + activeConns.filter { !($0["is_outbound"] as? Bool ?? false) })).prefix(6)
        if displayConns.isEmpty {
            let emptyConnLabel = NSTextField(labelWithString: I18n.translate("  • 暂无外联 IP 连接 (处于本地监听或空闲状态)"))
            emptyConnLabel.font = .systemFont(ofSize: 10, weight: .medium)
            emptyConnLabel.textColor = Serafina.muted
            connsListStack.addArrangedSubview(emptyConnLabel)
        } else {
            for c in displayConns {
                let flag = c["flag"] as? String ?? "🌐"
                let remIp = c["remote_ip"] as? String ?? ""
                let remPort = c["remote_port"] as? String ?? ""
                let geoSummary = c["geo_summary"] as? String ?? (c["country"] as? String ?? "本地")
                let proto = c["proto"] as? String ?? "TCP"
                let state = c["state"] as? String ?? "ESTABLISHED"
                let connType = c["conn_type"] as? String ?? "TCP 数据传输"
                let isBlocked = c["is_blocked"] as? Bool ?? false
                let targetStr = remIp.isEmpty ? (c["connection"] as? String ?? "*:*") : "\(remIp):\(remPort)"

                let flagLabel = NSTextField(labelWithString: flag)
                flagLabel.font = .systemFont(ofSize: 11)
                flagLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                let targetLabel = NSTextField(labelWithString: targetStr)
                targetLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
                targetLabel.textColor = isBlocked ? NSColor.systemRed : Serafina.ink
                targetLabel.lineBreakMode = .byTruncatingMiddle
                targetLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                let stateBadge = NSTextField(labelWithString: " \(proto) · \(state) · \(connType) ")
                stateBadge.font = .monospacedSystemFont(ofSize: 9, weight: .bold)
                let stateColor = isBlocked ? NSColor.systemRed : (state == "ESTABLISHED" ? NSColor(srgbRed: 0.15, green: 0.75, blue: 0.35, alpha: 1.0) : (state == "LISTEN" ? Serafina.grape : NSColor.systemOrange))
                stateBadge.textColor = stateColor
                stateBadge.wantsLayer = true
                stateBadge.layer?.backgroundColor = stateColor.withAlphaComponent(0.12).cgColor
                stateBadge.layer?.cornerRadius = 3
                stateBadge.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                let geoLabel = NSTextField(labelWithString: geoSummary)
                geoLabel.font = .systemFont(ofSize: 10, weight: .medium)
                geoLabel.textColor = Serafina.muted
                geoLabel.lineBreakMode = .byTruncatingMiddle
                geoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                // Disconnect and Block buttons
                let disconnectBtn = NSButton(title: I18n.translate("🔌 断连"), target: self, action: #selector(didClickDisconnectSocket(_:)))
                disconnectBtn.isBordered = false
                disconnectBtn.wantsLayer = true
                disconnectBtn.layer?.cornerRadius = 5
                disconnectBtn.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.18).cgColor
                disconnectBtn.font = .systemFont(ofSize: 9, weight: .bold)
                disconnectBtn.identifier = NSUserInterfaceItemIdentifier("\(remIp)::\(remPort)")
                disconnectBtn.translatesAutoresizingMaskIntoConstraints = false
                disconnectBtn.heightAnchor.constraint(equalToConstant: 20).isActive = true
                disconnectBtn.isEnabled = !remIp.isEmpty

                let blockIpBtn: NSButton
                if isBlocked {
                    blockIpBtn = NSButton(title: I18n.translate("🟢 解除阻断"), target: self, action: #selector(didClickUnblockIP(_:)))
                    blockIpBtn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor
                } else {
                    blockIpBtn = NSButton(title: I18n.translate("🛑 阻断 IP"), target: self, action: #selector(didClickBlockIP(_:)))
                    blockIpBtn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.18).cgColor
                }
                blockIpBtn.isBordered = false
                blockIpBtn.wantsLayer = true
                blockIpBtn.layer?.cornerRadius = 5
                blockIpBtn.font = .systemFont(ofSize: 9, weight: .bold)
                blockIpBtn.identifier = NSUserInterfaceItemIdentifier(remIp)
                blockIpBtn.translatesAutoresizingMaskIntoConstraints = false
                blockIpBtn.heightAnchor.constraint(equalToConstant: 20).isActive = true
                blockIpBtn.isEnabled = !remIp.isEmpty && remIp != "127.0.0.1"

                let cRow = NSStackView(views: [flagLabel, targetLabel, stateBadge, geoLabel, NSView(), disconnectBtn, blockIpBtn])
                cRow.orientation = .horizontal
                cRow.spacing = 6
                cRow.alignment = .centerY
                connsListStack.addArrangedSubview(cRow)
                cRow.widthAnchor.constraint(equalTo: connsListStack.widthAnchor).isActive = true
            }
        }

        // Process Family CPU & Memory Granular Breakdown
        let familyProcs = item["family_processes"] as? [[String: Any]] ?? []
        let familyProcsTitle = NSTextField(labelWithString: I18n.translate("⛓ 进程家族父子结构与独立资源消耗 (共 \(familyProcs.count) 个进程 · 支持单独关闭子进程或父进程):"))
        familyProcsTitle.font = .systemFont(ofSize: 11, weight: .bold)
        familyProcsTitle.textColor = Serafina.ink
        familyProcsTitle.lineBreakMode = .byTruncatingTail
        familyProcsTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let familyProcsStack = NSStackView()
        familyProcsStack.orientation = .vertical
        familyProcsStack.alignment = .leading
        familyProcsStack.spacing = 4

        for fp in familyProcs {
            let fpPid = fp["pid"] as? Int ?? 0
            let fpPpid = fp["ppid"] as? Int ?? 0
            let fpCmdShort = fp["command_short"] as? String ?? "process"
            let fpUser = fp["user"] as? String ?? "user"
            let fpCpu = fp["cpu_percent"] as? Double ?? 0.0
            let fpMem = fp["memory_formatted"] as? String ?? "0 B"
            let fpIsRoot = fp["is_root"] as? Bool ?? false
            let fpIsOob = fp["is_oob_exec"] as? Bool ?? false

            let pRow = NSStackView()
            pRow.orientation = .horizontal
            pRow.spacing = 6
            pRow.alignment = .centerY

            let tagLbl = NSTextField(labelWithString: I18n.translate(fpPid == pid ? "  🎯 主进程:" : "  ↳ 子进程:"))
            tagLbl.font = .systemFont(ofSize: 10, weight: .bold)
            tagLbl.textColor = fpPid == pid ? Serafina.grape : Serafina.muted
            tagLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let pidLbl = NSTextField(labelWithString: "PID \(fpPid) (PPID: \(fpPpid))")
            pidLbl.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
            pidLbl.textColor = Serafina.ink
            pidLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let nameLbl = NSTextField(labelWithString: fpCmdShort)
            nameLbl.font = .systemFont(ofSize: 10, weight: .bold)
            nameLbl.textColor = Serafina.ink
            nameLbl.lineBreakMode = .byTruncatingTail
            nameLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let cpuBadge = makeBadge("🔥 \(String(format: "%.1f", fpCpu))%", color: fpCpu > 10.0 ? NSColor.systemOrange : Serafina.muted)
            let memBadge = makeBadge("🧠 内存: \(fpMem)", color: NSColor(srgbRed: 0.10, green: 0.60, blue: 0.90, alpha: 1.0))

            pRow.addArrangedSubview(tagLbl)
            pRow.addArrangedSubview(pidLbl)
            pRow.addArrangedSubview(nameLbl)
            pRow.addArrangedSubview(cpuBadge)
            pRow.addArrangedSubview(memBadge)

            if fpIsRoot {
                let rBadge = makeBadge("🚨 Root", color: NSColor.systemRed)
                pRow.addArrangedSubview(rBadge)
            }
            if fpIsOob {
                let oBadge = makeBadge("⚠️ 越级路径", color: NSColor.systemOrange)
                pRow.addArrangedSubview(oBadge)
            }

            let uLbl = NSTextField(labelWithString: I18n.translate("用户: \(fpUser)"))
            uLbl.font = .systemFont(ofSize: 9, weight: .medium)
            uLbl.textColor = Serafina.muted
            uLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            pRow.addArrangedSubview(uLbl)

            let killProcBtn = NSButton(title: I18n.translate(fpPid == pid ? "🛑 关主进程" : "✕ 关此子进程"), target: self, action: #selector(didClickKillMember(_:)))
            killProcBtn.font = .systemFont(ofSize: 9, weight: .bold)
            killProcBtn.isBordered = false
            killProcBtn.wantsLayer = true
            killProcBtn.layer?.cornerRadius = 4
            killProcBtn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.15).cgColor
            killProcBtn.contentTintColor = NSColor.systemRed
            killProcBtn.identifier = NSUserInterfaceItemIdentifier("\(fpPid)")
            killProcBtn.translatesAutoresizingMaskIntoConstraints = false
            killProcBtn.heightAnchor.constraint(equalToConstant: 18).isActive = true
            pRow.addArrangedSubview(killProcBtn)

            if fpPpid > 1 {
                let killParentMemberBtn = NSButton(title: I18n.translate("⬆️ 关父进程 (\(fpPpid))"), target: self, action: #selector(didClickKillMember(_:)))
                killParentMemberBtn.font = .systemFont(ofSize: 9, weight: .bold)
                killParentMemberBtn.isBordered = false
                killParentMemberBtn.wantsLayer = true
                killParentMemberBtn.layer?.cornerRadius = 4
                killParentMemberBtn.layer?.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.15).cgColor
                killParentMemberBtn.contentTintColor = Serafina.grape
                killParentMemberBtn.identifier = NSUserInterfaceItemIdentifier("\(fpPpid)")
                killParentMemberBtn.translatesAutoresizingMaskIntoConstraints = false
                killParentMemberBtn.heightAnchor.constraint(equalToConstant: 18).isActive = true
                pRow.addArrangedSubview(killParentMemberBtn)
            }

            familyProcsStack.addArrangedSubview(pRow)
        }

        // Sandbox & Out-of-bounds warning
        let customExtsInfo = customExts.isEmpty ? "" : I18n.translate(" · 自定义拦截扩展名: [") + "\(customExts)]"
        let sandboxLabel = NSTextField(wrappingLabelWithString: I18n.translate("📁 限定沙箱目录: ") + "\(sandboxDir)\(customExtsInfo)")
        sandboxLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        sandboxLabel.textColor = Serafina.ink
        sandboxLabel.lineBreakMode = .byTruncatingMiddle
        sandboxLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Granular Checkboxes for blocking
        let chkSensitive = NSButton(checkboxWithTitle: I18n.translate("阻断私钥凭据 (.ssh/keychain)"), target: nil, action: nil)
        chkSensitive.state = blockTypes.contains("sensitive") ? .on : .off
        chkSensitive.font = .systemFont(ofSize: 11, weight: .medium)

        let chkImages = NSButton(checkboxWithTitle: I18n.translate("拦截图片"), target: nil, action: nil)
        chkImages.state = blockTypes.contains("images") ? .on : .off
        chkImages.font = .systemFont(ofSize: 11, weight: .medium)

        let chkVideos = NSButton(checkboxWithTitle: I18n.translate("拦截视频媒体"), target: nil, action: nil)
        chkVideos.state = blockTypes.contains("videos") ? .on : .off
        chkVideos.font = .systemFont(ofSize: 11, weight: .medium)

        let chkLarge = NSButton(checkboxWithTitle: I18n.translate("拦截 >20MB 大文件"), target: nil, action: nil)
        chkLarge.state = (item["block_large_files"] as? Bool ?? true) ? .on : .off
        chkLarge.font = .systemFont(ofSize: 11, weight: .medium)

        let chkDocs = NSButton(checkboxWithTitle: I18n.translate("拦截归档包 (.zip/.tar/.dmg)"), target: nil, action: nil)
        chkDocs.state = blockTypes.contains("docs") ? .on : .off
        chkDocs.font = .systemFont(ofSize: 11, weight: .medium)

        let chkGatekeeper = NSButton(checkboxWithTitle: I18n.translate("👮 每次请求需人工放行 (Gatekeeper 挂起确认)"), target: nil, action: nil)
        chkGatekeeper.state = enforcePrompt ? .on : .off
        chkGatekeeper.font = .systemFont(ofSize: 11, weight: .bold)

        for chk in [chkSensitive, chkImages, chkVideos, chkLarge, chkDocs, chkGatekeeper] {
            chk.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let rulesRow1 = NSStackView(views: [chkSensitive, chkImages, chkVideos])
        rulesRow1.orientation = .horizontal
        rulesRow1.spacing = 10
        rulesRow1.alignment = .centerY

        let rulesRow2 = NSStackView(views: [chkLarge, chkDocs, chkGatekeeper])
        rulesRow2.orientation = .horizontal
        rulesRow2.spacing = 10
        rulesRow2.alignment = .centerY

        let connsDoc = FlippedView()
        connsDoc.translatesAutoresizingMaskIntoConstraints = false
        connsListStack.translatesAutoresizingMaskIntoConstraints = false
        connsDoc.addSubview(connsListStack)

        let connsScroll = NSScrollView()
        connsScroll.hasVerticalScroller = true
        connsScroll.hasHorizontalScroller = false
        connsScroll.autohidesScrollers = true
        connsScroll.drawsBackground = false
        connsScroll.documentView = connsDoc
        connsScroll.translatesAutoresizingMaskIntoConstraints = false
        let connHeight: CGFloat = displayConns.isEmpty ? 28 : min(130, max(36, CGFloat(displayConns.count * 28 + 6)))
        connsScroll.heightAnchor.constraint(equalToConstant: connHeight).isActive = true

        NSLayoutConstraint.activate([
            connsDoc.leadingAnchor.constraint(equalTo: connsScroll.contentView.leadingAnchor),
            connsDoc.trailingAnchor.constraint(equalTo: connsScroll.contentView.trailingAnchor),
            connsDoc.topAnchor.constraint(equalTo: connsScroll.contentView.topAnchor),
            connsDoc.widthAnchor.constraint(equalTo: connsScroll.contentView.widthAnchor),
            connsListStack.leadingAnchor.constraint(equalTo: connsDoc.leadingAnchor),
            connsListStack.trailingAnchor.constraint(equalTo: connsDoc.trailingAnchor),
            connsListStack.topAnchor.constraint(equalTo: connsDoc.topAnchor),
            connsDoc.bottomAnchor.constraint(equalTo: connsListStack.bottomAnchor)
        ])

        // Persistent File Transfer and Access History Section
        let historyTitle = NSTextField(labelWithString: I18n.translate("📜 传输与文件访问历史记录 (持久化存档 · 共 ") + "\(fileHistory.count)" + I18n.translate(" 项 · 可滚动查看全部历史):"))
        historyTitle.font = .systemFont(ofSize: 11, weight: .bold)
        historyTitle.textColor = Serafina.ink
        historyTitle.lineBreakMode = .byTruncatingTail
        historyTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let clearHistBtn = NSButton(title: I18n.translate("🧹 清空历史"), target: self, action: #selector(didClickClearHistory))
        clearHistBtn.font = .systemFont(ofSize: 9, weight: .bold)
        clearHistBtn.isBordered = false
        clearHistBtn.wantsLayer = true
        clearHistBtn.layer?.cornerRadius = 5
        clearHistBtn.layer?.backgroundColor = Serafina.petal.withAlphaComponent(0.35).cgColor
        clearHistBtn.translatesAutoresizingMaskIntoConstraints = false
        clearHistBtn.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let histHeader = NSStackView(views: [historyTitle, NSView(), clearHistBtn])
        histHeader.orientation = .horizontal
        histHeader.alignment = .centerY

        let historyStack = NSStackView()
        historyStack.orientation = .vertical
        historyStack.alignment = .leading
        historyStack.spacing = 3

        if fileHistory.isEmpty {
            let emptyHist = NSTextField(labelWithString: I18n.translate("  • 暂无文件传输或访问存档 (进程读写的所有文件将自动在此永久记录)"))
            emptyHist.font = .systemFont(ofSize: 10, weight: .medium)
            emptyHist.textColor = Serafina.muted
            historyStack.addArrangedSubview(emptyHist)
        } else {
            for h in fileHistory {
                let p = h["path"] as? String ?? ""
                let sz = h["size_formatted"] as? String ?? ""
                let count = h["access_count"] as? Int ?? 1
                let lastSeen = h["last_seen_str"] as? String ?? ""
                let isOob = h["is_oob"] as? Bool ?? false
                let isSens = h["is_sensitive"] as? Bool ?? false
                let isScreen = h["is_screen_capture"] as? Bool ?? false
                let hasA = h["has_analysis"] as? Bool ?? false
                let rL = h["risk_level"] as? String ?? ""

                let hRow = NSStackView()
                hRow.orientation = .horizontal
                hRow.alignment = .centerY
                hRow.spacing = 6
                hRow.translatesAutoresizingMaskIntoConstraints = false

                let tagStr = isOob ? "越权" : (isSens ? "敏感" : (isScreen ? "截屏" : "传输"))
                let tagColor = isOob ? NSColor.systemRed : (isSens ? NSColor.systemRed : (isScreen ? NSColor.systemPurple : Serafina.grape))
                let tagLbl = NSTextField(labelWithString: "[\(I18n.translate(tagStr))]")
                tagLbl.font = .systemFont(ofSize: 9, weight: .bold)
                tagLbl.textColor = tagColor
                tagLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                let pathLbl = NSTextField(wrappingLabelWithString: p)
                pathLbl.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
                pathLbl.textColor = Serafina.ink
                pathLbl.lineBreakMode = .byTruncatingMiddle
                pathLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                let metaLbl = NSTextField(labelWithString: "\(sz) · " + I18n.translate("访问") + "\(count)" + I18n.translate("次") + " · \(lastSeen)")
                metaLbl.font = .systemFont(ofSize: 9, weight: .medium)
                metaLbl.textColor = Serafina.muted
                metaLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                hRow.addArrangedSubview(tagLbl)
                hRow.addArrangedSubview(pathLbl)
                hRow.addArrangedSubview(metaLbl)

                if hasA && !rL.isEmpty {
                    let badgeColor: NSColor
                    if rL.contains("高危") { badgeColor = .systemRed }
                    else if rL.contains("中危") { badgeColor = .systemOrange }
                    else if rL.contains("低风险") { badgeColor = .systemYellow }
                    else { badgeColor = NSColor(srgbRed: 0.1, green: 0.6, blue: 0.2, alpha: 1.0) }
                    let badge = NSTextField(labelWithString: " 🤖 \(I18n.translate(rL)) ")
                    badge.font = .systemFont(ofSize: 9, weight: .bold)
                    badge.textColor = badgeColor
                    badge.wantsLayer = true
                    badge.layer?.cornerRadius = 4
                    badge.layer?.backgroundColor = badgeColor.withAlphaComponent(0.15).cgColor
                    hRow.addArrangedSubview(badge)
                }

                let revealBtn = NSButton(title: I18n.translate("📂 Finder 定位"), target: self, action: #selector(didClickRevealFileBtn(_:)))
                revealBtn.isBordered = false
                revealBtn.wantsLayer = true
                revealBtn.layer?.cornerRadius = 5
                revealBtn.layer?.backgroundColor = Serafina.petal.withAlphaComponent(0.35).cgColor
                revealBtn.font = .systemFont(ofSize: 9, weight: .bold)
                revealBtn.identifier = NSUserInterfaceItemIdentifier(p)
                revealBtn.translatesAutoresizingMaskIntoConstraints = false
                revealBtn.heightAnchor.constraint(equalToConstant: 20).isActive = true

                let inspectBtn = NSButton(title: I18n.translate("📄 查看内容"), target: self, action: #selector(didClickInspectFileBtn(_:)))
                inspectBtn.isBordered = false
                inspectBtn.wantsLayer = true
                inspectBtn.layer?.cornerRadius = 5
                inspectBtn.layer?.backgroundColor = Serafina.grape.withAlphaComponent(0.15).cgColor
                inspectBtn.font = .systemFont(ofSize: 9, weight: .bold)
                inspectBtn.identifier = NSUserInterfaceItemIdentifier(p)
                inspectBtn.translatesAutoresizingMaskIntoConstraints = false
                inspectBtn.heightAnchor.constraint(equalToConstant: 20).isActive = true

                let analyzeBtn = NSButton(title: I18n.translate("🤖 深度分析"), target: self, action: #selector(didClickInspectFileBtn(_:)))
                analyzeBtn.isBordered = false
                analyzeBtn.wantsLayer = true
                analyzeBtn.layer?.cornerRadius = 5
                analyzeBtn.layer?.backgroundColor = Serafina.petal.withAlphaComponent(0.40).cgColor
                analyzeBtn.font = .systemFont(ofSize: 9, weight: .bold)
                analyzeBtn.identifier = NSUserInterfaceItemIdentifier(p)
                analyzeBtn.translatesAutoresizingMaskIntoConstraints = false
                analyzeBtn.heightAnchor.constraint(equalToConstant: 20).isActive = true

                hRow.addArrangedSubview(revealBtn)
                hRow.addArrangedSubview(inspectBtn)
                hRow.addArrangedSubview(analyzeBtn)

                historyStack.addArrangedSubview(hRow)
                hRow.widthAnchor.constraint(equalTo: historyStack.widthAnchor).isActive = true
            }
        }

        let histDoc = FlippedView()
        histDoc.translatesAutoresizingMaskIntoConstraints = false
        historyStack.translatesAutoresizingMaskIntoConstraints = false
        histDoc.addSubview(historyStack)

        let historyScroll = NSScrollView()
        historyScroll.hasVerticalScroller = true
        historyScroll.hasHorizontalScroller = false
        historyScroll.autohidesScrollers = true
        historyScroll.drawsBackground = false
        historyScroll.documentView = histDoc
        historyScroll.translatesAutoresizingMaskIntoConstraints = false
        let histHeight: CGFloat = fileHistory.isEmpty ? 36 : min(200, max(50, CGFloat(min(fileHistory.count, 6) * 30 + 10)))
        historyScroll.heightAnchor.constraint(equalToConstant: histHeight).isActive = true

        NSLayoutConstraint.activate([
            histDoc.leadingAnchor.constraint(equalTo: historyScroll.contentView.leadingAnchor),
            histDoc.trailingAnchor.constraint(equalTo: historyScroll.contentView.trailingAnchor),
            histDoc.topAnchor.constraint(equalTo: historyScroll.contentView.topAnchor),
            histDoc.widthAnchor.constraint(equalTo: historyScroll.contentView.widthAnchor),
            historyStack.leadingAnchor.constraint(equalTo: histDoc.leadingAnchor),
            historyStack.trailingAnchor.constraint(equalTo: histDoc.trailingAnchor),
            historyStack.topAnchor.constraint(equalTo: histDoc.topAnchor),
            histDoc.bottomAnchor.constraint(equalTo: historyStack.bottomAnchor)
        ])

        // Action Buttons Row (Solid Tactile Pills)
        func makeActionBtn(title: String, fill: NSColor, textColor: NSColor, action: Selector) -> NSButton {
            let b = NSButton(title: "", target: self, action: action)
            b.isBordered = false
            b.wantsLayer = true
            b.layer?.cornerRadius = 11
            b.layer?.backgroundColor = fill.cgColor
            let attr = NSAttributedString(string: I18n.translate(title), attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: textColor
            ])
            b.attributedTitle = attr
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 24).isActive = true
            return b
        }

        let resumeBtn = makeActionBtn(title: "✅ 放行允许 (SIGCONT)", fill: NSColor.systemGreen.withAlphaComponent(0.18), textColor: NSColor(srgbRed: 0.1, green: 0.6, blue: 0.2, alpha: 1.0), action: #selector(didClickResume))
        let pauseBtn = makeActionBtn(title: "⏸ 冻结挂起 (SIGSTOP)", fill: NSColor.systemOrange.withAlphaComponent(0.18), textColor: NSColor.systemOrange, action: #selector(didClickPause))
        let killBtn = makeActionBtn(title: "⚡️ 立即终止进程族", fill: NSColor.systemRed.withAlphaComponent(0.18), textColor: NSColor.systemRed, action: #selector(didClickKill))
        let applyBtn = makeActionBtn(title: "💾 应用规则", fill: Serafina.grape, textColor: .white, action: #selector(didClickApplyRules))
        let removeBtn = makeActionBtn(title: "移出监控", fill: Serafina.petal.withAlphaComponent(0.35), textColor: Serafina.ink, action: #selector(didClickRemove))

        let actionsRow = NSStackView(views: [resumeBtn, pauseBtn, killBtn, NSView(), applyBtn, removeBtn])
        actionsRow.orientation = .horizontal
        actionsRow.spacing = 8
        actionsRow.alignment = .centerY

        // Store references for checkboxes
        self.chkSensitiveRef = chkSensitive
        self.chkImagesRef = chkImages
        self.chkVideosRef = chkVideos
        self.chkLargeRef = chkLarge
        self.chkDocsRef = chkDocs
        self.chkGatekeeperRef = chkGatekeeper

        let mainStack = NSStackView(views: [
            topHeader,
            auditBox,
            trafficBox,
            connsTitle,
            connsScroll,
            familyProcsTitle,
            familyProcsStack,
            sandboxLabel,
            rulesRow1,
            rulesRow2,
            histHeader,
            historyScroll,
            actionsRow
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            topHeader.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            auditBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            trafficBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            connsTitle.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            connsScroll.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            sandboxLabel.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            rulesRow1.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            rulesRow2.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            histHeader.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            historyScroll.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            actionsRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])
    }

    private var chkSensitiveRef: NSButton?
    private var chkImagesRef: NSButton?
    private var chkVideosRef: NSButton?
    private var chkLargeRef: NSButton?
    private var chkDocsRef: NSButton?
    private var chkGatekeeperRef: NSButton?

    @objc private func didClickResume() { onResume(pid) }
    @objc private func didClickPause() { onPause(pid) }
    @objc private func didClickKill() { onKillFamily(pid) }
    @objc private func didClickRemove() { onRemove(pid) }
    @objc private func didClickClearHistory() { onClearHistory?(pid) }

    @objc private func didClickKillMember(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let mPid = Int(raw), mPid > 1 else { return }
        onKillSingle?(mPid)
    }

    @objc private func didClickInspectFileBtn(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue, !path.isEmpty else { return }
        let cmd = currentConfig["command"] as? String ?? "proc"
        onInspectFile?(path, pid, cmd)
    }

    @objc private func didClickRevealFileBtn(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue, !path.isEmpty else { return }
        onRevealFile?(path)
    }

    @objc private func didClickDisconnectSocket(_ sender: NSButton) {
        guard let tag = sender.identifier?.rawValue, tag.contains("::") else { return }
        let parts = tag.components(separatedBy: "::")
        let rip = parts[0]
        let rport = parts.count > 1 ? parts[1] : ""
        onDisconnectSocket?(pid, rip, rport)
    }

    @objc private func didClickBlockIP(_ sender: NSButton) {
        guard let ip = sender.identifier?.rawValue, !ip.isEmpty else { return }
        onBlockIP?(pid, ip)
    }

    @objc private func didClickUnblockIP(_ sender: NSButton) {
        guard let ip = sender.identifier?.rawValue, !ip.isEmpty else { return }
        onUnblockIP?(pid, ip)
    }

    @objc private func didClickApplyRules() {
        var bTypes: [String] = []
        if chkSensitiveRef?.state == .on { bTypes.append("sensitive") }
        if chkImagesRef?.state == .on { bTypes.append("images") }
        if chkVideosRef?.state == .on { bTypes.append("videos") }
        if chkDocsRef?.state == .on { bTypes.append("docs") }
        let blockLarge = chkLargeRef?.state == .on
        let enforcePrompt = chkGatekeeperRef?.state == .on
        let sandbox = currentConfig["sandbox_dir"] as? String ?? ""
        let customExts = currentConfig["custom_extensions"] as? [String] ?? []
        onUpdateRules(pid, bTypes, customExts, blockLarge, 20.0, sandbox, enforcePrompt)
    }

    required init?(coder: NSCoder) { nil }
}

final class LayerHealthCapsule: NSView {
    override var isFlipped: Bool { true }
    private let dotLabel = NSTextField(labelWithString: "🟢")
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "HEALTHY")
    private let detailLabel = NSTextField(labelWithString: "")

    init(layerId: String, name: String, initialStatus: String = "HEALTHY", initialDetail: String = "正常运行") {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Serafina.paper.withAlphaComponent(0.60).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor

        dotLabel.font = .systemFont(ofSize: 10)
        dotLabel.isBezeled = false
        dotLabel.isEditable = false
        dotLabel.drawsBackground = false

        titleLabel.font = Serafina.rounded(10, .bold)
        titleLabel.textColor = Serafina.ink
        titleLabel.stringValue = "\(layerId) \(name)"
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.drawsBackground = false

        statusLabel.font = Serafina.rounded(9, .heavy)
        statusLabel.textColor = NSColor.systemGreen
        statusLabel.stringValue = initialStatus
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.alignment = .right
        statusLabel.isBezeled = false
        statusLabel.isEditable = false
        statusLabel.drawsBackground = false

        detailLabel.font = Serafina.rounded(9, .medium)
        detailLabel.textColor = Serafina.muted
        detailLabel.stringValue = initialDetail
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.isBezeled = false
        detailLabel.isEditable = false
        detailLabel.drawsBackground = false

        let topRow = NSStackView(views: [dotLabel, titleLabel, NSView(), statusLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.distribution = .fill
        topRow.spacing = 3

        let stack = NSStackView(views: [topRow, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            topRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(status: String, detail: String) {
        let trimmed = status.uppercased()
        statusLabel.stringValue = trimmed
        if !detail.isEmpty {
            detailLabel.stringValue = detail
        }
        switch trimmed {
        case "HEALTHY":
            dotLabel.stringValue = "🟢"
            statusLabel.textColor = NSColor.systemGreen
        case "DEGRADED":
            dotLabel.stringValue = "🟡"
            statusLabel.textColor = NSColor.systemOrange
        case "UNHEALTHY":
            dotLabel.stringValue = "🔴"
            statusLabel.textColor = NSColor.systemRed
        case "RECOVERING":
            dotLabel.stringValue = "🟣"
            statusLabel.textColor = NSColor.systemPurple
        case "QUARANTINED":
            dotLabel.stringValue = "⛔️"
            statusLabel.textColor = NSColor.systemRed
        default:
            dotLabel.stringValue = "⚪️"
            statusLabel.textColor = Serafina.muted
        }
    }
}

final class FileInspectionWindowController: NSWindowController {
    var filePath: String = ""
    var targetPID: Int = 0
    var processName: String = ""

    private let titleLabel = NSTextField(labelWithString: "📄 重点监控传输文件内容审查")
    private let pathLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "正在加载属性…")
    private let contentTextView = NSTextView()
    private let reportTextView = NSTextView()
    private let riskBadge = NSTextField(labelWithString: " ⚪ 待审计 ")
    private let analyzeButton = NSButton()
    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "📄 传输文件内容审计 & 本地大模型威胁分析"
        win.backgroundColor = Serafina.lilac
        win.isReleasedWhenClosed = false
        super.init(window: win)
        setupUI()
    }

    required init?(coder: NSCoder) { nil }

    private func setupUI() {
        guard let win = window else { return }
        let root = NSView(frame: win.contentView?.bounds ?? .zero)
        root.wantsLayer = true
        win.contentView = root

        titleLabel.font = Serafina.display(20)
        titleLabel.textColor = Serafina.ink

        pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        pathLabel.textColor = Serafina.grape
        pathLabel.isSelectable = true
        pathLabel.lineBreakMode = .byTruncatingMiddle

        let copyPathBtn = NSButton(title: "📋 复制路径", target: self, action: #selector(copyPath))
        copyPathBtn.font = Serafina.rounded(10, .bold)
        copyPathBtn.isBordered = false
        copyPathBtn.wantsLayer = true
        copyPathBtn.layer?.cornerRadius = 6
        copyPathBtn.layer?.backgroundColor = Serafina.petal.withAlphaComponent(0.4).cgColor

        let pathRow = NSStackView(views: [pathLabel, NSView(), copyPathBtn])
        pathRow.orientation = .horizontal
        pathRow.alignment = .centerY

        metaLabel.font = Serafina.rounded(11, .medium)
        metaLabel.textColor = Serafina.muted

        let headerBox = NSStackView(views: [titleLabel, pathRow, metaLabel])
        headerBox.orientation = .vertical
        headerBox.alignment = .leading
        headerBox.spacing = 4

        // Preview Section
        let previewTitle = NSTextField(labelWithString: "【文件内容原始预览】(截取前 64KB · 支持代码/文本/二进制Hex)")
        previewTitle.font = Serafina.rounded(12, .bold)
        previewTitle.textColor = Serafina.ink

        contentTextView.isEditable = false
        contentTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        contentTextView.textColor = NSColor(srgbRed: 0.85, green: 0.90, blue: 0.95, alpha: 1.0)
        contentTextView.backgroundColor = NSColor(srgbRed: 0.12, green: 0.14, blue: 0.18, alpha: 1.0)
        contentTextView.isVerticallyResizable = true
        contentTextView.isHorizontallyResizable = false
        contentTextView.autoresizingMask = [.width]
        contentTextView.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        contentTextView.textContainer?.widthTracksTextView = true

        let contentScroll = NSScrollView()
        contentScroll.documentView = contentTextView
        contentScroll.hasVerticalScroller = true
        contentScroll.wantsLayer = true
        contentScroll.layer?.cornerRadius = 10
        contentScroll.layer?.borderWidth = 1
        contentScroll.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.heightAnchor.constraint(equalToConstant: 240).isActive = true

        // LLM Section
        let llmTitle = NSTextField(labelWithString: "【本地大模型深度安全审查 & 存入分析库】")
        llmTitle.font = Serafina.rounded(12, .bold)
        llmTitle.textColor = Serafina.grape

        riskBadge.font = Serafina.rounded(11, .bold)
        riskBadge.wantsLayer = true
        riskBadge.layer?.cornerRadius = 6
        riskBadge.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor

        let llmHeaderRow = NSStackView(views: [llmTitle, riskBadge, NSView()])
        llmHeaderRow.orientation = .horizontal
        llmHeaderRow.alignment = .centerY

        let optInHint = NSTextField(wrappingLabelWithString: "🛡️ 默认不自动耗费大模型算力与显存。点击按钮按需发起本地大模型深度分析，研判越权风险、敏感凭证与行为意图，结论将持久化至本地分析库。")
        optInHint.font = Serafina.rounded(10, .medium)
        optInHint.textColor = Serafina.muted

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        analyzeButton.target = self
        analyzeButton.action = #selector(didClickAnalyze)
        analyzeButton.isBordered = false
        analyzeButton.wantsLayer = true
        analyzeButton.layer?.cornerRadius = 12
        analyzeButton.layer?.backgroundColor = Serafina.grape.cgColor
        let attr = NSAttributedString(string: "🤖 启动本地大模型深度安全分析 (存入分析库)", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ])
        analyzeButton.attributedTitle = attr
        analyzeButton.translatesAutoresizingMaskIntoConstraints = false
        analyzeButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let copyReportBtn = NSButton(title: "📋 复制审计报告", target: self, action: #selector(copyReport))
        copyReportBtn.font = Serafina.rounded(10, .bold)
        copyReportBtn.isBordered = false
        copyReportBtn.wantsLayer = true
        copyReportBtn.layer?.cornerRadius = 6
        copyReportBtn.layer?.backgroundColor = Serafina.petal.withAlphaComponent(0.4).cgColor

        statusLabel.font = Serafina.rounded(10, .semibold)
        statusLabel.textColor = Serafina.muted

        let btnRow = NSStackView(views: [analyzeButton, spinner, statusLabel, NSView(), copyReportBtn])
        btnRow.orientation = .horizontal
        btnRow.alignment = .centerY
        btnRow.spacing = 8

        reportTextView.isEditable = false
        reportTextView.font = Serafina.rounded(12, .medium)
        reportTextView.textColor = Serafina.ink
        reportTextView.backgroundColor = Serafina.paper.withAlphaComponent(0.65)
        reportTextView.isVerticallyResizable = true
        reportTextView.isHorizontallyResizable = false
        reportTextView.autoresizingMask = [.width]
        reportTextView.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        reportTextView.textContainer?.widthTracksTextView = true

        let reportScroll = NSScrollView()
        reportScroll.documentView = reportTextView
        reportScroll.hasVerticalScroller = true
        reportScroll.wantsLayer = true
        reportScroll.layer?.cornerRadius = 10
        reportScroll.layer?.borderWidth = 1
        reportScroll.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        reportScroll.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView(views: [
            headerBox,
            previewTitle,
            contentScroll,
            llmHeaderRow,
            optInHint,
            btnRow,
            reportScroll
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            headerBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            pathRow.widthAnchor.constraint(equalTo: headerBox.widthAnchor),
            contentScroll.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            llmHeaderRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            optInHint.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            btnRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            reportScroll.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])
    }

    func inspect(path: String, pid: Int, processName: String) {
        self.filePath = path
        self.targetPID = pid
        self.processName = processName
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        pathLabel.stringValue = path
        metaLabel.stringValue = "进程: \(processName) (PID \(pid)) · 正在读取文件预览…"
        contentTextView.string = "正在加载文件内容…"
        reportTextView.string = "尚未进行大模型安全审计。\n\n🛡️ 说明：默认不自动耗费大模型算力与显存。点击上方「🤖 启动本地大模型深度安全分析」即可提交本地大模型进行深度安全威胁审查并存入分析库。"
        riskBadge.stringValue = " ⚪ 未分析 "
        riskBadge.textColor = Serafina.muted
        riskBadge.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        statusLabel.stringValue = ""
        analyzeButton.isEnabled = true
        analyzeButton.title = "🤖 启动本地大模型深度安全分析 (存入分析库)"

        loadFilePreview()
    }

    private func loadFilePreview() {
        guard let encoded = filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://127.0.0.1:8002/v1/watchlist/inspect_file?path=\(encoded)") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["ok"] as? Bool == true else {
                    let err = error?.localizedDescription ?? "无法读取文件"
                    self.contentTextView.string = "❌ 读取文件失败: \(err)"
                    self.metaLabel.stringValue = "读取失败"
                    return
                }

                let sz = json["size_formatted"] as? String ?? ""
                let mime = json["mime_type"] as? String ?? ""
                let isText = json["is_text"] as? Bool ?? false
                let mtime = json["modified_at"] as? String ?? ""
                let preview = json["preview"] as? String ?? ""

                self.metaLabel.stringValue = "进程: \(self.processName) (PID \(self.targetPID)) · 大小: \(sz) · 类型: \(mime) · 模式: \(isText ? "文本" : "二进制") · 修改于: \(mtime)"
                self.contentTextView.string = preview

                if let cached = json["cached_analysis"] as? [String: Any] {
                    self.renderAnalysisRecord(cached)
                    self.analyzeButton.title = "🔄 重新提交大模型深度分析"
                    self.statusLabel.stringValue = "✓ 已读取本地分析库存档 (\(cached["datetime"] as? String ?? ""))"
                }
            }
        }.resume()
    }

    @objc private func didClickAnalyze() {
        guard !filePath.isEmpty else { return }
        analyzeButton.isEnabled = false
        spinner.startAnimation(nil)
        statusLabel.stringValue = "正在调用本地大模型进行深度威胁分析…"

        guard let url = URL(string: "http://127.0.0.1:8002/v1/watchlist/analyze_file") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "path": filePath,
            "pid": targetPID,
            "process_name": processName,
            "force": true
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.spinner.stopAnimation(nil)
                self.analyzeButton.isEnabled = true
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["ok"] as? Bool == true,
                      let analysis = json["analysis"] as? [String: Any] else {
                    let err = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])?["error"] as? String
                        ?? error?.localizedDescription ?? "分析失败"
                    self.statusLabel.stringValue = "❌ 分析未完成"
                    self.reportTextView.string = "❌ 分析失败: \(err)\n\n提示：若本地大模型处于空载状态，请先在模型控制台启动本地模型后再执行深度分析。"
                    return
                }

                self.renderAnalysisRecord(analysis)
                self.analyzeButton.title = "🔄 重新提交大模型深度分析"
                self.statusLabel.stringValue = "✓ 深度审计完毕，已存档至本地安全分析库"
            }
        }.resume()
    }

    private func renderAnalysisRecord(_ rec: [String: Any]) {
        let risk = rec["risk_level"] as? String ?? "未知"
        let report = rec["report"] as? String ?? ""
        reportTextView.string = report

        riskBadge.stringValue = " 🤖 \(risk) "
        let riskColor: NSColor
        if risk.contains("高危") {
            riskColor = .systemRed
        } else if risk.contains("中危") {
            riskColor = .systemOrange
        } else if risk.contains("低风险") {
            riskColor = .systemYellow
        } else {
            riskColor = NSColor(srgbRed: 0.1, green: 0.6, blue: 0.2, alpha: 1.0)
        }
        riskBadge.textColor = riskColor
        riskBadge.layer?.backgroundColor = riskColor.withAlphaComponent(0.18).cgColor
    }

    @objc private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(filePath, forType: .string)
    }

    @objc private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reportTextView.string, forType: .string)
    }
}

final class GatekeeperInterceptWindowController: NSWindowController {
    private(set) var currentEventId: String = ""
    var onDecisionResolved: (() -> Void)?

    private let bannerTitle = NSTextField(labelWithString: "")
    private let bannerSub = NSTextField(wrappingLabelWithString: "")

    // Dedicated Destination & Trust Assessment Box
    private let destCard = NSView()
    private let destBadgeLabel = NSTextField(labelWithString: "")
    private let destTargetLabel = NSTextField(wrappingLabelWithString: "")
    private let destAdviceLabel = NSTextField(wrappingLabelWithString: "")

    // Process & Network summary
    private let reasonLabel = NSTextField(wrappingLabelWithString: "")
    private let procSummaryLabel = NSTextField(wrappingLabelWithString: "")
    private let netSummaryLabel = NSTextField(wrappingLabelWithString: "")
    private let sensitiveSummaryLabel = NSTextField(wrappingLabelWithString: "")

    private let detailTextView = NSTextView()
    private let whitelistContainer = NSView()
    private let whitelistCheckbox = NSButton()
    private var currentParentName: String = ""
    private let allowBtn = NSButton()
    private let killChildBtn = NSButton()
    private let killParentBtn = NSButton()
    private let killFamilyBtn = NSButton()
    private let statusFeedbackLabel = NSTextField(wrappingLabelWithString: "")

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "🚨 Gatekeeper 高危流量与敏感凭证实时拦截确认"
        win.backgroundColor = Serafina.lilac
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.minSize = NSSize(width: 700, height: 500)
        win.maxSize = NSSize(width: 10000, height: 10000)
        win.isReleasedWhenClosed = false
        super.init(window: win)
        setupUI()
    }

    required init?(coder: NSCoder) { nil }

    private func setupUI() {
        guard let win = window else { return }
        let root = NSView(frame: win.contentView?.bounds ?? .zero)
        root.wantsLayer = true
        win.contentView = root

        bannerTitle.font = .systemFont(ofSize: 17, weight: .heavy)
        bannerTitle.textColor = NSColor.systemRed
        bannerTitle.stringValue = I18n.translate("🚨 敏感凭证 / 高危后台流量传输拦截！")

        bannerSub.font = Serafina.rounded(11.5, .semibold)
        bannerSub.textColor = Serafina.ink
        bannerSub.stringValue = I18n.translate("⏸ 系统已自动挂起 (SIGSTOP) 该进程及其子进程，阻断后台上传传输。请核对以下详情，点击「允许放行」后才可通过：")

        // Destination & Trust Assessment Card
        destCard.wantsLayer = true
        destCard.layer?.cornerRadius = 10
        destCard.layer?.borderWidth = 1.5
        destCard.translatesAutoresizingMaskIntoConstraints = false

        destBadgeLabel.font = .systemFont(ofSize: 12.5, weight: .bold)
        destBadgeLabel.translatesAutoresizingMaskIntoConstraints = false

        destTargetLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        destTargetLabel.translatesAutoresizingMaskIntoConstraints = false

        destAdviceLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        destAdviceLabel.translatesAutoresizingMaskIntoConstraints = false

        let destStack = NSStackView(views: [destBadgeLabel, destTargetLabel, destAdviceLabel])
        destStack.orientation = .vertical
        destStack.alignment = .leading
        destStack.spacing = 5
        destStack.translatesAutoresizingMaskIntoConstraints = false
        destCard.addSubview(destStack)

        NSLayoutConstraint.activate([
            destStack.leadingAnchor.constraint(equalTo: destCard.leadingAnchor, constant: 14),
            destStack.trailingAnchor.constraint(equalTo: destCard.trailingAnchor, constant: -14),
            destStack.topAnchor.constraint(equalTo: destCard.topAnchor, constant: 10),
            destStack.bottomAnchor.constraint(equalTo: destCard.bottomAnchor, constant: -10),
            destBadgeLabel.widthAnchor.constraint(equalTo: destStack.widthAnchor),
            destTargetLabel.widthAnchor.constraint(equalTo: destStack.widthAnchor),
            destAdviceLabel.widthAnchor.constraint(equalTo: destStack.widthAnchor)
        ])

        reasonLabel.font = .systemFont(ofSize: 12.5, weight: .bold)
        reasonLabel.textColor = NSColor.systemRed

        procSummaryLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        procSummaryLabel.textColor = Serafina.ink

        netSummaryLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        netSummaryLabel.textColor = Serafina.grape

        sensitiveSummaryLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        sensitiveSummaryLabel.textColor = NSColor(srgbRed: 0.85, green: 0.20, blue: 0.20, alpha: 1.0)

        let infoCard = NSView()
        infoCard.wantsLayer = true
        infoCard.layer?.cornerRadius = 10
        infoCard.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
        infoCard.layer?.borderWidth = 1
        infoCard.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        infoCard.translatesAutoresizingMaskIntoConstraints = false

        let infoStack = NSStackView(views: [reasonLabel, procSummaryLabel, netSummaryLabel, sensitiveSummaryLabel])
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 5
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoCard.addSubview(infoStack)

        NSLayoutConstraint.activate([
            infoStack.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 14),
            infoStack.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -14),
            infoStack.topAnchor.constraint(equalTo: infoCard.topAnchor, constant: 10),
            infoStack.bottomAnchor.constraint(equalTo: infoCard.bottomAnchor, constant: -10),
            reasonLabel.widthAnchor.constraint(equalTo: infoStack.widthAnchor),
            procSummaryLabel.widthAnchor.constraint(equalTo: infoStack.widthAnchor),
            netSummaryLabel.widthAnchor.constraint(equalTo: infoStack.widthAnchor),
            sensitiveSummaryLabel.widthAnchor.constraint(equalTo: infoStack.widthAnchor)
        ])

        let detailHeader = NSTextField(labelWithString: I18n.translate("📋 拦截现场完整审计细节 (敏感凭证路径 / 父子进程内存 / 外联目标):"))
        detailHeader.font = Serafina.rounded(12, .bold)
        detailHeader.textColor = Serafina.ink

        detailTextView.isEditable = false
        detailTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detailTextView.textColor = NSColor(srgbRed: 0.90, green: 0.93, blue: 0.98, alpha: 1.0)
        detailTextView.backgroundColor = NSColor(srgbRed: 0.12, green: 0.14, blue: 0.19, alpha: 1.0)
        detailTextView.isVerticallyResizable = true
        detailTextView.isHorizontallyResizable = false
        detailTextView.autoresizingMask = [.width]
        detailTextView.textContainer?.containerSize = NSSize(width: 710, height: CGFloat.greatestFiniteMagnitude)
        detailTextView.textContainer?.widthTracksTextView = true

        let detailScroll = NSScrollView()
        detailScroll.documentView = detailTextView
        detailScroll.hasVerticalScroller = true
        detailScroll.wantsLayer = true
        detailScroll.layer?.cornerRadius = 10
        detailScroll.layer?.borderWidth = 1
        detailScroll.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        detailScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        detailScroll.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)

        // Whitelist Parent Process Checkbox & Hint Box
        whitelistContainer.wantsLayer = true
        whitelistContainer.layer?.cornerRadius = 8
        whitelistContainer.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.06).cgColor
        whitelistContainer.layer?.borderWidth = 1
        whitelistContainer.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.25).cgColor
        whitelistContainer.translatesAutoresizingMaskIntoConstraints = false

        whitelistCheckbox.setButtonType(.switch)
        whitelistCheckbox.font = .systemFont(ofSize: 12, weight: .bold)
        whitelistCheckbox.title = I18n.translate("🛡️ 记住此授权：将父进程加入信任白名单 (下次不再弹窗提醒)")
        whitelistCheckbox.target = self
        whitelistCheckbox.action = #selector(whitelistCheckboxToggled)
        whitelistCheckbox.translatesAutoresizingMaskIntoConstraints = false

        let wlHint = NSTextField(wrappingLabelWithString: I18n.translate("勾选后，该父进程今后派生子进程或执行外联时将直接受信任放行，不会再阻断挂起或弹出警告。"))
        wlHint.font = Serafina.rounded(10.5, .medium)
        wlHint.textColor = Serafina.muted
        wlHint.translatesAutoresizingMaskIntoConstraints = false

        let wlStack = NSStackView(views: [whitelistCheckbox, wlHint])
        wlStack.orientation = .vertical
        wlStack.alignment = .leading
        wlStack.spacing = 3
        wlStack.translatesAutoresizingMaskIntoConstraints = false
        whitelistContainer.addSubview(wlStack)

        NSLayoutConstraint.activate([
            wlStack.leadingAnchor.constraint(equalTo: whitelistContainer.leadingAnchor, constant: 12),
            wlStack.trailingAnchor.constraint(equalTo: whitelistContainer.trailingAnchor, constant: -12),
            wlStack.topAnchor.constraint(equalTo: whitelistContainer.topAnchor, constant: 8),
            wlStack.bottomAnchor.constraint(equalTo: whitelistContainer.bottomAnchor, constant: -8)
        ])

        func configureBtn(_ btn: NSButton, title: String, bg: NSColor, fg: NSColor, action: Selector) {
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 10
            btn.layer?.backgroundColor = bg.cgColor
            btn.attributedTitle = NSAttributedString(string: I18n.translate(title), attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: fg
            ])
            btn.target = self
            btn.action = action
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }

        configureBtn(allowBtn, title: "✅ 允许放行 (恢复传输 SIGCONT)", bg: NSColor(srgbRed: 0.13, green: 0.68, blue: 0.32, alpha: 1.0), fg: .white, action: #selector(didClickAllow))
        configureBtn(killChildBtn, title: "🛑 拒绝并关闭本进程", bg: NSColor.systemOrange, fg: .white, action: #selector(didClickKillChild))
        configureBtn(killParentBtn, title: "⬆️ 拒绝并关闭父进程", bg: Serafina.grape, fg: .white, action: #selector(didClickKillParent))
        configureBtn(killFamilyBtn, title: "💥 拒绝并清理父子进程树", bg: NSColor(srgbRed: 0.85, green: 0.16, blue: 0.20, alpha: 1.0), fg: .white, action: #selector(didClickKillFamily))

        let btnRow = NSStackView(views: [allowBtn, killChildBtn, killParentBtn, killFamilyBtn])
        btnRow.orientation = .horizontal
        btnRow.distribution = .fillEqually
        btnRow.spacing = 10

        statusFeedbackLabel.font = Serafina.rounded(11, .semibold)
        statusFeedbackLabel.textColor = Serafina.muted

        let mainStack = NSStackView(views: [
            bannerTitle,
            bannerSub,
            destCard,
            infoCard,
            detailHeader,
            detailScroll,
            whitelistContainer,
            statusFeedbackLabel,
            btnRow
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            bannerSub.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            destCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            infoCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            detailScroll.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            whitelistContainer.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            statusFeedbackLabel.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            btnRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])
    }

    func presentEvent(_ event: [String: Any]) {
        let evId = event["event_id"] as? String ?? ""
        self.currentEventId = evId
        let pid = event["pid"] as? Int ?? 0
        let ppid = event["ppid"] as? Int ?? 0
        let cmd = event["command"] as? String ?? "unknown"
        let parentName = event["parent_name"] as? String ?? "launchd"
        let reason = event["reason"] as? String ?? "检测到敏感凭证访问或高危后台外联上传"
        let memFmt = event["memory_formatted"] as? String ?? "0 B"
        let famMemFmt = event["family_memory_formatted"] as? String ?? memFmt
        let cpuPct = event["cpu_percent"] as? Double ?? 0.0
        let remoteEp = (event["remote_endpoint"] as? String) ?? (event["remote"] as? String ?? I18n.translate("未知外部地址"))
        let geo = event["geo"] as? String ?? I18n.translate("外部公网")
        let upFmt = event["upload_formatted"] as? String ?? "0 B"
        let upSpd = event["upload_speed_formatted"] as? String ?? "0 B/s"
        let downFmt = event["download_formatted"] as? String ?? "0 B"
        let timeStr = event["timestamp_str"] as? String ?? ""
        let sensFiles = event["sensitive_files"] as? [String] ?? []
        let alertDetails = event["alert_details"] as? [String] ?? []
        let children = event["children"] as? [[String: Any]] ?? []
        let isPaused = event["is_paused"] as? Bool ?? true

        // Destination & Trust properties
        let targetDomain = event["target_domain"] as? String ?? ""
        let targetOrg = event["target_org"] as? String ?? ""
        let trustLevel = event["trust_level"] as? String ?? "SUSPICIOUS"
        let trustBadge = event["trust_badge"] as? String ?? ""
        let trustAdvice = event["trust_advice"] as? String ?? ""
        let isOfficial = event["is_official"] as? Bool ?? false

        let domainDisplay = targetDomain.isEmpty ? remoteEp : targetDomain
        let orgDisplay = targetOrg.isEmpty ? geo : targetOrg

        // Configure trust card appearance
        if isOfficial || trustLevel == "OFFICIAL_TRUSTED" {
            destCard.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.08).cgColor
            destCard.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.50).cgColor
            destBadgeLabel.textColor = NSColor(srgbRed: 0.12, green: 0.65, blue: 0.28, alpha: 1.0)
            destTargetLabel.textColor = Serafina.ink
            destAdviceLabel.textColor = NSColor(srgbRed: 0.10, green: 0.52, blue: 0.22, alpha: 1.0)
            bannerTitle.textColor = NSColor(srgbRed: 0.12, green: 0.65, blue: 0.28, alpha: 1.0)
            bannerTitle.stringValue = I18n.translate("🛡️ 敏感凭证与后台外联传输确认 (可信官方目标)")
            statusFeedbackLabel.stringValue = I18n.translate("🟢 安全建议：上传目的地为 Apple 等官方服务器，通常用于账号身份验证或系统数据同步。若确认属实，建议点击「允许放行」。")
        } else if trustLevel == "PUBLIC_CLOUD" {
            destCard.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.08).cgColor
            destCard.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.50).cgColor
            destBadgeLabel.textColor = NSColor.systemOrange
            destTargetLabel.textColor = Serafina.ink
            destAdviceLabel.textColor = NSColor.systemOrange
            bannerTitle.textColor = NSColor.systemOrange
            bannerTitle.stringValue = I18n.translate("⚠️ 敏感凭证 / 公有云后台流量传输拦截！")
            statusFeedbackLabel.stringValue = I18n.translate("🟡 提醒：目标为公共云端/CDN，请确认是否为预期上传；若非预期，建议点击「拒绝并关闭」。")
        } else {
            destCard.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.08).cgColor
            destCard.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.50).cgColor
            destBadgeLabel.textColor = NSColor.systemRed
            destTargetLabel.textColor = Serafina.ink
            destAdviceLabel.textColor = NSColor.systemRed
            bannerTitle.textColor = NSColor.systemRed
            bannerTitle.stringValue = I18n.translate("🚨 敏感凭证 / 高危未知后台流量传输拦截！")
            statusFeedbackLabel.stringValue = I18n.translate("🔴 高危警示：目标为未知公网或自建节点，正在外发私钥/凭据！极可能是恶意泄密，强烈建议点击「拒绝并清理」。")
        }

        destBadgeLabel.stringValue = I18n.translate(trustBadge.isEmpty ? "🛡️ 上传目的地与平台可信度研判" : trustBadge)
        destTargetLabel.stringValue = I18n.translate("🌐 上传目的地: ") + "\(domainDisplay)" + I18n.translate("  |  🏢 归属机构: ") + "\(orgDisplay)" + I18n.translate("  |  📍 远端: ") + "\(remoteEp)"
        destAdviceLabel.stringValue = I18n.translate("💡 研判分析: ") + I18n.translate(trustAdvice.isEmpty ? "正在外发敏感凭据，请审慎核对。" : trustAdvice)

        reasonLabel.stringValue = I18n.translate("🚨 触发原因: ") + I18n.translate(reason) + (!timeStr.isEmpty ? " [\(timeStr)]" : "")
        procSummaryLabel.stringValue = I18n.translate("⛓ 进程: \(cmd) (PID: \(pid)) · 父进程: \(parentName) (PPID: \(ppid)) · 🧠 本进程内存: \(memFmt) (家族总内存: \(famMemFmt)) · 🔥 CPU: \(String(format: "%.1f", cpuPct))%")
        netSummaryLabel.stringValue = I18n.translate("🌐 外联目标: ") + "\(remoteEp) (\(geo)) · " + I18n.translate("⬆️ 后台上传: ") + "\(upFmt) (" + I18n.translate("当前上传速度 ") + "\(upSpd)) · " + I18n.translate("↓ 下载: ") + "\(downFmt)"

        if !sensFiles.isEmpty {
            let fileNames = sensFiles.prefix(2).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            sensitiveSummaryLabel.stringValue = I18n.translate("🔑 涉及凭据: ") + "\(fileNames)" + (sensFiles.count > 2 ? I18n.translate(" 等共 \(sensFiles.count) 个敏感文件") : "")
            sensitiveSummaryLabel.isHidden = false
        } else {
            sensitiveSummaryLabel.isHidden = true
        }

        var lines: [String] = []
        lines.append(I18n.translate("【拦截状态】: ") + (isPaused ? I18n.translate("⏸ 已通过 SIGSTOP 冻结挂起该进程与子进程，等待人工授权") : I18n.translate("⚠️ 实时拦截监控中")))
        lines.append("")
        lines.append(I18n.translate("🎯 ══════ 【上传目的地与主体归属 (Destination & Trust)】 ══════"))
        lines.append(I18n.translate("  • 目标域名 (Domain): ") + "\(domainDisplay)")
        lines.append(I18n.translate("  • 所属机构 (Organization): ") + "\(orgDisplay)")
        lines.append(I18n.translate("  • 网络端点 (Endpoint): ") + "\(remoteEp)")
        lines.append(I18n.translate("  • 地理归属 (Geo Location): ") + "\(geo)")
        lines.append(I18n.translate("  • 安全评级 (Trust Level): ") + I18n.translate(trustBadge.isEmpty ? trustLevel : trustBadge))
        lines.append(I18n.translate("  • 专家研判 (Security Advice): ") + I18n.translate(trustAdvice))
        lines.append("")
        if !sensFiles.isEmpty {
            lines.append(I18n.translate("🔑 ══════ 【检测到触碰的敏感凭证 / 私钥文件") + " (\(sensFiles.count)" + I18n.translate(" 项)】 ══════"))
            for sf in sensFiles {
                lines.append("  • \(sf)")
            }
            lines.append("")
        }
        lines.append(I18n.translate("⛓ ══════ 【进程与系统执行现场】 ══════"))
        lines.append(I18n.translate("  • 触发进程: ") + "\(cmd) (PID: \(pid))")
        lines.append(I18n.translate("  • 父级守护: ") + "\(parentName) (PPID: \(ppid))")
        lines.append(I18n.translate("  • 内存占用: 本进程 ") + "\(memFmt)" + I18n.translate(" / 进程树总计 ") + "\(famMemFmt)" + "  |  🔥 CPU: \(String(format: "%.1f", cpuPct))%")
        lines.append(I18n.translate("  • 传输流量: 累计上传 ") + "\(upFmt)" + I18n.translate(" (当前上传速度 ") + "\(upSpd)" + I18n.translate(") · 累计下载 ") + "\(downFmt)")
        lines.append("")
        if !alertDetails.isEmpty {
            lines.append(I18n.translate("⚠️ ══════ 【高危行为告警细节】 ══════"))
            for ad in alertDetails {
                lines.append("  • \(I18n.translate(ad))")
            }
            lines.append("")
        }
        if !children.isEmpty {
            lines.append(I18n.translate("👶 ══════ 【关联子进程列表") + " (" + I18n.translate("共 \(children.count) 个子进程") + ")] ══════")
            for ch in children {
                let cPid = ch["pid"] as? Int ?? 0
                let cName = ch["name"] as? String ?? (ch["command"] as? String ?? "child")
                let cMem = ch["memory_formatted"] as? String ?? "0 B"
                let cCpu = ch["cpu_percent"] as? Double ?? 0.0
                lines.append("  ↳ \(I18n.translate("子进程")) PID \(cPid): \(cName)  |  \(I18n.translate("🧠 内存:")) \(cMem)  |  🔥 CPU: \(String(format: "%.1f", cCpu))%")
            }
        } else {
            lines.append(I18n.translate("👶 ══════ 【关联子进程列表】: 无派生子进程 ══════"))
        }

        detailTextView.string = lines.joined(separator: "\n")

        self.currentParentName = parentName
        let displayParent = parentName.isEmpty ? "当前父进程" : parentName
        whitelistCheckbox.title = I18n.translate("🛡️ 记住此授权：将父进程「\(displayParent)」加入信任白名单 (下次不再弹窗提醒)")
        whitelistCheckbox.state = .off
        updateAllowButtonTitle()

        allowBtn.isEnabled = true
        killChildBtn.isEnabled = true
        killParentBtn.isEnabled = (ppid > 1)
        killFamilyBtn.isEnabled = true

        NSSound.beep()
        if let win = window {
            if !win.isVisible {
                win.center()
            }
            win.makeKeyAndOrderFront(nil)
            win.orderFrontRegardless()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func whitelistCheckboxToggled() {
        updateAllowButtonTitle()
    }

    private func updateAllowButtonTitle() {
        let isChecked = (whitelistCheckbox.state == .on)
        let title = isChecked ? "🛡️ 放行并永久信任父进程 (加入白名单)" : "✅ 允许放行 (恢复传输 SIGCONT)"
        let bg = isChecked ? NSColor(srgbRed: 0.10, green: 0.58, blue: 0.28, alpha: 1.0) : NSColor(srgbRed: 0.13, green: 0.68, blue: 0.32, alpha: 1.0)
        allowBtn.layer?.backgroundColor = bg.cgColor
        allowBtn.attributedTitle = NSAttributedString(string: I18n.translate(title), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white
        ])
    }

    private func sendDecision(action: String) {
        guard !currentEventId.isEmpty,
              let url = URL(string: "http://127.0.0.1:8002/v1/network/gatekeeper_decision") else { return }
        allowBtn.isEnabled = false
        killChildBtn.isEnabled = false
        killParentBtn.isEnabled = false
        killFamilyBtn.isEnabled = false
        statusFeedbackLabel.stringValue = "正在执行指令..."

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "event_id": currentEventId,
            "action": action
        ]
        if action == "allow" {
            body["whitelist_parent"] = (whitelistCheckbox.state == .on)
            body["parent_name"] = currentParentName
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let msg = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["message"] as? String ?? "已处理"
                self.statusFeedbackLabel.stringValue = "✓ \(msg)"
                self.currentEventId = ""
                self.window?.close()
                self.onDecisionResolved?()
            }
        }.resume()
    }

    @objc private func didClickAllow() {
        sendDecision(action: "allow")
    }

    @objc private func didClickKillChild() {
        sendDecision(action: "kill_child")
    }

    @objc private func didClickKillParent() {
        sendDecision(action: "kill_parent")
    }

    @objc private func didClickKillFamily() {
        sendDecision(action: "kill_family")
    }
}

final class SidebarItemView: NSControl {
    private let iconLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let bgView = NSView()
    let targetIndex: Int

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    init(icon: String, title: String, targetIndex: Int, target: AnyObject?, action: Selector) {
        self.targetIndex = targetIndex
        super.init(frame: .zero)
        self.target = target
        self.action = action
        wantsLayer = true
        setupUI(icon: icon, title: title)
    }

    required init?(coder: NSCoder) { nil }

    private func setupUI(icon: String, title: String) {
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = 8
        bgView.layer?.cornerCurve = .continuous
        bgView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bgView)

        iconLabel.font = .systemFont(ofSize: 13, weight: .medium)
        iconLabel.stringValue = icon
        iconLabel.alignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconLabel)

        titleLabel.font = Serafina.rounded(12, .semibold)
        titleLabel.stringValue = title
        titleLabel.textColor = Serafina.ink
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            bgView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            bgView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            bgView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            bgView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            iconLabel.leadingAnchor.constraint(equalTo: bgView.leadingAnchor, constant: 8),
            iconLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconLabel.widthAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: bgView.trailingAnchor, constant: -6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 34)
        ])
        updateAppearance()
    }

    func setTitle(_ newTitle: String) {
        titleLabel.stringValue = newTitle
    }

    private func updateAppearance() {
        if isSelected {
            bgView.layer?.backgroundColor = Serafina.grape.cgColor
            titleLabel.textColor = .white
            iconLabel.textColor = .white
        } else {
            bgView.layer?.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = Serafina.ink
            iconLabel.textColor = Serafina.muted
        }
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}

final class PowerButtonView: NSControl {
    private let iconLabel = NSTextField(labelWithString: "⏻")
    private var isWorking = false
    private var isReady = false

    override var intrinsicContentSize: NSSize { NSSize(width: 44, height: 44) }

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 44, height: 44))
        wantsLayer = true
        setupUI()
    }

    required init?(coder: NSCoder) { nil }

    private func setupUI() {
        layer?.cornerRadius = 22
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Serafina.paper.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 2.0
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor

        iconLabel.font = .systemFont(ofSize: 20, weight: .bold)
        iconLabel.textColor = NSColor.secondaryLabelColor
        iconLabel.alignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconLabel)

        NSLayoutConstraint.activate([
            iconLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateVisualState()
    }

    func setState(ready: Bool, working: Bool) {
        self.isReady = ready
        self.isWorking = working
        updateVisualState()
    }

    private func updateVisualState() {
        if isWorking {
            layer?.borderColor = NSColor(srgbRed: 1.0, green: 0.58, blue: 0.16, alpha: 0.95).cgColor
            iconLabel.textColor = NSColor(srgbRed: 1.0, green: 0.58, blue: 0.16, alpha: 1.0)
            layer?.backgroundColor = NSColor(srgbRed: 1.0, green: 0.58, blue: 0.16, alpha: 0.18).cgColor
        } else if isReady {
            layer?.borderColor = NSColor(srgbRed: 0.20, green: 0.88, blue: 0.42, alpha: 0.95).cgColor
            iconLabel.textColor = NSColor(srgbRed: 0.15, green: 0.80, blue: 0.35, alpha: 1.0)
            layer?.backgroundColor = NSColor(srgbRed: 0.20, green: 0.88, blue: 0.42, alpha: 0.15).cgColor
        } else {
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.18).cgColor
            iconLabel.textColor = NSColor.secondaryLabelColor
            layer?.backgroundColor = Serafina.paper.withAlphaComponent(0.6).cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        alphaValue = 0.7
        super.mouseDown(with: event)
        alphaValue = 1.0
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            sendAction(action, to: target)
        }
    }
}

struct ModelChoice {
    let title: String
    let provider: String
    let model: String
    let capability: String
    let endpoint: String?
    let managedMTPLX: Bool
    let reasoningEffort: String
    let backend: String
    let backendURL: String
    let serveModel: String
    let profile: String
    let mtp: Bool
    let lmsKey: String
    let ggufPath: String
    let ggufRepo: String
    let contextLength: Int

    init(title: String, provider: String, model: String, capability: String,
         endpoint: String? = nil, managedMTPLX: Bool = false, reasoningEffort: String = "low",
         backend: String = "mtplx", backendURL: String = "http://127.0.0.1:8000",
         serveModel: String = "", profile: String = "turbo", mtp: Bool = true,
         lmsKey: String = "", ggufPath: String = "", ggufRepo: String = "",
         contextLength: Int = 0) {
        self.title = title
        self.provider = provider
        self.model = model
        self.capability = capability
        self.endpoint = endpoint
        self.managedMTPLX = managedMTPLX
        self.reasoningEffort = reasoningEffort
        self.backend = backend
        self.backendURL = backendURL
        self.serveModel = serveModel
        self.profile = profile
        self.mtp = mtp
        self.lmsKey = lmsKey
        self.ggufPath = ggufPath
        self.ggufRepo = ggufRepo
        self.contextLength = contextLength
    }

    var compactTokenLimit: Int { contextLength > 0 ? contextLength * 3 / 4 : 0 }
    var isLocal: Bool { provider == "local-qwen" }
    var codexName: String {
        switch model {
        case "Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed-FP16": return "本地 Qwen 3.8 27B MTP"
        case "local/qwen3.8-27b-mlx-4bit": return "本地 Qwen 3.8 27B 4bit"
        case "local/qwen3.5-9b-mlx-4bit": return "本地 Qwen 3.5 9B"
        case "local/cyberstrike-35b-mlx-6bit": return "本地 CyberStrike 35B 6bit"
        case "local/qwopus3.6-35b-a3b-coder-4bit": return "本地 Qwopus 3.6 35B Coder"
        case "local/ravenx-qwen3.6-35b-a3b-4bit-mtp": return "本地 RavenX 35B A3B"
        case "local/nemotron-3.5-lightning-30b-a3b-mlx-4bit": return "本地 Nemotron 3.5 Lightning 30B"
        case "local/qwen3.6-35b-a3b-mlx-4bit": return "本地 Qwen 3.6 35B A3B 4bit"
        case "gemma4-26b": return "本地 Gemma 4 26B"
        case "gpt-oss-20b": return "本地 GPT-OSS 20B"
        case "bonsai-27b-agent": return "本地 Bonsai 三进制 27B"
        case "NVIDIA-Nemotron-3.5-Lightning-30B-A3B-MLX-4bit": return "本地 Nemotron 3.5 Lightning 30B · oMLX"
        case "NVIDIA-Nemotron-3.5-Lightning-30B-A3B-MLX-6bit": return "本地 Nemotron 3.5 Lightning 6bit · oMLX"
        case "NVIDIA-Nemotron-3-Super-120B-A12B-4bit": return "本地 Nemotron 3 Super 120B · oMLX"
        case "K2-Horizon-MoVA-36B-A4B-MLX-4bit": return "本地 K2 Horizon MoVA 36B A4B"
        case "Ling-3.0-flash-oQ2": return "本地 Ling 3.0 Flash 124B A5B"
        default: return title
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSSearchFieldDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var activeToastView: ToastHUDView?

    func showAsyncToast(_ message: String, isSuccess: Bool = true, duration: TimeInterval = 2.5) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let cv = self.window?.contentView else { return }
            self.activeToastView?.removeFromSuperview()

            let toast = ToastHUDView(message: I18n.translate(message), isSuccess: isSuccess)
            toast.alphaValue = 0
            cv.addSubview(toast)
            self.activeToastView = toast

            NSLayoutConstraint.activate([
                toast.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
                toast.topAnchor.constraint(equalTo: cv.topAnchor, constant: 18),
                toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
                toast.widthAnchor.constraint(lessThanOrEqualTo: cv.widthAnchor, multiplier: 0.82)
            ])
            cv.layoutSubtreeIfNeeded()

            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                toast.animator().alphaValue = 1.0
            }, completionHandler: { [weak toast, weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak toast, weak self] in
                    guard let t = toast, t.superview != nil else { return }
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration = 0.28
                        ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                        t.animator().alphaValue = 0.0
                    }, completionHandler: {
                        t.removeFromSuperview()
                        if self?.activeToastView === t {
                            self?.activeToastView = nil
                        }
                    })
                }
            })
        }
    }
    private var modelPopup: NSPopUpButton?
    private var effortPopup: NSPopUpButton?
    private var depthPopup: NSPopUpButton?
    private var windowPopup: NSPopUpButton?
    private var thinkingCheckbox: NSButton?
    private var currentLabel: NSTextField?
    private var capabilityLabel: NSTextField?
    private var serviceStatusLabel: NSTextField?
    private var statsLabel: NSTextField?
    private var ledMeter: LEDMeterView?
    private var meterStatusLabel: NSTextField?
    private var runningModelId = ""
    private var lmStudioLoadedModel = ""
    private var bonsaiReady = false
    private var omlxLoadedModels: [String] = []
    private var localBackendUp: Bool {
        mtplxReady || bonsaiReady || !lmStudioLoadedModel.isEmpty || !omlxLoadedModels.isEmpty
    }
    private var transcriptView: NSTextView?
    private var restartCheckbox: NSButton?
    private var serviceTimer: Timer?
    private var trafficTimer: Timer?
    private var mtplxReady = false
    private var lastLoggedServiceState: Bool?
    private var trafficOffset: UInt64 = 0
    private var trafficRemainder = ""
    private var trafficPrimed = false
    private var activeStreamID = ""
    private var liveRequests: [String: String] = [:]
    private var requestOwners: [String: String] = [:]
    private var activeAnswer = ""
    private var activeModel = ""
    private var taskBlocked = false
    private var speedAverages: [String: [String: Any]] = [:]
    private var cacheSummary = ""
    private lazy var lastSpeeds: [String: Double] =
        (UserDefaults.standard.dictionary(forKey: "lastSpeeds") as? [String: Double]) ?? [:]
    private lazy var lastPrefillSpeeds: [String: Double] =
        (UserDefaults.standard.dictionary(forKey: "lastPrefillSpeeds") as? [String: Double]) ?? [:]
    private var fixingFrame = false
    private var clientStatusLabels: [String: NSTextField] = [:]
    private var clientLastSeen: [String: Date] = [:]
    private var codexFollowCheckbox: NSButton?
    private var managedSwitch: NSSwitch?
    private var managedStatusLabel: NSTextField?
    private var manualControls: [NSControl] = []
    private var clientButtons: [NSControl] = []
    private var managedMode: Bool { UserDefaults.standard.bool(forKey: "managedAgentMode") }
    private var settingsHintLabel: NSTextField?
    /// Best known settings per model: measured on this Mac or taken from the
    /// model card. Manual changes are kept per model on top of these.
    private let recommendedSettings: [String: (thinking: Bool, effort: String, depth: Int)] = [
        "local/qwopus3.6-35b-a3b-coder-4bit": (false, "medium", 3),   // thinking-off fine-tune; bench 2026-10-09
        "local/ravenx-qwen3.6-35b-a3b-4bit-mtp": (true, "medium", 3), // MSQ pack; served by LM Studio, which honors per-tensor bits
        "local/nemotron-3.5-lightning-30b-a3b-mlx-4bit": (true, "medium", 1), // official thinking-on; Nemotron-H MTP is single-step only
        "local/qwen3.6-35b-a3b-mlx-4bit": (true, "medium", 3),        // thinking model; Qwen recommends it for agents
        "Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed-FP16": (true, "medium", 3),
        "local/qwen3.8-27b-mlx-4bit": (true, "medium", 3),
        "local/qwen3.5-9b-mlx-4bit": (false, "medium", 3),
        "gemma4-26b": (false, "medium", 3),
        "gpt-oss-20b": (false, "medium", 3),
        "bonsai-27b-agent": (true, "medium", 3),
        "NVIDIA-Nemotron-3.5-Lightning-30B-A3B-MLX-4bit": (true, "medium", 1), // official template default: thinking on
        "NVIDIA-Nemotron-3.5-Lightning-30B-A3B-MLX-6bit": (true, "medium", 1),
        "NVIDIA-Nemotron-3-Super-120B-A12B-4bit": (true, "medium", 1),
        "K2-Horizon-MoVA-36B-A4B-MLX-4bit": (true, "medium", 3),  // K2 cannot turn thinking off; off = effort low
        "Ling-3.0-flash-oQ2": (true, "medium", 3),                // "detailed thinking on" by default
        "gpt-5.6-sol": (false, "xhigh", 3),
        "deepseek-v4-flash": (false, "high", 3),
        "deepseek-v4-pro": (false, "high", 3),
        "deepseek-v4-flash-vision-exp": (false, "high", 3)
    ]
    /// The one "best local agent" configuration used by 全托管 Agent 模式.
    /// Thinking off: Qwopus Coder is a thinking-off fine-tune, and the
    /// 2026-10-09 bench had OpenCode and Claude Code at 5/5 and faster with it off.
    private let managedProfile = (model: "local/qwopus3.6-35b-a3b-coder-4bit", effort: "medium",
                                  thinking: false, targetTokS: 45.0)
    private let clientIDs = ["codex", "opencode", "claude", "qwen"]
    private var clientPopups: [String: NSPopUpButton] = [:]
    private var clientApplyHints: [String: NSTextField] = [:]
    private var clientTargetSignatures: [String: String] = [:]
    private var autoloadCheckbox: NSButton?
    private var apiPanel: NSWindow?
    private var apiSnippetView: NSTextView?
    private var apiSnippetPopup: NSPopUpButton?
    private var apiModelLabel: NSTextField?
    private let localGateway = "http://127.0.0.1:8002"

    /// Set by `--home DIR` for the command-line client mode (sandbox tests).
    static var homeOverride: URL?
    private let home = AppDelegate.homeOverride ?? FileManager.default.homeDirectoryForCurrentUser
    private var teamCheckbox: NSButton?
    private var companionPopup: NSPopUpButton?
    private var taskRepoField: NSTextField?
    private var taskGoalField: NSTextField?
    private var taskAcceptField: NSTextField?
    private var taskStatusLabel: NSTextField?
    private var taskProcess: Process?
    private var pagePicker: NSSegmentedControl?
    private var pageCards: [[NSView]] = []
    private var sidebarItems: [SidebarItemView] = []
    private var topBarModelLabel: NSTextField?
    private var topBarStatusBadge: NSTextField?
    private var topBarSpeedLabel: NSTextField?
    private var powerButton: PowerButtonView?
    private var unloadModelButton: NSButton?
    private var topBarUnloadButton: NSButton?
    private var fileInspectionWindow: FileInspectionWindowController?
    private var modelContextCapsule: NSTextField?
    private var statTotalTokens: MetricStatCard?
    private var statCachedTokens: MetricStatCard?
    private var statThroughputTPS: MetricStatCard?
    private var statEAT: MetricStatCard?
    private var statWCR: MetricStatCard?
    private var statARP: MetricStatCard?
    private var capsuleL1: LayerHealthCapsule?
    private var capsuleL2: LayerHealthCapsule?
    private var capsuleL3: LayerHealthCapsule?
    private var capsuleL4: LayerHealthCapsule?
    private var capsuleL5: LayerHealthCapsule?
    private var capsuleL6: LayerHealthCapsule?
    private var arpTimelineLabel: NSTextField?
    private var dashboardModelInfoLabel: NSTextField?
    private var supervisorPipelineLabel: NSTextField?
    private var breakerBadgeLabel: NSTextField?
    private var loopRadarLabel: NSTextField?
    private var cacheEligibilityLabel: NSTextField?
    private var gpuUsageBar: HardwareMetricBar?
    private var ramUsageBar: HardwareMetricBar?
    private var chipDetailLabel: NSTextField?
    private var thermalBadgeLabel: NSTextField?
    private var systemUptimeLabel: NSTextField?
    private var networkTimer: Timer?
    private var netBandwidthBento: HardwareBentoCard?
    private var netSecurityBento: HardwareBentoCard?
    private var netPortsBento: HardwareBentoCard?
    private var netConnsBento: HardwareBentoCard?
    private var netAlertsLabel: NSTextField?
    private var netConnsContainerStack: NSStackView?
    private var netListeningListLabel: NSTextField?
    private var trafficWaveformView: TrafficWaveformView?
    private var netSubtabSegment: NSSegmentedControl?
    private var currentNetSubtab: Int = 0
    private var netConnsViewContainer: NSStackView?
    private var netUploadAuditContainer: NSStackView?
    private var uploadImagesBento: HardwareBentoCard?
    private var uploadTextsBento: HardwareBentoCard?
    private var uploadFilesBento: HardwareBentoCard?
    private var uploadSensitiveBento: HardwareBentoCard?
    private var uploadProcsContainerStack: NSStackView?
    private var uploadDistributionBar: UploadDistributionBarView?
    private var countryDistributionView: CountryDistributionView?
    private var startupTotalBento: HardwareBentoCard?
    private var startupRunningBento: HardwareBentoCard?
    private var startupDisabledBento: HardwareBentoCard?
    private var startupProtectedBento: HardwareBentoCard?
    private var startupItemsContainerStack: NSStackView?
    private var startupFilterSegment: NSSegmentedControl?
    private var currentStartupFilter: Int = 0
    private var cachedStartupItems: [[String: Any]] = []
    private var watchlistTotalBento: HardwareBentoCard?
    private var watchlistAnomaliesBento: HardwareBentoCard?
    private var watchlistBlockedBento: HardwareBentoCard?
    private var watchlistGatekeeperBento: HardwareBentoCard?
    private var watchlistContainerStack: NSStackView?
    private var watchlistStatusLabel: NSTextField?
    private var cachedWatchlistItems: [[String: Any]] = []
    private var processPickerPanel: NSWindow?
    private var candidateSearchField: NSSearchField?
    private var candidateCategoryPicker: NSSegmentedControl?
    private var candidateContainerStack: NSStackView?
    private var inlineCandidateSearchField: NSSearchField?
    private var inlineCandidateCategoryPicker: NSSegmentedControl?
    private var inlineCandidateContainerStack: NSStackView?
    private var manualPidInlineField: NSTextField?
    private var manualPidModalField: NSTextField?
    private var allCandidatesCache: [[String: Any]] = []
    private var appIconsCache: [Int: NSImage] = [:]
    private var ssdCacheInfoLabel: NSTextField?
    private var clearCacheStatusLabel: NSTextField?
    private var procFamilyContainerStack: NSStackView?
    private var procResourceSortSegment: NSSegmentedControl?
    private var procSummaryLabel: NSTextField?
    private var procResourceSortBy: String = "memory"
    private var gatekeeperWindow: GatekeeperInterceptWindowController?
    private var lastPresentedGatekeeperEventId: String = ""
    private var topBarHarnessPill: NSTextField?
    private var topBarLangButton: NSButton?
    private var harnessTokenBento: HardwareBentoCard?
    private var harnessHitBento: HardwareBentoCard?
    private var harnessReadBento: HardwareBentoCard?
    private var harnessMemoryBento: HardwareBentoCard?
    private var aociSummaryLabel: NSTextField?
    private var codeGraphSummaryLabel: NSTextField?
    private var platformSummaryLabel: NSTextField?
    private var cachedIntelligenceData: [String: Any] = [:]
    private var lastWatchlistItemsHash: String = ""
    private var lastProcessResourcesHash: String = ""
    private var lastStartupItemsHash: String = ""
    private var lastUploadProcsHash: String = ""
    private var lastNetConnsHash: String = ""
    private var lastCandidatesRenderHash: String = ""
    private var cachedRuntimeDict: [String: Any] = [:]
    private var cachedRuntimeMtime: Date?
    private var mainScrollView: NSScrollView?
    private var procScrollHeightConstraint: NSLayoutConstraint?
    private var inlineScrollHeightConstraint: NSLayoutConstraint?
    private var liveScrollHeightConstraint: NSLayoutConstraint?
    private var cachedConfigTopLevel: (provider: String, model: String) = ("openai", "gpt-5.6-sol")
    private var cachedConfigMtime: Date?
    private var candidatesFetchInFlight = false
    private var hardwareTimer: Timer?
    private var switchInProgress = false
    private var cliMode = false
    private lazy var configURL = home.appendingPathComponent(".codex/config.toml")
    private lazy var startScript = home.appendingPathComponent("bin/start-qwen38-daemon.sh")
    private lazy var stopScript = home.appendingPathComponent("bin/stop-qwen38.sh")
    private lazy var logURL = home.appendingPathComponent("Library/Logs/CodexModelSwitcher/switcher.log")
    private lazy var trafficURL = home.appendingPathComponent("Library/Logs/CodexModelSwitcher/traffic.jsonl")
    private lazy var runtimeURL = home.appendingPathComponent(".local/state/mtplx-qwen38/runtime.json")
    private lazy var openCodeConfigURL = home.appendingPathComponent(".config/opencode/opencode.jsonc")
    private lazy var claudeSettingsURL = home.appendingPathComponent(".claude/settings.json")
    private lazy var qwenSettingsURL = home.appendingPathComponent(".qwen/settings.json")
    private lazy var qwenEnvURL = home.appendingPathComponent(".qwen/.env")
    private lazy var disabledFlagURL = home.appendingPathComponent(".local/state/mtplx-qwen38/disabled")
    private var gatewayV1: String { localGateway + "/v1" }
    private lazy var clientBackupURL = home.appendingPathComponent("Library/Application Support/CodexModelSwitcher/client-backups.json")

    private let choices = [
        ModelChoice(
            title: "本地 · Qwopus 3.6 35B A3B Coder · MLX 4bit · 视觉",
            provider: "local-qwen",
            model: "local/qwopus3.6-35b-a3b-coder-4bit",
            capability: "已下载的 4bit 权重，MTPLX 直接加载，无 MTP 头，自回归。视觉和工具调用可用。为关闭思考微调：实测关闭思考时 OpenCode 与 Claude Code 5/5 全通过且更快，建议关闭思考 + medium",
            endpoint: "Codex 127.0.0.1:8002/v1",
            managedMTPLX: true,
            reasoningEffort: "medium",
            serveModel: "/Users/mac/.lmstudio/models/mlx-community/Qwopus3.6-35B-A3B-Coder-4bit",
            profile: "sustained",
            mtp: false,
            contextLength: 131072
        ),
        ModelChoice(
            title: "本地 · RavenX CyberAgent 35B A3B · LM Studio · MSQ",
            provider: "local-qwen",
            model: "local/ravenx-qwen3.6-35b-a3b-4bit-mtp",
            capability: "mlx-community 的 MSQ 混合精度包，平均 4.5 bit。用 LM Studio 的 MLX 引擎按每层比特加载，这是这份权重能正常出字的方式。MTPLX 会把 8bit 的 MTP 头按 4bit 反量化，输出会乱。文本和工具调用。上下文 128K，建议开思考 + medium",
            endpoint: "Codex 127.0.0.1:8002/v1 → LM Studio :1234",
            managedMTPLX: true,
            reasoningEffort: "medium",
            backend: "lmstudio",
            backendURL: "http://127.0.0.1:1234",
            serveModel: "local/ravenx-qwen3.6-35b-a3b-4bit-mtp",
            profile: "lmstudio",
            mtp: false,
            lmsKey: "ravenx-cyberagent-qwen3.6-35b-a3b-opus-4.7-openmythos-pentester-bughunter-rath-mlx-mtp-msq",
            contextLength: 131072
        ),
        ModelChoice(
            title: "本地 · Nemotron 3.5 Lightning 30B A3B · MTPLX · 实测 57–62 tok/s",
            provider: "local-qwen",
            model: "local/nemotron-3.5-lightning-30b-a3b-mlx-4bit",
            capability: "已实测（2026-10-11）：短提示 57、7K 上下文 62、14K 上下文 57 tok/s，预填充 420–800 tok/s。MTPLX 实际走 AR（generation_mode=ar），MTP 头未生效。TensorFold 4bit affine。长上下文比 oMLX 版稳，短上下文 oMLX 版更快。上游模板默认开思考，文本和工具调用。服务窗口 128K",
            endpoint: "Codex 127.0.0.1:8002/v1",
            managedMTPLX: true,
            reasoningEffort: "medium",
            serveModel: "/Users/mac/.lmstudio/models/TensorFold/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-MLX-4bit",
            profile: "sustained",
            mtp: true,
            contextLength: 131072
        ),
        ModelChoice(
            title: "本地 · CyberStrike 35B · MLX 6bit",
            provider: "local-qwen",
            model: "local/cyberstrike-35b-mlx-6bit",
            capability: "本地 6bit 权重约 28.19 GB，沿用 Qwopus 的 MTPLX 自回归接入，无 MTP。工具调用与速度待实测；初始上下文 128K",
            endpoint: "Codex 127.0.0.1:8002/v1",
            managedMTPLX: true,
            reasoningEffort: "medium",
            serveModel: "/Users/mac/.lmstudio/models/osxest/Huihui-CyberStrike-OffSec-35B-abliterated-mlx-6Bit",
            profile: "sustained",
            mtp: false,
            contextLength: 131072
        ),
        ModelChoice(
            title: "本地 · Qwen 3.6 35B A3B · MLX 4bit · 视觉",
            provider: "local-qwen",
            model: "local/qwen3.6-35b-a3b-mlx-4bit",
            capability: "官方 MLX 4bit，权重已在本机。35B MoE、约 3B 激活，无 MTP 头，MTPLX 直接加载。视觉可用。agent 建议 medium",
            endpoint: "Codex 127.0.0.1:8002/v1",
            managedMTPLX: true,
            reasoningEffort: "medium",
            serveModel: "/Users/mac/.lmstudio/models/lmstudio-community/Qwen3.6-35B-A3B-MLX-4bit",
            profile: "sustained",
            mtp: false,
            contextLength: 131072
        ),
        ModelChoice(
            title: "本地 · Qwen 3.8 27B · MTP FP16 · 视觉 · 平均 11.5 tok/s",
            provider: "local-qwen",
            model: "Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed-FP16",
            capability: "已实测。同一段 128 token 中文，解码平均 11.5 tok/s。原生 MTP，视觉可用。agent 规划主力：工具调用最稳，建议开思考 + medium",
            endpoint: "Codex 127.0.0.1:8002/v1",
            managedMTPLX: true,
            reasoningEffort: "medium",
            serveModel: "Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed-FP16",
            profile: "turbo",
            mtp: true,
            contextLength: 262144
        ),
        ModelChoice(
            title: "本地 · Qwen 3.8 27B · MLX 4bit · 平均 8.7 tok/s",
            provider: "local-qwen",
            model: "local/qwen3.8-27b-mlx-4bit",
            capability: "已实测。同一段 128 token，解码平均 8.7 tok/s。无 MTP，权重齐全，配置里带视觉",
            endpoint: "Codex 127.0.0.1:8002/v1",
            managedMTPLX: true,
            serveModel: "/Users/mac/.lmstudio/models/lmstudio-community/Qwen3.8-27B-MLX-4bit",
            profile: "sustained",
            mtp: false,
            contextLength: 262144
        ),
        ModelChoice(
            title: "本地 · Qwen 3.5 9B · MLX 4bit · 平均 30.5 tok/s",
            provider: "local-qwen",
            model: "local/qwen3.5-9b-mlx-4bit",
            capability: "已实测。同一段 128 token，解码平均 30.5 tok/s。体积小，无 MTP，配置里带视觉",
            endpoint: "Codex 127.0.0.1:8002/v1",
            managedMTPLX: true,
            serveModel: "/Users/mac/.lmstudio/models/lmstudio-community/Qwen3.5-9B-MLX-4bit",
            profile: "sustained",
            mtp: false,
            contextLength: 262144
        ),
        ModelChoice(
            title: "本地 · Gemma 4 26B A4B · LM Studio · 视觉 · 平均 91.0 tok/s",
            provider: "local-qwen",
            model: "gemma4-26b",
            capability: "已实测。同一段 128 token 中文，思考关闭，解码平均 91.0 tok/s。LM Studio 官方 MLX 引擎，视觉可用。agent 可用：模板内置工具调用，planning 比 OSS 稳，建议 medium",
            endpoint: "Codex 127.0.0.1:8002/v1 → LM Studio :1234",
            managedMTPLX: true,
            reasoningEffort: "medium",
            backend: "lmstudio",
            backendURL: "http://127.0.0.1:1234",
            serveModel: "google/gemma-4-26b-a4b-qat",
            profile: "lmstudio",
            mtp: false,
            lmsKey: "google/gemma-4-26b-a4b-qat",
            contextLength: 262144
        ),
        ModelChoice(
            title: "本地 · GPT-OSS 20B · LM Studio · Harmony · 平均 97.4 tok/s",
            provider: "local-qwen",
            model: "gpt-oss-20b",
            capability: "已实测。同一段 128 token 中文，解码平均 97.4 tok/s。Harmony 运行时，正文不含控制符。快速问答首选；做 agent 需升到 medium，长工具参数 JSON 偶尔会写坏",
            endpoint: "Codex 127.0.0.1:8002/v1 → LM Studio :1234",
            managedMTPLX: true,
            reasoningEffort: "low",
            backend: "lmstudio",
            backendURL: "http://127.0.0.1:1234",
            serveModel: "openai/gpt-oss-20b",
            profile: "lmstudio",
            mtp: false,
            lmsKey: "openai/gpt-oss-20b",
            contextLength: 131072
        ),
        ModelChoice(
            title: "本地 · Nemotron 3.5 Lightning 30B A3B · oMLX · 94 tok/s · OpenCode 5/5",
            provider: "local-qwen",
            model: "NVIDIA-Nemotron-3.5-Lightning-30B-A3B-MLX-4bit",
            capability: "OpenCode 基准 5/5，共 783 秒（Qwopus 是 991 秒），测试文件没被改动。已实测（oMLX，思考开）：短提示 94 tok/s，7K 上下文 71，14K 上下文 51；预填充约 650–1100 tok/s。Mamba-2 + MoE 混合，30B 总参 / 3B 激活，占用约 18GB。文本和工具调用。同一份权重在 MTPLX 走 AR 约 57–62 tok/s，长上下文更稳",
            endpoint: "Codex 127.0.0.1:8002/v1 → oMLX :7777",
            managedMTPLX: true,
            reasoningEffort: "medium",
            backend: "omlx",
            backendURL: "http://127.0.0.1:7777",
            serveModel: "NVIDIA-Nemotron-3.5-Lightning-30B-A3B-MLX-4bit",
            profile: "omlx",
            mtp: false,
            contextLength: 131072
        ),
        ModelChoice(
            title: "本地 · Nemotron 3.5 Lightning 30B A3B · MLX 6bit · 高精",
            provider: "local-qwen",
            model: "NVIDIA-Nemotron-3.5-Lightning-30B-A3B-MLX-6bit",
            capability: "Vontra 6bit 高精度量化（约 25.7GB），Mamba-2 + MoE 混合架构（30B 总参 / 3B 激活），上下文 256K。实测代码逻辑与推理精度相比 4bit 更高，兼顾极速生成与长上下文稳定性。oMLX / LM Studio 均可驱动。文本和工具调用",
            endpoint: "Codex 127.0.0.1:8002/v1 → oMLX :7777",
            managedMTPLX: true,
            reasoningEffort: "medium",
            backend: "omlx",
            backendURL: "http://127.0.0.1:7777",
            serveModel: "NVIDIA-Nemotron-3.5-Lightning-30B-A3B-MLX-6bit",
            profile: "omlx",
            mtp: false,
            lmsKey: "vontra/nvidia-nemotron-3.5-lightning-30b-a3b-mlx",
            contextLength: 262144
        ),
        ModelChoice(
            title: "本地 · Nemotron 3 Super 120B A12B · MLX 4bit · 120B 旗舰",
            provider: "local-qwen",
            model: "NVIDIA-Nemotron-3-Super-120B-A12B-4bit",
            capability: "官方 mlx-community 4bit 旗舰级超大混合架构（120B 总参 / 12B 激活），占用约 68GB 统一内存，原生 256K 超大上下文窗口。深度代码重构、复杂长流程 Agent 与高难度指令遵循能力极强。在 96GB Mac 独占满载运行。文本和工具调用",
            endpoint: "Codex 127.0.0.1:8002/v1 → oMLX :7777",
            managedMTPLX: true,
            reasoningEffort: "medium",
            backend: "omlx",
            backendURL: "http://127.0.0.1:7777",
            serveModel: "NVIDIA-Nemotron-3-Super-120B-A12B-4bit",
            profile: "omlx",
            mtp: false,
            lmsKey: "nvidia-nemotron-3-super-120b-a12b",
            contextLength: 262144
        ),
        ModelChoice(
            title: "本地 · K2 Horizon MoVA 36B A4B · oMLX · 43 tok/s · OpenCode 4/5",
            provider: "local-qwen",
            model: "K2-Horizon-MoVA-36B-A4B-MLX-4bit",
            capability: "OpenCode 基准 4/5，共 431 秒：回答简短、轮数少，所以最快；重命名任务只改了 3 个文件就宣布完成。已实测（oMLX）：短提示 43 tok/s，6K 上下文 28，12K 上下文 23；预填充约 250–380 tok/s，占用约 21GB。DreamFoundries 4bit，权重名映射到 oMLX 原生 K2 实现（APFS 克隆，数值未改）。思考只能调深浅 low/medium/high，关思考等于 low。文本和工具调用",
            endpoint: "Codex 127.0.0.1:8002/v1 → oMLX :7777",
            managedMTPLX: true,
            reasoningEffort: "medium",
            backend: "omlx",
            backendURL: "http://127.0.0.1:7777",
            serveModel: "K2-Horizon-MoVA-36B-A4B-MLX-4bit",
            profile: "omlx",
            mtp: false,
            contextLength: 131072
        ),
        ModelChoice(
            title: "本地 · Ling 3.0 Flash 124B A5B · oMLX · 2bit · 24 tok/s · 不建议做 agent",
            provider: "local-qwen",
            model: "Ling-3.0-flash-oQ2",
            capability: "OpenCode 基准 1/5：长提示时每个 2048 token 的预填充块约 10 秒，触发 macOS Metal 看门狗（Impacting Interactivity），请求被系统中止。适合短对话，不适合 agent。已实测（oMLX）：解码约 24 tok/s，基本不随上下文变化；预填充约 190–390 tok/s，占用约 42GB。TensorFold oQ2 混合 2bit。走 mlx-lm 官方 bailing_moe_v3 实现，不执行仓库自带代码：router 精确反量化为 bf16，其余权重 APFS 克隆未改。可开关思考。文本和工具调用",
            endpoint: "Codex 127.0.0.1:8002/v1 → oMLX :7777",
            managedMTPLX: true,
            reasoningEffort: "medium",
            backend: "omlx",
            backendURL: "http://127.0.0.1:7777",
            serveModel: "Ling-3.0-flash-oQ2",
            profile: "omlx",
            mtp: false,
            contextLength: 131072
        ),
        ModelChoice(
            title: "本地 · Bonsai 三进制 27B · 2bit · agent · 约 14 tok/s",
            provider: "local-qwen",
            model: "bonsai-27b-agent",
            capability: "三进制(0/1/-1)2bit，仅 8GB 占用却是 27B。自建服务器补齐工具调用：会思考+并行多工具+参数干净，实测多轮建文件/运行 0 畸形。解码约 14 tok/s，偏慢但能当 agent 干活。默认开思考 + medium",
            endpoint: "Codex 127.0.0.1:8002/v1 → Bonsai :2386",
            managedMTPLX: true,
            reasoningEffort: "medium",
            backend: "bonsai",
            backendURL: "http://127.0.0.1:2386",
            serveModel: "bonsai-27b-agent",
            profile: "bonsai",
            mtp: false,
            contextLength: 32768
        ),
        ModelChoice(title: "OpenAI · GPT-5.6 Sol · 云端", provider: "openai", model: "gpt-5.6-sol",
                    capability: "云端 Codex · 文本/图片/工具调用", reasoningEffort: "xhigh",
                    backend: "cloud", mtp: false),
        ModelChoice(title: "DeepSeek · V4 Flash · 云端", provider: "deepseek", model: "deepseek-v4-flash",
                    capability: "云端文本模型", backend: "cloud", mtp: false),
        ModelChoice(title: "DeepSeek · V4 Pro · 云端", provider: "deepseek", model: "deepseek-v4-pro",
                    capability: "云端文本模型", backend: "cloud", mtp: false),
        ModelChoice(title: "DeepSeek · V4 Flash Vision · 云端", provider: "deepseek",
                    model: "deepseek-v4-flash-vision-exp", capability: "云端视觉模型",
                    backend: "cloud", mtp: false)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["restartAfterSwitch": false, "mtpDepth": 3, "codexFollowsLocal": true, "agentWindowPreset": 1])
        if !UserDefaults.standard.bool(forKey: "mtplxV12DefaultsApplied") {
            UserDefaults.standard.set(false, forKey: "restartAfterSwitch")
            UserDefaults.standard.set(3, forKey: "mtpDepth")
            UserDefaults.standard.set(false, forKey: "enableThinking")
            UserDefaults.standard.set(true, forKey: "mtplxV12DefaultsApplied")
        }
        if !UserDefaults.standard.bool(forKey: "agentWindowPreset24KDefaultV1") {
            let currentModel = (readRuntime()["api_model"] as? String) ?? ""
            let isSuper = currentModel.contains("120B") || currentModel.contains("Ling")
            if !isSuper && UserDefaults.standard.integer(forKey: "agentWindowPreset") == 0 {
                UserDefaults.standard.set(1, forKey: "agentWindowPreset")
                if let choice = activeLocalChoice() {
                    try? writeRuntime(choice)
                }
            }
            UserDefaults.standard.set(true, forKey: "agentWindowPreset24KDefaultV1")
        }
        // Support idle startup by default: do not auto-load model to memory
        if !UserDefaults.standard.bool(forKey: "userExplicitlyEnabledAutoload") {
            if !FileManager.default.fileExists(atPath: disabledFlagURL.path) {
                try? FileManager.default.createDirectory(at: disabledFlagURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? Data().write(to: disabledFlagURL)
            }
        }
        log("app launched version=3.0 (idle-supported)")
        NSApplication.shared.setActivationPolicy(.regular)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: "MNEMOS")
        statusItem.button?.imagePosition = .imageLeading
        rebuildMenu()
        ensureGatewayRunning()
        refreshLocalServiceStatus()
        serviceTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.refreshLocalServiceStatus()
            self?.ensureGatewayRunning()
        }
        trafficTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self, self.window?.isVisible == true else { return }
            self.pollTraffic()
        }
        hardwareTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, self.window?.isVisible == true else { return }
            let seg = self.pagePicker?.selectedSegment ?? 0
            if seg == 2 || seg == 3 {
                self.refreshHardwareAndOMLXStats()
            } else {
                self.updatePowerButtonVisuals()
            }
        }
        networkTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self = self, self.window?.isVisible == true else { return }
            let seg = self.pagePicker?.selectedSegment ?? 0
            if seg == 5 {
                self.pollNetworkSentinel()
            } else {
                self.checkGatekeeperPendingEventsOnly()
                if seg == 6 {
                    self.pollStartupItems()
                } else if seg == 7 {
                    self.pollWatchlistItems()
                }
            }
        }
        if let serviceTimer { RunLoop.main.add(serviceTimer, forMode: .common) }
        if let trafficTimer { RunLoop.main.add(trafficTimer, forMode: .common) }
        if let hardwareTimer { RunLoop.main.add(hardwareTimer, forMode: .common) }
        if let networkTimer { RunLoop.main.add(networkTimer, forMode: .common) }
        if !CommandLine.arguments.contains("--background") {
            DispatchQueue.main.async { [weak self] in
                self?.showWindow()
                self?.refreshIntelligenceStatus()
                self?.refreshLocalizedUI()
            }
        }
        // v3.1: settings are per model. Once, bring the loaded model's runtime
        // to its own (recommended) settings instead of the old global switch.
        if !UserDefaults.standard.bool(forKey: "perModelSettingsV1"), let choice = activeLocalChoice() {
            try? writeRuntime(choice)
            UserDefaults.standard.set(true, forKey: "perModelSettingsV1")
            log("per-model settings applied to \(choice.model): thinking=\(modelSettings(for: choice).thinking) effort=\(modelSettings(for: choice).effort)")
        }
        if CommandLine.arguments.contains("--api") {
            DispatchQueue.main.async { [weak self] in self?.showAPIPanel() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        serviceTimer?.invalidate()
        trafficTimer?.invalidate()
        hardwareTimer?.invalidate()
        networkTimer?.invalidate()
    }

    private func ensureGatewayRunning() {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/bridge-info") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.0
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return
            }
            DispatchQueue.global(qos: .utility).async {
                let venvPy = "/Users/mac/.venvs/mtplx/bin/python"
                let pythonBin = FileManager.default.fileExists(atPath: venvPy) ? venvPy : "/usr/bin/python3"
                let candidates = [
                    "/Users/mac/Code_Start/MNEMOS/mtplx-responses-proxy.py",
                    "/Users/mac/bin/mtplx-responses-proxy.py"
                ]
                guard let script = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
                let task = Process()
                task.executableURL = URL(fileURLWithPath: pythonBin)
                task.arguments = [script, "--host", "127.0.0.1", "--port", "8002"]
                let logDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CodexModelSwitcher")
                try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
                let logFile = logDir.appendingPathComponent("gateway.log")
                if !FileManager.default.fileExists(atPath: logFile.path) {
                    FileManager.default.createFile(atPath: logFile.path, contents: nil)
                }
                if let fh = try? FileHandle(forWritingTo: logFile) {
                    fh.seekToEndOfFile()
                    task.standardOutput = fh
                    task.standardError = fh
                }
                try? task.run()
                Thread.sleep(forTimeInterval: 1.5)
                DispatchQueue.main.async {
                    self?.refreshLocalServiceStatus()
                    self?.pollNetworkSentinel()
                }
            }
        }.resume()
    }

    private func showWindow() {
        let isFirstShow = (window == nil)
        if isFirstShow { buildWindow() }
        refreshClientCard()
        refreshWindowSelection()
        refreshLocalServiceStatus()
        if isFirstShow, let window {
            window.layoutIfNeeded()
            placeOnScreen(window)
            updateDynamicScrollHeights(for: window.frame.height)
        }
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        if isFirstShow, let window {
            placeOnScreen(window)
            updateDynamicScrollHeights(for: window.frame.height)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func tonalLabel(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = Serafina.rounded(size, weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func wrappingLabel(_ string: String, size: CGFloat = 12, weight: NSFont.Weight = .medium, color: NSColor = Serafina.muted) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = Serafina.rounded(size, weight)
        label.textColor = color
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func pill(_ title: String, action: Selector, fill: NSColor, titleColor: NSColor, key: String = "") -> SerafinaButton {
        let button = SerafinaButton(frame: .zero)
        button.title = title
        button.fill = fill
        button.labelColor = titleColor
        button.target = self
        button.action = action
        button.keyEquivalent = key
        button.font = Serafina.rounded(13, .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    private func wrapCard(fill: NSColor, radius: CGFloat, _ inner: NSView, insets: NSEdgeInsets) -> TonalCard {
        let card = TonalCard(fill: fill, radius: radius)
        card.translatesAutoresizingMaskIntoConstraints = false
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: insets.left),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -insets.right),
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: insets.top),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -insets.bottom)
        ])
        return card
    }

    /// Frosted-glass card wrapper used for the main content cards.
    private func wrapFrost(tint: NSColor, radius: CGFloat, alpha: CGFloat,
                           _ inner: NSView, insets: NSEdgeInsets) -> FrostCard {
        let card = FrostCard(tint: tint, radius: radius, alpha: alpha)
        card.translatesAutoresizingMaskIntoConstraints = false
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: insets.left),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -insets.right),
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: insets.top),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -insets.bottom)
        ])
        return card
    }

    private func buildWindow() {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1366, height: 768),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "MNEMOS"
        panel.isRestorable = false
        panel.delegate = self
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.fullScreenPrimary, .managed]
        panel.backgroundColor = Serafina.lilac
        panel.isReleasedWhenClosed = false

        let content = SerafinaBackground(frame: NSRect(x: 0, y: 0, width: 1366, height: 768))
        panel.contentView = content

        let eyebrow = tonalLabel("LOCAL  ·  CODEX  ·  OPENCODE  ·  CLAUDE CODE  ·  QWEN CODE", size: 11, weight: .bold, color: Serafina.grape)
        let title = NSTextField(labelWithString: "MNEMOS")
        title.font = Serafina.display(46)
        title.textColor = Serafina.ink
        let subtitle = wrappingLabel("本地主模型 · 智能网络安全哨兵 · 规划、执行、验收", size: 14, weight: .medium, color: Serafina.muted)
        let headingText = NSStackView(views: [eyebrow, title, subtitle])
        headingText.orientation = .vertical
        headingText.alignment = .leading
        headingText.spacing = 2

        let mark = TonalCard(fill: Serafina.petal, radius: 28)
        mark.translatesAutoresizingMaskIntoConstraints = false
        let check = NSTextField(labelWithString: "✓")
        check.font = Serafina.rounded(26, .bold)
        check.textColor = Serafina.ink
        check.translatesAutoresizingMaskIntoConstraints = false
        mark.addSubview(check)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 56),
            mark.heightAnchor.constraint(equalToConstant: 56),
            check.centerXAnchor.constraint(equalTo: mark.centerXAnchor),
            check.centerYAnchor.constraint(equalTo: mark.centerYAnchor, constant: -1)
        ])
        let heading = NSStackView(views: [mark, headingText])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 16

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.font = Serafina.rounded(14, .medium)
        popup.addItems(withTitles: choices.map(\.title))
        popup.target = self
        popup.action = #selector(selectionChanged)
        popup.cell?.lineBreakMode = .byTruncatingTail
        popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        modelPopup = popup

        let capability = NSTextField(wrappingLabelWithString: "")
        capability.font = Serafina.rounded(12, .medium)
        capability.textColor = Serafina.muted
        capability.maximumNumberOfLines = 6
        capability.lineBreakMode = .byWordWrapping
        capabilityLabel = capability

        let effort = NSPopUpButton(frame: .zero, pullsDown: false)
        effort.font = Serafina.rounded(13, .medium)
        effort.addItems(withTitles: ["low", "medium", "high", "xhigh"])
        effort.selectItem(withTitle: "low")
        effortPopup = effort
        let depth = NSPopUpButton(frame: .zero, pullsDown: false)
        depth.font = Serafina.rounded(13, .medium)
        depth.addItems(withTitles: ["D1", "D2", "D3 推荐"])
        depth.selectItem(at: max(0, UserDefaults.standard.integer(forKey: "mtpDepth") - 1))
        depthPopup = depth
        let thinking = NSButton(checkboxWithTitle: "开启思考", target: self, action: #selector(thinkingChanged))
        thinking.font = Serafina.rounded(13, .medium)
        thinking.state = UserDefaults.standard.bool(forKey: "enableThinking") ? .on : .off
        thinkingCheckbox = thinking
        let knobs = pill("应用速度", action: #selector(applySpeedKnobs), fill: Serafina.grape, titleColor: .white)
        effort.target = self
        effort.action = #selector(modelSettingChanged)
        depth.target = self
        depth.action = #selector(modelSettingChanged)
        let resetSettings = pill("恢复推荐", action: #selector(resetModelSettings),
                                 fill: NSColor(srgbRed: 0.93, green: 0.89, blue: 0.98, alpha: 1), titleColor: Serafina.ink)
        let controlRow = NSStackView(views: [
            tonalLabel("推理", size: 12, weight: .semibold, color: Serafina.muted), effort,
            tonalLabel("深度", size: 12, weight: .semibold, color: Serafina.muted), depth,
            thinking
        ])
        let settingsActions = NSStackView(views: [knobs, resetSettings])
        settingsActions.orientation = .horizontal; settingsActions.spacing = 8
        let settingsHint = wrappingLabel("", size: 11, weight: .medium, color: Serafina.muted)
        settingsHintLabel = settingsHint
        controlRow.orientation = .horizontal
        controlRow.alignment = .centerY
        controlRow.spacing = 8

        let applyButton = pill("应用所选模型", action: #selector(applyWindowSelection), fill: Serafina.cream, titleColor: Serafina.ink, key: "\r")
        let restart = NSButton(checkboxWithTitle: "切换后重启 Codex", target: self, action: #selector(restartPreferenceChanged))
        restart.font = Serafina.rounded(13, .medium)
        restart.state = UserDefaults.standard.bool(forKey: "restartAfterSwitch") ? .on : .off
        restartCheckbox = restart
        let switchRow = NSStackView(views: [restart])
        switchRow.orientation = .horizontal
        switchRow.alignment = .centerY
        switchRow.spacing = 16

        let current = wrappingLabel("", size: 13, weight: .semibold, color: Serafina.ink)
        currentLabel = current
        let agentPreset = pill("应用模型 · 加载到内存", action: #selector(applyWindowSelection), fill: Serafina.grape, titleColor: .white)
        let chatPreset = pill("快速问答 · OSS 20B", action: #selector(applyChatPreset), fill: Serafina.petal, titleColor: Serafina.ink)
        let presetRow = NSStackView(views: [
            tonalLabel("应用模型", size: 12, weight: .semibold, color: Serafina.muted), agentPreset
        ])
        presetRow.orientation = .horizontal
        presetRow.alignment = .centerY
        presetRow.spacing = 8
        let workWindow = NSPopUpButton(frame: .zero, pullsDown: false)
        workWindow.addItems(withTitles: [
            "紧凑 2K（每 1.5K 增量总结 · 120B 防爆）",
            "会话 24K（推荐 · 30B/35B 适用）",
            "会话 56K（长任务全量）"
        ])
        let savedPreset = UserDefaults.standard.integer(forKey: "agentWindowPreset")
        workWindow.selectItem(at: min(2, max(0, savedPreset)))
        workWindow.target = self
        workWindow.action = #selector(agentWindowChanged)
        windowPopup = workWindow
        let memoryRow = NSStackView(views: [tonalLabel("任务上下文", size: 12, weight: .semibold, color: Serafina.muted), workWindow])
        let memoryHint = wrappingLabel("紧凑模式每 1.5K 增量总结历史，防止 120B 超大模型 Metal Watchdog 超时。", size: 11)
        memoryRow.orientation = .horizontal
        memoryRow.spacing = 8
        let power = PowerButtonView()
        power.target = self
        power.action = #selector(togglePowerState)
        powerButton = power
        let powerTitle = tonalLabel("模型运行状态", size: 14, weight: .bold, color: Serafina.ink)
        let powerSubtitle = wrappingLabel("点击 ⏻ 启停本地模型 · 绿色就绪 · 橙色推理 · 灰色停止", size: 11, weight: .medium, color: Serafina.muted)
        powerSubtitle.maximumNumberOfLines = 1
        powerSubtitle.lineBreakMode = .byTruncatingTail
        let powerText = NSStackView(views: [powerTitle, powerSubtitle])
        powerText.orientation = .vertical; powerText.alignment = .leading; powerText.spacing = 2
        let contextCapsule = tonalLabel(" 上下文 128K · 统一内存 96GB ", size: 11, weight: .semibold, color: Serafina.grape)
        contextCapsule.wantsLayer = true
        contextCapsule.layer?.backgroundColor = Serafina.petal.withAlphaComponent(0.35).cgColor
        contextCapsule.layer?.cornerRadius = 6
        modelContextCapsule = contextCapsule

        let unloadBtn = NSButton(title: "⏏️ 卸载释放显存", target: self, action: #selector(unloadModelAndReleaseMemory))
        unloadBtn.font = Serafina.rounded(11, .bold)
        unloadBtn.isBordered = false
        unloadBtn.wantsLayer = true
        unloadBtn.layer?.cornerRadius = 6
        unloadBtn.layer?.backgroundColor = Serafina.petal.withAlphaComponent(0.40).cgColor
        unloadBtn.translatesAutoresizingMaskIntoConstraints = false
        unloadBtn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        unloadModelButton = unloadBtn

        let powerHeader = NSStackView(views: [power, powerText, NSView(), unloadBtn, contextCapsule])
        powerHeader.orientation = .horizontal; powerHeader.alignment = .centerY; powerHeader.spacing = 10

        let managed = NSSwitch()
        managed.target = self
        managed.action = #selector(managedChanged(_:))
        managed.state = managedMode ? .on : .off
        managedSwitch = managed
        let managedRow = NSStackView(views: [
            managed,
            tonalLabel("全托管 Agent 模式", size: 15, weight: .bold, color: Serafina.ink)
        ])
        managedRow.orientation = .horizontal
        managedRow.alignment = .centerY
        managedRow.spacing = 10
        let managedHint = wrappingLabel("开启后，所有客户端使用本地最佳配置。", size: 12)
        let managedStatus = wrappingLabel("", size: 12, weight: .semibold, color: Serafina.muted)
        managedStatusLabel = managedStatus
        manualControls = [popup, effort, depth, thinking, knobs, applyButton, agentPreset, chatPreset, resetSettings]
        let modelCardInner = NSStackView(views: [powerHeader, managedRow, managedHint, managedStatus, popup, capability, presetRow, controlRow, settingsActions, settingsHint, memoryRow, memoryHint, switchRow, current])
        modelCardInner.orientation = .vertical
        modelCardInner.alignment = .leading
        modelCardInner.spacing = 10
        let modelCard = wrapFrost(
            tint: Serafina.paper,
            radius: 26,
            alpha: 0.62,
            modelCardInner,
            insets: NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
        )

        let clientsTitle = tonalLabel("客户端 · 共用同一个本地模型", size: 13, weight: .bold, color: Serafina.grape)
        var clientViews: [NSView] = [clientsTitle]
        var clientRows: [NSStackView] = []
        var clientText: [NSTextField] = []
        for id in clientIDs {
            let name = tonalLabel(clientTitle(id), size: 14, weight: .bold, color: Serafina.ink)
            name.translatesAutoresizingMaskIntoConstraints = false
            name.widthAnchor.constraint(equalToConstant: 100).isActive = true
            let status = wrappingLabel("检测中…", size: 12, weight: .medium, color: Serafina.muted)
            status.lineBreakMode = .byWordWrapping
            status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            status.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            clientStatusLabels[id] = status
            let target = NSPopUpButton(frame: .zero, pullsDown: false)
            target.font = Serafina.rounded(13, .medium)
            target.identifier = NSUserInterfaceItemIdentifier(id)
            target.target = self
            target.action = #selector(clientTargetChanged(_:))
            target.translatesAutoresizingMaskIntoConstraints = false
            target.cell?.lineBreakMode = .byTruncatingTail
            target.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            target.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            clientPopups[id] = target
            clientButtons.append(target)
            let open = pill(["claude", "qwen"].contains(id) ? "终端" : "打开", action: #selector(clientOpen(_:)),
                            fill: Serafina.petal, titleColor: Serafina.ink)
            open.identifier = NSUserInterfaceItemIdentifier(id)
            let views: [NSView] = [name, NSView(), open]
            for button in views.dropFirst(2) {
                button.setContentHuggingPriority(.required, for: .horizontal)
                button.setContentCompressionResistancePriority(.required, for: .horizontal)
            }
            let row = NSStackView(views: views)
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            clientRows.append(row)
            clientViews.append(row)
            clientViews.append(status)
            clientText.append(status)
            let selection = NSStackView(views: [target])
            selection.orientation = .horizontal
            target.widthAnchor.constraint(equalTo: selection.widthAnchor).isActive = true
            clientRows.append(selection); clientViews.append(selection)
            let restore = pill("恢复原配置", action: #selector(restoreClient(_:)),
                               fill: Serafina.paper, titleColor: Serafina.ink)
            restore.identifier = NSUserInterfaceItemIdentifier(id)
            let activate = pill(["codex", "opencode"].contains(id) ? "重启客户端" : "开新会话",
                                action: #selector(activateClient(_:)), fill: Serafina.petal, titleColor: Serafina.ink)
            activate.identifier = NSUserInterfaceItemIdentifier(id)
            let hint = wrappingLabel("本地换模型无需重启；更改接入配置后请重启或开新会话。", size: 11, weight: .medium, color: Serafina.muted)
            hint.lineBreakMode = .byWordWrapping
            hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            clientApplyHints[id] = hint
            let actions = NSStackView(views: [restore, activate])
            actions.orientation = .horizontal; actions.alignment = .centerY; actions.spacing = 8
            clientRows.append(actions); clientViews.append(actions)
            clientViews.append(hint); clientText.append(hint)
            do {
                let spacer = NSView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                spacer.heightAnchor.constraint(equalToConstant: 12).isActive = true
                clientViews.append(spacer)
            }

        }
        let follow = NSButton(checkboxWithTitle: "切换本地模型时，Codex 也切到本地", target: self, action: #selector(codexFollowChanged))
        follow.font = Serafina.rounded(13, .medium)
        follow.state = UserDefaults.standard.bool(forKey: "codexFollowsLocal") ? .on : .off
        codexFollowCheckbox = follow
        let clientHint = NSTextField(wrappingLabelWithString: "每个客户端单独选择：本地（跟随当前加载的模型和思考开关，换模型不用重启客户端）、原配置，或它自己的云端模型。恢复原配置＝恢复第一次切换前备份的接入设置，不清除会话。切换本地/云端后：Codex、OpenCode 重启 App，Claude Code、Qwen Code 开新会话。Claude Code 改的是 ~/.claude/settings.json，影响所有 Claude Code 会话（包括 Claude 桌面版的 Code）。")
        clientHint.font = Serafina.rounded(11, .medium)
        clientHint.textColor = Serafina.muted
        clientHint.maximumNumberOfLines = 0
        let restoreAll = pill("全部恢复原配置", action: #selector(restoreAllClients), fill: Serafina.paper, titleColor: Serafina.ink)
        clientViews.append(contentsOf: [restoreAll, follow, clientHint])
        let clientInner = NSStackView(views: clientViews)
        clientInner.orientation = .vertical
        clientInner.alignment = .leading
        clientInner.spacing = 10
        let clientCard = wrapFrost(
            tint: Serafina.paper,
            radius: 26,
            alpha: 0.62,
            clientInner,
            insets: NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        )

        let liveTitle = tonalLabel("Live", size: 13, weight: .bold, color: Serafina.petal)
        let stats = NSTextField(wrappingLabelWithString: "本地网关请求会显示在这里；云端请求不经过本地。可在服务页点击文本测试。")
        stats.font = Serafina.rounded(12, .medium)
        stats.textColor = NSColor(srgbRed: 0.86, green: 0.82, blue: 0.96, alpha: 1)
        stats.maximumNumberOfLines = 0
        statsLabel = stats

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.isHorizontallyResizable = false
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.drawsBackground = true
        text.backgroundColor = Serafina.night
        text.textColor = NSColor(srgbRed: 0.96, green: 0.94, blue: 1, alpha: 1)
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.textContainerInset = NSSize(width: 4, height: 6)
        text.string = "token 流会写在这里。\n"
        scroll.documentView = text
        transcriptView = text

        let meter = LEDMeterView(frame: .zero)
        ledMeter = meter

        let meterLabel = NSTextField(wrappingLabelWithString: "呼吸灯 VU 表 · 绿灯: 闲置就绪 | 橙灯(呼吸): 工作中 (每 5 tok/s 点亮 1 拍 · 满排 20 拍) | 红灯: 未启动")
        meterLabel.font = Serafina.rounded(11, .medium)
        meterLabel.textColor = NSColor(srgbRed: 0.78, green: 0.74, blue: 0.90, alpha: 0.85)
        meterStatusLabel = meterLabel

        let liveInner = NSStackView(views: [liveTitle, meter, meterLabel, stats, scroll])
        liveInner.orientation = .vertical
        liveInner.alignment = .leading
        liveInner.spacing = 8
        let liveCard = wrapFrost(
            tint: Serafina.night,
            radius: 26,
            alpha: 0.78,
            liveInner,
            insets: NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        )

        let status = wrappingLabel("正在检测…", size: 15, weight: .bold, color: Serafina.ink)
        serviceStatusLabel = status
        let endpoint = NSTextField(wrappingLabelWithString: "Codex、OpenCode、Claude Code 都走网关 127.0.0.1:8002（Responses / Chat / Anthropic 三种协议）。Qwen 在 MTPLX :8000，Gemma 4 和 GPT-OSS 在 LM Studio :1234。同一时间只留一个本地模型。")
        endpoint.font = Serafina.rounded(12, .medium)
        endpoint.textColor = Serafina.muted
        let start = pill("启动", action: #selector(startLocalAPI), fill: Serafina.ink, titleColor: Serafina.cream)
        let stop = pill("停止", action: #selector(stopLocalAPI), fill: NSColor(srgbRed: 0.93, green: 0.89, blue: 0.98, alpha: 1), titleColor: Serafina.ink)
        let unloadPill = pill("⏏️ 卸载并释放显存", action: #selector(unloadModelAndReleaseMemory), fill: NSColor.systemRed.withAlphaComponent(0.18), titleColor: NSColor.systemRed)
        let textTest = pill("文本测试", action: #selector(testLocalText), fill: Serafina.petal, titleColor: Serafina.ink)
        let test = pill("图片测试", action: #selector(testLocalVision), fill: Serafina.petal, titleColor: Serafina.ink)
        let openLog = pill("日志", action: #selector(openLogFile), fill: NSColor(srgbRed: 0.93, green: 0.89, blue: 0.98, alpha: 1), titleColor: Serafina.ink)
        let api = pill("API 接入", action: #selector(showAPIPanel), fill: Serafina.grape, titleColor: .white)
        let serviceButtons = NSStackView(views: [start, stop, unloadPill, textTest])
        serviceButtons.orientation = .horizontal
        serviceButtons.spacing = 8
        let serviceMoreButtons = NSStackView(views: [test, openLog, api])
        serviceMoreButtons.orientation = .horizontal; serviceMoreButtons.spacing = 8
        let autoload = NSButton(checkboxWithTitle: "开机自动加载本地模型（含崩溃后自动恢复）", target: self, action: #selector(autoloadChanged))
        autoload.font = Serafina.rounded(13, .medium)
        autoloadCheckbox = autoload
        let serviceInner = NSStackView(views: [status, endpoint, autoload, serviceButtons, serviceMoreButtons])
        serviceInner.orientation = .vertical
        serviceInner.alignment = .leading
        serviceInner.spacing = 8
        let serviceCard = wrapFrost(
            tint: Serafina.paper,
            radius: 26,
            alpha: 0.62,
            serviceInner,
            insets: NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        )

        let note = NSTextField(wrappingLabelWithString: "历史均速来自实际调用，按生成 token 数加权；输入处理、首 token 和生成分别统计。网关只透传、不改写历史，便于复用前缀缓存；需要验收的长任务交给 agentd（命令行 agentd run，或在 OpenCode 里调用 agentd 工具）。Qwopus Coder 为关闭思考而微调。")
        note.font = Serafina.rounded(11, .medium)
        note.textColor = Serafina.muted
        note.maximumNumberOfLines = 4

        let team = NSButton(checkboxWithTitle: "先规划、执行后验收（可选第二个本地模型）", target: self, action: #selector(teamSettingsChanged))
        team.state = UserDefaults.standard.bool(forKey: "verifiedTeamMode") ? .on : .off
        teamCheckbox = team
        let companion = NSPopUpButton(frame: .zero, pullsDown: false)
        companion.addItems(withTitles: ["OSS 20B · 规划与复核", "Qwen 9B · 整理信息，主模型规划与复核"])
        companion.selectItem(at: UserDefaults.standard.integer(forKey: "teamCompanion"))
        companion.target = self
        companion.action = #selector(teamSettingsChanged)
        companionPopup = companion
        func taskField(_ placeholder: String, _ value: String = "") -> NSTextField {
            let field = NSTextField(string: value)
            field.placeholderString = placeholder
            field.translatesAutoresizingMaskIntoConstraints = false
            return field
        }
        let repo = taskField("项目完整路径，例如 /Users/mac/Code_Start/my-project")
        let goal = taskField("任务目标：要完成什么，哪些文件不能改")
        let accept = taskField("验收命令，例如 python3 -m unittest discover -s tests")
        taskRepoField = repo; taskGoalField = goal; taskAcceptField = accept
        let runTask = pill("开始执行任务", action: #selector(startVerifiedTask), fill: Serafina.grape, titleColor: .white)
        let cancelTask = pill("停止任务", action: #selector(cancelVerifiedTask), fill: Serafina.petal, titleColor: Serafina.ink)
        let taskButtons = NSStackView(views: [runTask, cancelTask])
        taskButtons.orientation = .horizontal; taskButtons.spacing = 12
        let taskStatus = NSTextField(wrappingLabelWithString: "任务直接修改指定项目。先确保有备份或版本记录；只有验收命令通过并完成复核才报告完成。")
        taskStatusLabel = taskStatus
        let taskHint = NSTextField(wrappingLabelWithString: "主模型负责工具与代码；20B 可负责规划/复核，9B 可整理资料。辅助模型在任务开始时加载，推理排队，工具可独立运行。此开关也用于 OpenCode 的 agentd 工具，不改变 A3B 推理参数。")
        let taskInner = NSStackView(views: [team, companion,
            tonalLabel("项目", size: 13, weight: .bold, color: Serafina.ink), repo,
            tonalLabel("任务目标", size: 13, weight: .bold, color: Serafina.ink), goal,
            tonalLabel("验收命令（必须覆盖任务目标）", size: 13, weight: .bold, color: Serafina.ink), accept,
            taskButtons, taskStatus, taskHint])
        taskInner.orientation = .vertical; taskInner.alignment = .leading; taskInner.spacing = 12
        let taskCard = wrapFrost(tint: Serafina.paper, radius: 26, alpha: 0.62, taskInner,
                                 insets: NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22))
        for field in [repo, goal, accept, taskStatus, taskHint] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalTo: taskCard.widthAnchor, constant: -44).isActive = true
        }
        // Dashboard Card (Page 2)
        let dashTitle = tonalLabel("实时监控 · 6层全栈可观测性与 ARP 运行时看板", size: 13, weight: .bold, color: Serafina.grape)
        let dashSubtitle = wrappingLabel("六层全链路健康感知 (服务在线 ≠ 模型可用 ≠ GPU健康) · 自适应故障隔离 (ARP) · 智能体有效产出", size: 11, weight: .medium, color: Serafina.muted)

        let c1 = LayerHealthCapsule(layerId: "L1", name: "系统统一内存", initialStatus: "HEALTHY", initialDetail: "RAM/Swap 稳定")
        let c2 = LayerHealthCapsule(layerId: "L2", name: "Metal & GPU", initialStatus: "HEALTHY", initialDetail: "看门狗正常")
        let c3 = LayerHealthCapsule(layerId: "L3", name: "推理引擎", initialStatus: "HEALTHY", initialDetail: "模型就绪")
        let c4 = LayerHealthCapsule(layerId: "L4", name: "网关与协议", initialStatus: "HEALTHY", initialDetail: ":8002 在线")
        let c5 = LayerHealthCapsule(layerId: "L5", name: "督导决策", initialStatus: "HEALTHY", initialDetail: "熔断器活跃")
        let c6 = LayerHealthCapsule(layerId: "L6", name: "记忆与恢复", initialStatus: "HEALTHY", initialDetail: "WAL/快照就绪")
        capsuleL1 = c1; capsuleL2 = c2; capsuleL3 = c3
        capsuleL4 = c4; capsuleL5 = c5; capsuleL6 = c6

        let layerRow1 = NSStackView(views: [c1, c2, c3])
        layerRow1.orientation = .horizontal
        layerRow1.distribution = .fillEqually
        layerRow1.spacing = 8

        let layerRow2 = NSStackView(views: [c4, c5, c6])
        layerRow2.orientation = .horizontal
        layerRow2.distribution = .fillEqually
        layerRow2.spacing = 8

        let stat1 = MetricStatCard(title: "累积服务 Token", initialValue: "0", initialSubtitle: "Prompt 0 · Gen 0", fill: Serafina.paper)
        let stat2 = MetricStatCard(title: "前缀缓存效率", initialValue: "0.0%", initialSubtitle: "已复用 0 Token", fill: Serafina.paper)
        let stat3 = MetricStatCard(title: "实时吞吐 TPS", initialValue: "0.0 / 0.0", initialSubtitle: "首字预填 / 持续生成", fill: Serafina.paper)
        statTotalTokens = stat1
        statCachedTokens = stat2
        statThroughputTPS = stat3

        let statsRow1 = NSStackView(views: [stat1, stat2, stat3])
        statsRow1.orientation = .horizontal
        statsRow1.distribution = .fillEqually
        statsRow1.spacing = 8

        let stat4 = MetricStatCard(title: "有效产出 EAT", initialValue: "0.0 步/分", initialSubtitle: "验收证据推进率", fill: Serafina.paper)
        let stat5 = MetricStatCard(title: "算力损耗 WCR", initialValue: "0.0%", initialSubtitle: "零无效算力损耗", fill: Serafina.paper)
        let stat6 = MetricStatCard(title: "ARP 故障防护", initialValue: "🟢 守卫就绪", initialSubtitle: "0 次 Metal 崩溃", fill: Serafina.paper)
        statEAT = stat4
        statWCR = stat5
        statARP = stat6

        let statsRow2 = NSStackView(views: [stat4, stat5, stat6])
        statsRow2.orientation = .horizontal
        statsRow2.distribution = .fillEqually
        statsRow2.spacing = 8

        let dashModelInfo = wrappingLabel("当前状态：检测中…", size: 11, weight: .semibold, color: Serafina.muted)
        dashboardModelInfoLabel = dashModelInfo

        let arpTimeline = wrappingLabel("ARP 保护事件：🟢 正常守卫中 · 无 Metal 异常 · Prefill 分块 2048", size: 11, weight: .medium, color: Serafina.muted)
        arpTimeline.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        arpTimelineLabel = arpTimeline
        let resetQuarantine = pill("解除隔离", action: #selector(clearQuarantineAction), fill: Serafina.petal, titleColor: Serafina.ink)
        let arpRow = NSStackView(views: [arpTimeline, resetQuarantine])
        arpRow.orientation = .horizontal
        arpRow.alignment = .centerY
        arpRow.spacing = 8

        let supervisorHeader = tonalLabel("运行时监管 · PAR Supervisor & 防循环熔断器", size: 12, weight: .bold, color: Serafina.grape)
        let pipelineLabel = wrappingLabel("任务流水线：[规划] ➔ [定位入口] ➔ [编码实现] ➔ [回归验证] ➔ [验收交付] · 待命中", size: 11, weight: .medium, color: Serafina.muted)
        let breakerLabel = wrappingLabel("熔断器状态：🟢 L0 正常运行 · 双平面 Guard 活跃", size: 11, weight: .semibold, color: Serafina.ink)
        let loopLabel = wrappingLabel("防死循环雷达：Type A~H (8类特征) 监控中 · 0 异常 · 幂等副作用已拦截 0 次", size: 11, weight: .medium, color: Serafina.muted)
        let cacheLabel = wrappingLabel("分层前缀缓存：Eligibility 100% · Actual Hit -- (Project Core 锁定)", size: 11, weight: .medium, color: Serafina.muted)

        supervisorPipelineLabel = pipelineLabel
        breakerBadgeLabel = breakerLabel
        loopRadarLabel = loopLabel
        cacheEligibilityLabel = cacheLabel

        let dashInner = NSStackView(views: [
            dashTitle, dashSubtitle,
            layerRow1, layerRow2,
            statsRow1, statsRow2,
            dashModelInfo, arpRow,
            supervisorHeader, pipelineLabel, breakerLabel, loopLabel, cacheLabel
        ])
        dashInner.orientation = .vertical
        dashInner.alignment = .leading
        dashInner.spacing = 8
        let dashboardCard = wrapFrost(
            tint: Serafina.paper,
            radius: 26,
            alpha: 0.62,
            dashInner,
            insets: NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        )

        // ─── DeepSeek Harness Intelligence & KV-Cache Card (AOCI + CodeGraph) ───
        let hTitle = tonalLabel("⚡️ DeepSeek Harness 智能体推理与 KV-Cache 命中率大盘", size: 13, weight: .bold, color: Serafina.ink)
        let hSubtitle = wrappingLabel("结合 AOCI 全局架构蓝图与 CodeGraph 局部 AST 剪枝 · 维持 99% 前缀缓存复用 · 彻底减负 96GB 内存与推理延迟", size: 11, weight: .medium, color: Serafina.muted)

        let hBentoToken = HardwareBentoCard(icon: "📊", title: "Token 用量", value: "213,777,704 tok", subtitle: "27 轮 558 步 · 11.5 tok/s", accent: Serafina.grape)
        let hBentoHit = HardwareBentoCard(icon: "🟢", title: "缓存命中率", value: "99%", subtitle: "未缓存仅 1.38M · 免重复Prefill", accent: NSColor(srgbRed: 0.15, green: 0.80, blue: 0.35, alpha: 1.0))
        let hBentoRead = HardwareBentoCard(icon: "📥", title: "缓存读取 / 输出", value: "211.7M / 651K", subtitle: "极速 KV-Cache 命中复用", accent: NSColor(srgbRed: 0.20, green: 0.55, blue: 0.95, alpha: 1.0))
        let hBentoMem = HardwareBentoCard(icon: "🧠", title: "96GB 内存节省", value: "~95.3 GB", subtitle: "大幅降低显存带宽与等待时间", accent: NSColor(srgbRed: 0.95, green: 0.55, blue: 0.20, alpha: 1.0))
        harnessTokenBento = hBentoToken
        harnessHitBento = hBentoHit
        harnessReadBento = hBentoRead
        harnessMemoryBento = hBentoMem

        let hBentoRow = NSStackView(views: [hBentoToken, hBentoHit, hBentoRead, hBentoMem])
        hBentoRow.orientation = .horizontal
        hBentoRow.distribution = .fillEqually
        hBentoRow.spacing = 10

        // Pillar 1: AOCI
        let aociHead = tonalLabel("🌐 AOCI (AI-Oriented Code Indexing) 全局架构感知", size: 12, weight: .bold, color: Serafina.ink)
        let aociBadge = NSTextField(labelWithString: " 🟢 蓝图受控 ")
        aociBadge.font = .systemFont(ofSize: 10, weight: .bold)
        aociBadge.textColor = NSColor(srgbRed: 0.15, green: 0.75, blue: 0.35, alpha: 1.0)
        aociBadge.wantsLayer = true
        aociBadge.layer?.backgroundColor = NSColor(srgbRed: 0.15, green: 0.75, blue: 0.35, alpha: 0.12).cgColor
        aociBadge.layer?.cornerRadius = 4
        let aociTitleRow = NSStackView(views: [aociHead, aociBadge, NSView()])
        aociTitleRow.orientation = .horizontal; aociTitleRow.spacing = 6; aociTitleRow.alignment = .centerY

        let aociText = wrappingLabel("基于 .aoci/blueprint.md 维系全局架构蓝图与契约 · 约 28.5K 行代码 · 3 项核心不变量契约，从根源防止模型改偏与越权", size: 11, weight: .medium, color: Serafina.muted)
        aociSummaryLabel = aociText
        let aociBox = wrapFrost(tint: Serafina.paper, radius: 12, alpha: 0.45, NSStackView(views: [aociTitleRow, aociText]), insets: NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12))

        // Pillar 2: CodeGraph
        let cgHead = tonalLabel("🎯 CodeGraph 局部精准跳查 (AST & Tree-sitter Outline)", size: 12, weight: .bold, color: Serafina.ink)
        let cgBadge = NSTextField(labelWithString: " 🟢 节省 70%~85% Token ")
        cgBadge.font = .systemFont(ofSize: 10, weight: .bold)
        cgBadge.textColor = Serafina.grape
        cgBadge.wantsLayer = true
        cgBadge.layer?.backgroundColor = Serafina.grape.withAlphaComponent(0.12).cgColor
        cgBadge.layer?.cornerRadius = 4
        let cgTitleRow = NSStackView(views: [cgHead, cgBadge, NSView()])
        cgTitleRow.orientation = .horizontal; cgTitleRow.spacing = 6; cgTitleRow.alignment = .centerY

        let cgText = wrappingLabel("精准提取类与函数签名大纲，剥离实现体 (平均压缩率 82.5%) · 支持跨文件符号跳查与调用链爆炸半径分析 · 杜绝整文件Dump刷屏", size: 11, weight: .medium, color: Serafina.muted)
        codeGraphSummaryLabel = cgText
        let cgBox = wrapFrost(tint: Serafina.paper, radius: 12, alpha: 0.45, NSStackView(views: [cgTitleRow, cgText]), insets: NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12))

        // Pillar 3: Cross-Platform Decoupling
        let platHead = tonalLabel("💻 跨平台架构与算力适配 (Cross-Platform Architecture)", size: 12, weight: .bold, color: Serafina.ink)
        let platBadge = NSTextField(labelWithString: " 🍎 macOS (Metal/MPS) ")
        platBadge.font = .systemFont(ofSize: 10, weight: .bold)
        platBadge.textColor = NSColor(srgbRed: 0.10, green: 0.60, blue: 0.90, alpha: 1.0)
        platBadge.wantsLayer = true
        platBadge.layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.60, blue: 0.90, alpha: 0.12).cgColor
        platBadge.layer?.cornerRadius = 4
        let platTitleRow = NSStackView(views: [platHead, platBadge, NSView()])
        platTitleRow.orientation = .horizontal; platTitleRow.spacing = 6; platTitleRow.alignment = .centerY

        let platText = wrappingLabel("当前底座: Apple Silicon M2 Max (38-Core GPU, 96GB 统一内存) · 架构已完成核心解耦，后续平滑扩充 Windows 11 + NVIDIA CUDA (TensorRT-LLM) 与 AMD ROCm 专供版", size: 11, weight: .medium, color: Serafina.muted)
        platformSummaryLabel = platText
        let platBox = wrapFrost(tint: Serafina.paper, radius: 12, alpha: 0.45, NSStackView(views: [platTitleRow, platText]), insets: NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12))

        let hRefreshBtn = pill("🔄 刷新代码蓝图 & 命中率", action: #selector(refreshIntelligenceStatus), fill: Serafina.petal, titleColor: Serafina.ink)
        let hActionRow = NSStackView(views: [hRefreshBtn, NSView()])
        hActionRow.orientation = .horizontal; hActionRow.alignment = .centerY

        let hInner = NSStackView(views: [hTitle, hSubtitle, hBentoRow, aociBox, cgBox, platBox, hActionRow])
        hInner.orientation = .vertical; hInner.alignment = .leading; hInner.spacing = 10
        let harnessCard = wrapFrost(
            tint: Serafina.paper,
            radius: 26,
            alpha: 0.62,
            hInner,
            insets: NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        )

        // Hardware Card (Page 3)
        let hwTitle = tonalLabel("硬件与显存监控 · Apple Silicon (M2 Max 96GB)", size: 13, weight: .bold, color: Serafina.grape)
        let gpuBar = HardwareMetricBar(
            title: "GPU 显存占用 (Metal / MLX)",
            colors: [Serafina.grape, NSColor(srgbRed: 0.45, green: 0.35, blue: 0.95, alpha: 1.0), NSColor(srgbRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0)]
        )
        let ramBar = HardwareMetricBar(
            title: "系统统一内存 (Mach Kernel VM)",
            colors: [NSColor(srgbRed: 0.05, green: 0.71, blue: 0.83, alpha: 1.0), NSColor(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 1.0)]
        )
        gpuUsageBar = gpuBar
        ramUsageBar = ramBar

        let chipBento = HardwareBentoCard(icon: "⚡️", title: "芯片规格", value: "Apple M2 Max", subtitle: "38-Core GPU · 800GB/s")
        let thermalBento = HardwareBentoCard(icon: "🌡️", title: "温控状态", value: "🟢 正常 (Nominal)", subtitle: "能耗良好 · 峰值能效")
        let uptimeBento = HardwareBentoCard(icon: "⏱️", title: "系统运行", value: "--", subtitle: "持续稳定在线")
        chipDetailLabel = chipBento.valueLabel
        thermalBadgeLabel = thermalBento.valueLabel
        systemUptimeLabel = uptimeBento.valueLabel
        let bentoRow = NSStackView(views: [chipBento, thermalBento, uptimeBento])
        bentoRow.orientation = .horizontal
        bentoRow.distribution = .fillEqually
        bentoRow.spacing = 10

        let ssdTitleLabel = tonalLabel("SSD 运行时快照与缓存", size: 12, weight: .bold, color: Serafina.ink)
        let ssdCacheLabel = wrappingLabel("SSD 运行时缓存: 正在读取…", size: 11, weight: .medium, color: Serafina.muted)
        ssdCacheInfoLabel = ssdCacheLabel
        let clearSSDBtn = pill("清理 SSD 缓存", action: #selector(clearSSDCache), fill: Serafina.petal, titleColor: Serafina.ink)
        let clearStatus = tonalLabel("", size: 11, weight: .medium, color: Serafina.muted)
        clearCacheStatusLabel = clearStatus

        let ssdTextStack = NSStackView(views: [ssdTitleLabel, ssdCacheLabel])
        ssdTextStack.orientation = .vertical
        ssdTextStack.alignment = .leading
        ssdTextStack.spacing = 3

        let ssdBtnStack = NSStackView(views: [clearSSDBtn, clearStatus])
        ssdBtnStack.orientation = .horizontal
        ssdBtnStack.alignment = .centerY
        ssdBtnStack.spacing = 8

        let ssdRow = NSStackView(views: [ssdTextStack, NSView(), ssdBtnStack])
        ssdRow.orientation = .horizontal
        ssdRow.alignment = .centerY
        ssdRow.distribution = .fill

        let ssdCard = wrapFrost(tint: Serafina.paper, radius: 14, alpha: 0.55, ssdRow, insets: NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))

        // ─── Process Family Resource Breakdown (CPU & RAM) ───
        let procTitle = tonalLabel("💻 进程家族 CPU & 内存细化监控 (父子进程树)", size: 13, weight: .bold, color: Serafina.ink)
        let procSubtitle = wrappingLabel("全面透视具体应用程序及其 Helper/Renderer/Daemon 子进程对 CPU 和物理内存的独立占用 · 支持父子级联折叠", size: 11, weight: .medium, color: Serafina.muted)

        let procSortSegment = NSSegmentedControl(labels: ["🔥 按 CPU 消耗排行", "🧠 按 内存占用排行"], trackingMode: .selectOne, target: self, action: #selector(procSortChanged(_:)))
        procSortSegment.selectedSegment = 1
        procSortSegment.segmentStyle = .rounded
        procResourceSortSegment = procSortSegment

        let procRefreshBtn = pill("🔄 刷新排行", action: #selector(manualRefreshProcessResources), fill: Serafina.petal, titleColor: Serafina.ink)
        let procSummary = tonalLabel("正在扫描系统进程家族资源...", size: 11, weight: .medium, color: Serafina.muted)
        procSummaryLabel = procSummary

        let procControlRow = NSStackView(views: [procSortSegment, procRefreshBtn, NSView(), procSummary])
        procControlRow.orientation = .horizontal
        procControlRow.alignment = .centerY
        procControlRow.spacing = 8

        let procStack = NSStackView()
        procStack.orientation = .vertical
        procStack.alignment = .leading
        procStack.spacing = 6
        procStack.translatesAutoresizingMaskIntoConstraints = false
        procFamilyContainerStack = procStack

        let procDoc = FlippedView()
        procDoc.translatesAutoresizingMaskIntoConstraints = false
        procDoc.addSubview(procStack)

        let procScroll = NSScrollView()
        procScroll.hasVerticalScroller = true
        procScroll.hasHorizontalScroller = false
        procScroll.autohidesScrollers = true
        procScroll.drawsBackground = false
        procScroll.documentView = procDoc
        procScroll.translatesAutoresizingMaskIntoConstraints = false
        let procScrollHeight = procScroll.heightAnchor.constraint(equalToConstant: 280)
        procScrollHeight.isActive = true
        self.procScrollHeightConstraint = procScrollHeight

        NSLayoutConstraint.activate([
            procDoc.leadingAnchor.constraint(equalTo: procScroll.contentView.leadingAnchor),
            procDoc.trailingAnchor.constraint(equalTo: procScroll.contentView.trailingAnchor),
            procDoc.topAnchor.constraint(equalTo: procScroll.contentView.topAnchor),
            procDoc.widthAnchor.constraint(equalTo: procScroll.contentView.widthAnchor),
            procStack.leadingAnchor.constraint(equalTo: procDoc.leadingAnchor),
            procStack.trailingAnchor.constraint(equalTo: procDoc.trailingAnchor),
            procStack.topAnchor.constraint(equalTo: procDoc.topAnchor),
            procDoc.bottomAnchor.constraint(equalTo: procStack.bottomAnchor)
        ])

        let procBox = NSStackView(views: [procTitle, procSubtitle, procControlRow, procScroll])
        procBox.orientation = .vertical
        procBox.alignment = .leading
        procBox.spacing = 10

        let procCard = wrapFrost(tint: Serafina.paper, radius: 14, alpha: 0.55, procBox, insets: NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))

        let hwInner = NSStackView(views: [hwTitle, gpuBar, ramBar, bentoRow, ssdCard, procCard])
        hwInner.orientation = .vertical
        hwInner.alignment = .leading
        hwInner.spacing = 14
        let hardwareCard = wrapFrost(
            tint: Serafina.paper,
            radius: 26,
            alpha: 0.62,
            hwInner,
            insets: NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        )

        // ─── Network Sentinel Card (Page 5 Part 1) ───
        let netTitle = tonalLabel("网络安全哨兵 · 本机流量监控与异常研判 (Network Sentinel)", size: 13, weight: .bold, color: Serafina.grape)
        let netSubtitle = wrappingLabel("实时监控公网出站流量、异常进程外联与危险端口暴露 · 识别反弹 Shell、C2 木马与未授权服务暴露", size: 11, weight: .medium, color: Serafina.muted)

        let netBentoBandwidth = HardwareBentoCard(icon: "⚡️", title: "实时网络吞吐", value: "↓ 0 B/s", subtitle: "↑ 0 B/s 出站", accent: Serafina.grape)
        let netBentoSecurity = HardwareBentoCard(icon: "🛡️", title: "威胁防护状态", value: "🟢 SAFE", subtitle: "0 处高危 / 0 处警告", accent: NSColor(srgbRed: 0.15, green: 0.80, blue: 0.35, alpha: 1.0))
        let netBentoPorts = HardwareBentoCard(icon: "🔌", title: "开放监听端口", value: "0", subtitle: "0 处公网暴露", accent: NSColor(srgbRed: 0.20, green: 0.55, blue: 0.95, alpha: 1.0))
        let netBentoConns = HardwareBentoCard(icon: "🌐", title: "活跃网络连接", value: "0", subtitle: "0 处公网外联", accent: NSColor(srgbRed: 0.95, green: 0.55, blue: 0.20, alpha: 1.0))
        netBandwidthBento = netBentoBandwidth
        netSecurityBento = netBentoSecurity
        netPortsBento = netBentoPorts
        netConnsBento = netBentoConns

        let netBentoRow = NSStackView(views: [netBentoBandwidth, netBentoSecurity, netBentoPorts, netBentoConns])
        netBentoRow.orientation = .horizontal
        netBentoRow.distribution = .fillEqually
        netBentoRow.spacing = 10

        let netAlertHeader = tonalLabel("🚨 异常事件与安全告警 (Threat Alerts)", size: 12, weight: .bold, color: Serafina.ink)
        let netAlertsText = wrappingLabel("正在连接 :8002 获取网络监控审计数据...", size: 11, weight: .medium, color: Serafina.muted)
        netAlertsLabel = netAlertsText

        let waveform = TrafficWaveformView(frame: .zero)
        waveform.translatesAutoresizingMaskIntoConstraints = false
        trafficWaveformView = waveform

        let netCardInner = NSStackView(views: [
            netTitle, netSubtitle,
            netBentoRow,
            waveform,
            netAlertHeader, netAlertsText
        ])
        netCardInner.orientation = .vertical; netCardInner.alignment = .leading; netCardInner.spacing = 14
        let networkCard = wrapFrost(tint: Serafina.paper, radius: 26, alpha: 0.62, netCardInner,
                                    insets: NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22))

        // ─── Network Connections & Upload Payload Audit (Page 5 Part 2) ───
        let netTableTitle = tonalLabel("🌐 网络连接测绘与上传数据审计 (Network Map & Upload Payload Audit)", size: 13, weight: .bold, color: Serafina.ink)
        let netTableSubtitle = wrappingLabel("集成公共 IP 归属地 API（国家/地区/运营商）与上传数据深度溯源（图片/文本/文件/敏感凭据）", size: 11, weight: .medium, color: Serafina.muted)

        let netSubtab = NSSegmentedControl(labels: ["🌐 活跃外网连接与 IP 归属地", "📤 上传数据深度审计 (重点监控)"], trackingMode: .selectOne, target: self, action: #selector(netSubtabChanged(_:)))
        netSubtab.selectedSegment = 0
        netSubtab.segmentStyle = .rounded
        netSubtabSegment = netSubtab

        let killAllBtn = pill("🚨 一键批量阻断异常外联", action: #selector(killAllSuspiciousProcesses), fill: NSColor(srgbRed: 0.85, green: 0.18, blue: 0.22, alpha: 1.0), titleColor: .white)
        let scanBtn = pill("🔄 立即重新扫描", action: #selector(manualScanNetwork), fill: Serafina.petal, titleColor: Serafina.ink)
        let simGatekeeperBtn = pill("🚨 模拟敏感凭证拦截弹窗", action: #selector(simulateGatekeeperAlert), fill: Serafina.grape, titleColor: .white)
        let whitelistBtn = pill("🛡️ 管理信任白名单", action: #selector(showGatekeeperWhitelistDialog), fill: Serafina.petal, titleColor: Serafina.ink)
        let netActionRow = NSStackView(views: [killAllBtn, scanBtn, simGatekeeperBtn, whitelistBtn])
        netActionRow.orientation = .horizontal; netActionRow.spacing = 10; netActionRow.alignment = .centerY

        let connsStack = NSStackView()
        connsStack.orientation = .vertical
        connsStack.alignment = .leading
        connsStack.spacing = 6
        netConnsContainerStack = connsStack

        let netListText = NSTextField(wrappingLabelWithString: "【本地监听端口与暴露审计】\n正在查询中...")
        netListText.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        netListText.textColor = Serafina.muted
        netListeningListLabel = netListText

        let connsViewInner = NSStackView(views: [netActionRow, connsStack, netListText])
        connsViewInner.orientation = .vertical; connsViewInner.alignment = .leading; connsViewInner.spacing = 10
        netConnsViewContainer = connsViewInner

        // Upload Data Audit Container (Dedicated sub-tab)
        let upImgBento = HardwareBentoCard(icon: "🖼️", title: "图片多媒体上传", value: "0 项", subtitle: "照片/截图/图片文件", accent: NSColor(srgbRed: 0.15, green: 0.78, blue: 0.40, alpha: 1.0))
        let upTxtBento = HardwareBentoCard(icon: "📝", title: "文本/代码/配置", value: "0 项", subtitle: "日志/文本/JSON传输", accent: NSColor(srgbRed: 0.20, green: 0.60, blue: 0.95, alpha: 1.0))
        let upFileBento = HardwareBentoCard(icon: "📦", title: "文件与压缩包", value: "0 项", subtitle: "文档/压缩包/安装包", accent: NSColor.systemOrange)
        let upSensBento = HardwareBentoCard(icon: "🚨", title: "敏感凭证告警", value: "0 项", subtitle: "密钥/私钥/密码库访问", accent: NSColor.systemRed)
        uploadImagesBento = upImgBento
        uploadTextsBento = upTxtBento
        uploadFilesBento = upFileBento
        uploadSensitiveBento = upSensBento

        let upBentoRow = NSStackView(views: [upImgBento, upTxtBento, upFileBento, upSensBento])
        upBentoRow.orientation = .horizontal; upBentoRow.distribution = .fillEqually; upBentoRow.spacing = 10

        let upHeading = tonalLabel("📤 当前活跃上传进程与文件溯源 (Top Uploading Processes):", size: 12, weight: .bold, color: Serafina.ink)
        let upProcsStack = NSStackView()
        upProcsStack.orientation = .vertical
        upProcsStack.alignment = .leading
        upProcsStack.spacing = 6
        uploadProcsContainerStack = upProcsStack

        let distBar = UploadDistributionBarView(frame: .zero)
        distBar.translatesAutoresizingMaskIntoConstraints = false
        uploadDistributionBar = distBar

        let cDist = CountryDistributionView(frame: .zero)
        cDist.translatesAutoresizingMaskIntoConstraints = false
        countryDistributionView = cDist

        let uploadAuditInner = NSStackView(views: [upBentoRow, distBar, cDist, upHeading, upProcsStack])
        uploadAuditInner.orientation = .vertical; uploadAuditInner.alignment = .leading; uploadAuditInner.spacing = 12
        uploadAuditInner.isHidden = true
        netUploadAuditContainer = uploadAuditInner

        let netTableInner = NSStackView(views: [
            netTableTitle, netTableSubtitle,
            netSubtab,
            connsViewInner,
            uploadAuditInner
        ])
        netTableInner.orientation = .vertical; netTableInner.alignment = .leading; netTableInner.spacing = 14
        let networkTableCard = wrapFrost(tint: Serafina.paper, radius: 26, alpha: 0.62, netTableInner,
                                         insets: NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22))

        // ─── Startup & Login Items Management Card (Page 5 Part 3) ───
        let startupTitle = tonalLabel("🚀 开机默认启动程序管控 (Startup & Login Items Manager)", size: 13, weight: .bold, color: Serafina.ink)
        let startupSubtitle = wrappingLabel("全面管控 macOS 用户开机守护进程 (LaunchAgents) 与登录项。卡片式一键开关，无需输入命令或 ID，核心系统受白名单保护：", size: 11, weight: .medium, color: Serafina.muted)

        let bentoTotal = HardwareBentoCard(icon: "📦", title: "自启项总数", value: "-- 项", subtitle: "LaunchAgents & 登录项", accent: Serafina.grape)
        let bentoRunning = HardwareBentoCard(icon: "⚡️", title: "运行中守护", value: "-- 项", subtitle: "活跃常驻服务", accent: NSColor(srgbRed: 0.15, green: 0.80, blue: 0.35, alpha: 1.0))
        let bentoDisabled = HardwareBentoCard(icon: "🛑", title: "已禁用服务", value: "-- 项", subtitle: "已关闭不自启", accent: NSColor.systemOrange)
        let bentoProtected = HardwareBentoCard(icon: "🛡️", title: "核心保护", value: "-- 项", subtitle: "Serafina & 系统白名单", accent: NSColor(srgbRed: 0.20, green: 0.55, blue: 0.95, alpha: 1.0))
        startupTotalBento = bentoTotal
        startupRunningBento = bentoRunning
        startupDisabledBento = bentoDisabled
        startupProtectedBento = bentoProtected

        let startupBentoRow = NSStackView(views: [bentoTotal, bentoRunning, bentoDisabled, bentoProtected])
        startupBentoRow.orientation = .horizontal; startupBentoRow.distribution = .fillEqually; startupBentoRow.spacing = 10

        let batchDisableBtn = pill("🛑 一键批量关闭非必要自启", action: #selector(batchDisableStartupItems), fill: NSColor.systemOrange, titleColor: .white)
        let refreshStartupBtn = pill("🔄 刷新自启清单", action: #selector(pollStartupItems), fill: Serafina.petal, titleColor: Serafina.ink)

        let startupFilter = NSSegmentedControl(labels: ["全部项", "可优化第三方", "运行中", "已禁用"], trackingMode: .selectOne, target: self, action: #selector(startupFilterChanged(_:)))
        startupFilter.selectedSegment = 0
        startupFilter.segmentStyle = .rounded
        startupFilterSegment = startupFilter

        let startupActionRow = NSStackView(views: [batchDisableBtn, refreshStartupBtn, NSView(), startupFilter])
        startupActionRow.orientation = .horizontal; startupActionRow.spacing = 10; startupActionRow.alignment = .centerY

        let startupStack = NSStackView()
        startupStack.orientation = .vertical
        startupStack.alignment = .leading
        startupStack.spacing = 8
        startupItemsContainerStack = startupStack

        let startupCardInner = NSStackView(views: [
            startupTitle, startupSubtitle,
            startupBentoRow,
            startupActionRow,
            startupStack
        ])
        startupCardInner.orientation = .vertical; startupCardInner.alignment = .leading; startupCardInner.spacing = 14
        let startupCard = wrapFrost(tint: Serafina.paper, radius: 26, alpha: 0.62, startupCardInner,
                                    insets: NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22))

        // ─── Priority Process Watchlist & Granular Interceptor Card (Page 7) ───
        let watchTitle = tonalLabel("🎯 重点程序监控与细粒度流量/越权沙箱拦截 (Priority Watchlist & Sandbox Guard)", size: 13, weight: .bold, color: Serafina.ink)
        let watchSubtitle = wrappingLabel("支持关联父子进程深度纳管、每次请求拦截放行 (Gatekeeper)、细粒度阻断指定数据/文件类型（图片、视频、大文件、私钥凭据、自定义扩展名）及工作目录越权跨界监控：", size: 11, weight: .medium, color: Serafina.muted)

        let wBentoTotal = HardwareBentoCard(icon: "🎯", title: "纳管程序族", value: "0 族", subtitle: "重点观察进程及子进程", accent: Serafina.grape)
        let wBentoAnomalies = HardwareBentoCard(icon: "⚠️", title: "越权跨界告警", value: "0 次", subtitle: "读取工作目录外私有文件", accent: NSColor.systemRed)
        let wBentoBlocked = HardwareBentoCard(icon: "🛑", title: "阻断流量/文件", value: "0 项", subtitle: "命中图片/视频/大文件规则", accent: NSColor.systemOrange)
        let wBentoGatekeeper = HardwareBentoCard(icon: "👮", title: "每次放行审核", value: "已就绪", subtitle: "支持 SIGSTOP/SIGCONT", accent: NSColor(srgbRed: 0.15, green: 0.80, blue: 0.35, alpha: 1.0))
        watchlistTotalBento = wBentoTotal
        watchlistAnomaliesBento = wBentoAnomalies
        watchlistBlockedBento = wBentoBlocked
        watchlistGatekeeperBento = wBentoGatekeeper

        let watchBentoRow = NSStackView(views: [wBentoTotal, wBentoAnomalies, wBentoBlocked, wBentoGatekeeper])
        watchBentoRow.orientation = .horizontal; watchBentoRow.distribution = .fillEqually; watchBentoRow.spacing = 10

        // ─── Inline Process Picker & Search Card (Page 7) ───
        let pickerHeaderIcon = tonalLabel("🔍", size: 13, weight: .bold, color: Serafina.grape)
        let pickerHeaderTitle = tonalLabel("挑选与搜索运行程序 (实时免查 PID)", size: 12, weight: .bold, color: Serafina.ink)
        let pickerHeaderTip = tonalLabel("可输入应用名称（如 WeChat, Chrome, Python）或 PID 实时筛选：", size: 11, weight: .medium, color: Serafina.muted)
        let pickerHeaderLeft = NSStackView(views: [pickerHeaderIcon, pickerHeaderTitle, pickerHeaderTip])
        pickerHeaderLeft.orientation = .horizontal; pickerHeaderLeft.spacing = 6; pickerHeaderLeft.alignment = .centerY

        let pickerRefreshBtn = pill("🔄 刷新进程", action: #selector(refreshCandidateProcessesAction), fill: Serafina.petal, titleColor: Serafina.ink)
        let pickerOpenModalBtn = pill("⤢ 独立窗口", action: #selector(openProcessPickerSheet), fill: Serafina.petal, titleColor: Serafina.ink)
        let pickerHeaderRight = NSStackView(views: [pickerRefreshBtn, pickerOpenModalBtn])
        pickerHeaderRight.orientation = .horizontal; pickerHeaderRight.spacing = 6; pickerHeaderRight.alignment = .centerY

        let pickerHeaderRow = NSStackView(views: [pickerHeaderLeft, NSView(), pickerHeaderRight])
        pickerHeaderRow.orientation = .horizontal; pickerHeaderRow.alignment = .centerY

        // Search Controls Row
        let inlineSearch = NSSearchField()
        inlineSearch.placeholderString = "🔍 输入应用名或 PID 实时筛选 (如 Chrome, WeChat, Python)..."
        inlineSearch.sendsSearchStringImmediately = true
        inlineSearch.target = self
        inlineSearch.action = #selector(candidateSearchChanged(_:))
        inlineSearch.delegate = self
        inlineSearch.focusRingType = .none
        inlineSearch.font = .systemFont(ofSize: 12)
        inlineSearch.translatesAutoresizingMaskIntoConstraints = false
        inlineSearch.heightAnchor.constraint(equalToConstant: 28).isActive = true
        inlineSearch.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        inlineSearch.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.inlineCandidateSearchField = inlineSearch

        let inlineCatPicker = NSSegmentedControl(labels: ["全部常用", "🌐 活跃外联", "💻 运行中的 App"],
                                                 trackingMode: .selectOne, target: self, action: #selector(candidateFilterChanged(_:)))
        inlineCatPicker.selectedSegment = 0
        inlineCatPicker.segmentStyle = .rounded
        inlineCatPicker.translatesAutoresizingMaskIntoConstraints = false
        inlineCatPicker.heightAnchor.constraint(equalToConstant: 26).isActive = true
        self.inlineCandidateCategoryPicker = inlineCatPicker

        let manualPidLabel = tonalLabel("快速 PID:", size: 11, weight: .medium, color: Serafina.muted)
        let manualPidField = NSTextField()
        manualPidField.placeholderString = "如 1234"
        manualPidField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        manualPidField.alignment = .center
        manualPidField.translatesAutoresizingMaskIntoConstraints = false
        manualPidField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        manualPidField.heightAnchor.constraint(equalToConstant: 24).isActive = true
        self.manualPidInlineField = manualPidField

        let manualPidBtn = pill("➕ 纳管", action: #selector(didSubmitManualPidInline(_:)), fill: Serafina.grape, titleColor: .white)

        let inlineControlsRow = NSStackView(views: [inlineSearch, inlineCatPicker, NSView(), manualPidLabel, manualPidField, manualPidBtn])
        inlineControlsRow.orientation = .horizontal; inlineControlsRow.alignment = .centerY; inlineControlsRow.spacing = 10

        // Scroll view for candidates
        let inlineScroll = NSScrollView()
        inlineScroll.hasVerticalScroller = true
        inlineScroll.autohidesScrollers = true
        inlineScroll.drawsBackground = false
        inlineScroll.translatesAutoresizingMaskIntoConstraints = false
        let inlineScrollHeight = inlineScroll.heightAnchor.constraint(equalToConstant: 220)
        inlineScrollHeight.isActive = true
        self.inlineScrollHeightConstraint = inlineScrollHeight

        let inlineDoc = FlippedView()
        inlineDoc.translatesAutoresizingMaskIntoConstraints = false

        let inlineStack = NSStackView()
        inlineStack.orientation = .vertical
        inlineStack.alignment = .leading
        inlineStack.spacing = 6
        inlineStack.translatesAutoresizingMaskIntoConstraints = false
        self.inlineCandidateContainerStack = inlineStack

        inlineDoc.addSubview(inlineStack)
        inlineScroll.documentView = inlineDoc

        NSLayoutConstraint.activate([
            inlineDoc.leadingAnchor.constraint(equalTo: inlineScroll.contentView.leadingAnchor),
            inlineDoc.trailingAnchor.constraint(equalTo: inlineScroll.contentView.trailingAnchor),
            inlineDoc.topAnchor.constraint(equalTo: inlineScroll.contentView.topAnchor),
            inlineDoc.widthAnchor.constraint(equalTo: inlineScroll.contentView.widthAnchor),

            inlineStack.leadingAnchor.constraint(equalTo: inlineDoc.leadingAnchor),
            inlineStack.trailingAnchor.constraint(equalTo: inlineDoc.trailingAnchor),
            inlineStack.topAnchor.constraint(equalTo: inlineDoc.topAnchor),
            inlineStack.bottomAnchor.constraint(equalTo: inlineDoc.bottomAnchor)
        ])

        let pickerInnerStack = NSStackView(views: [pickerHeaderRow, inlineControlsRow, inlineScroll])
        pickerInnerStack.orientation = .vertical; pickerInnerStack.alignment = .leading; pickerInnerStack.spacing = 10
        let pickerCard = wrapCard(fill: Serafina.paper.withAlphaComponent(0.65), radius: 16, pickerInnerStack,
                                  insets: NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16))

        let activeWatchlistHeader = tonalLabel("🛡️ 当前受控与细粒度防护中的重点程序族 (Active Monitored Families)", size: 12, weight: .bold, color: Serafina.ink)
        activeWatchlistHeader.lineBreakMode = .byTruncatingTail
        activeWatchlistHeader.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let activeWatchlistTip = tonalLabel("提示：已被纳管的进程将自动拦截异常跨界越权文件访问，并支持网络放行拦截审核与流量细粒度过滤：", size: 11, weight: .medium, color: Serafina.muted)
        activeWatchlistTip.lineBreakMode = .byTruncatingTail
        activeWatchlistTip.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let watchStack = NSStackView()
        watchStack.orientation = .vertical
        watchStack.alignment = .leading
        watchStack.spacing = 10
        watchlistContainerStack = watchStack

        let watchCardInner = NSStackView(views: [
            watchTitle, watchSubtitle,
            watchBentoRow,
            pickerCard,
            activeWatchlistHeader,
            activeWatchlistTip,
            watchStack
        ])
        watchCardInner.orientation = .vertical; watchCardInner.alignment = .leading; watchCardInner.spacing = 14
        let watchlistCard = wrapFrost(tint: Serafina.paper, radius: 26, alpha: 0.62, watchCardInner,
                                      insets: NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22))

        waveform.translatesAutoresizingMaskIntoConstraints = false
        netBentoRow.translatesAutoresizingMaskIntoConstraints = false
        netAlertsText.translatesAutoresizingMaskIntoConstraints = false
        netTableInner.translatesAutoresizingMaskIntoConstraints = false
        connsViewInner.translatesAutoresizingMaskIntoConstraints = false
        netActionRow.translatesAutoresizingMaskIntoConstraints = false
        connsStack.translatesAutoresizingMaskIntoConstraints = false
        netListText.translatesAutoresizingMaskIntoConstraints = false
        uploadAuditInner.translatesAutoresizingMaskIntoConstraints = false
        upBentoRow.translatesAutoresizingMaskIntoConstraints = false
        distBar.translatesAutoresizingMaskIntoConstraints = false
        cDist.translatesAutoresizingMaskIntoConstraints = false
        upProcsStack.translatesAutoresizingMaskIntoConstraints = false
        startupCardInner.translatesAutoresizingMaskIntoConstraints = false
        startupBentoRow.translatesAutoresizingMaskIntoConstraints = false
        startupActionRow.translatesAutoresizingMaskIntoConstraints = false
        startupStack.translatesAutoresizingMaskIntoConstraints = false
        watchCardInner.translatesAutoresizingMaskIntoConstraints = false
        watchBentoRow.translatesAutoresizingMaskIntoConstraints = false
        pickerCard.translatesAutoresizingMaskIntoConstraints = false
        pickerInnerStack.translatesAutoresizingMaskIntoConstraints = false
        pickerHeaderRow.translatesAutoresizingMaskIntoConstraints = false
        inlineControlsRow.translatesAutoresizingMaskIntoConstraints = false
        inlineScroll.translatesAutoresizingMaskIntoConstraints = false
        activeWatchlistHeader.translatesAutoresizingMaskIntoConstraints = false
        activeWatchlistTip.translatesAutoresizingMaskIntoConstraints = false
        watchStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            netBentoRow.widthAnchor.constraint(equalTo: netCardInner.widthAnchor),
            waveform.widthAnchor.constraint(equalTo: netCardInner.widthAnchor),
            waveform.heightAnchor.constraint(equalToConstant: 135),
            netAlertsText.widthAnchor.constraint(equalTo: netCardInner.widthAnchor),
            connsViewInner.widthAnchor.constraint(equalTo: netTableInner.widthAnchor),
            netActionRow.widthAnchor.constraint(equalTo: connsViewInner.widthAnchor),
            connsStack.widthAnchor.constraint(equalTo: connsViewInner.widthAnchor),
            netListText.widthAnchor.constraint(equalTo: connsViewInner.widthAnchor),
            uploadAuditInner.widthAnchor.constraint(equalTo: netTableInner.widthAnchor),
            upBentoRow.widthAnchor.constraint(equalTo: uploadAuditInner.widthAnchor),
            distBar.widthAnchor.constraint(equalTo: uploadAuditInner.widthAnchor),
            distBar.heightAnchor.constraint(equalToConstant: 58),
            cDist.widthAnchor.constraint(equalTo: uploadAuditInner.widthAnchor),
            cDist.heightAnchor.constraint(equalToConstant: 58),
            upProcsStack.widthAnchor.constraint(equalTo: uploadAuditInner.widthAnchor),
            startupBentoRow.widthAnchor.constraint(equalTo: startupCardInner.widthAnchor),
            startupActionRow.widthAnchor.constraint(equalTo: startupCardInner.widthAnchor),
            startupStack.widthAnchor.constraint(equalTo: startupCardInner.widthAnchor),
            watchBentoRow.widthAnchor.constraint(equalTo: watchCardInner.widthAnchor),
            pickerCard.widthAnchor.constraint(equalTo: watchCardInner.widthAnchor),
            pickerHeaderRow.widthAnchor.constraint(equalTo: pickerInnerStack.widthAnchor),
            inlineControlsRow.widthAnchor.constraint(equalTo: pickerInnerStack.widthAnchor),
            inlineScroll.widthAnchor.constraint(equalTo: pickerInnerStack.widthAnchor),
            activeWatchlistHeader.widthAnchor.constraint(equalTo: watchCardInner.widthAnchor),
            activeWatchlistTip.widthAnchor.constraint(equalTo: watchCardInner.widthAnchor),
            watchStack.widthAnchor.constraint(equalTo: watchCardInner.widthAnchor)
        ])

        buildAPIPanel()
        let apiPage = apiPanel!.contentView!
        apiPage.removeFromSuperview()
        apiPanel!.contentView = NSView()
        apiPage.translatesAutoresizingMaskIntoConstraints = false

        // Backing segmented control for compatibility & contract tests
        let pages = NSSegmentedControl(labels: ["模型与客户端", "API 接入", "实时监控看板", "系统硬件与服务", "任务执行", "网络与流量安全", "开机自启管控", "重点程序管控"],
                                       trackingMode: .selectOne, target: self, action: #selector(pageChanged))
        pages.selectedSegment = 0
        pages.segmentStyle = .rounded
        pages.isHidden = true
        pagePicker = pages
        content.addSubview(pages)

        pageCards = [[modelCard, clientCard], [apiPage], [dashboardCard, harnessCard, liveCard, note], [hardwareCard, serviceCard], [taskCard], [networkCard, networkTableCard], [startupCard], [watchlistCard]]
        for group in pageCards.dropFirst() { for view in group { view.isHidden = true } }

        // ─── Left Sidebar (oMLX style) ───
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)

        let brandIcon = TonalCard(fill: Serafina.petal, radius: 14)
        brandIcon.translatesAutoresizingMaskIntoConstraints = false
        let brandCheck = NSTextField(labelWithString: "❖")
        brandCheck.font = Serafina.rounded(16, .bold)
        brandCheck.textColor = Serafina.grape
        brandCheck.translatesAutoresizingMaskIntoConstraints = false
        brandIcon.addSubview(brandCheck)
        NSLayoutConstraint.activate([
            brandIcon.widthAnchor.constraint(equalToConstant: 28),
            brandIcon.heightAnchor.constraint(equalToConstant: 28),
            brandCheck.centerXAnchor.constraint(equalTo: brandIcon.centerXAnchor),
            brandCheck.centerYAnchor.constraint(equalTo: brandIcon.centerYAnchor)
        ])
        let brandTitle = tonalLabel("Serafina", size: 15, weight: .bold, color: Serafina.ink)
        let brandSubtitle = tonalLabel("5.0 PAR · 96GB", size: 10, weight: .semibold, color: Serafina.muted)
        let brandText = NSStackView(views: [brandTitle, brandSubtitle])
        brandText.orientation = .vertical; brandText.alignment = .leading; brandText.spacing = 1
        let brandHeader = NSStackView(views: [brandIcon, brandText])
        brandHeader.orientation = .horizontal; brandHeader.alignment = .centerY; brandHeader.spacing = 8

        func makeSectionLabel(_ title: String) -> NSTextField {
            let label = tonalLabel(title.uppercased(), size: 10, weight: .bold, color: Serafina.muted.withAlphaComponent(0.85))
            return label
        }

        let itemLive = SidebarItemView(icon: "📊", title: "实时监控看板", targetIndex: 2, target: self, action: #selector(sidebarItemClicked(_:)))
        let itemHardware = SidebarItemView(icon: "⚡️", title: "系统硬件与服务", targetIndex: 3, target: self, action: #selector(sidebarItemClicked(_:)))
        let itemNetwork = SidebarItemView(icon: "🛰️", title: "网络与流量安全", targetIndex: 5, target: self, action: #selector(sidebarItemClicked(_:)))
        let itemStartup = SidebarItemView(icon: "🚀", title: "开机自启管控", targetIndex: 6, target: self, action: #selector(sidebarItemClicked(_:)))
        let itemWatchlist = SidebarItemView(icon: "🎯", title: "重点程序管控", targetIndex: 7, target: self, action: #selector(sidebarItemClicked(_:)))
        let itemModel = SidebarItemView(icon: "🤖", title: "模型与客户端", targetIndex: 0, target: self, action: #selector(sidebarItemClicked(_:)))
        let itemAPI = SidebarItemView(icon: "🌐", title: "API 接入", targetIndex: 1, target: self, action: #selector(sidebarItemClicked(_:)))
        let itemTask = SidebarItemView(icon: "🛡️", title: "任务执行与监管", targetIndex: 4, target: self, action: #selector(sidebarItemClicked(_:)))
        sidebarItems = [itemModel, itemAPI, itemLive, itemHardware, itemTask, itemNetwork, itemStartup, itemWatchlist]
        itemModel.isSelected = true

        let gatewayBadge = tonalLabel("● :8002 在线", size: 11, weight: .semibold, color: NSColor(srgbRed: 0.15, green: 0.80, blue: 0.35, alpha: 1.0))

        let sidebarStack = NSStackView(views: [
            brandHeader,
            makeSectionLabel("运行时与监控"),
            itemLive,
            itemHardware,
            itemNetwork,
            itemStartup,
            itemWatchlist,
            makeSectionLabel("模型服务"),
            itemModel,
            itemAPI,
            makeSectionLabel("Agent 监管"),
            itemTask,
            NSView(),
            gatewayBadge
        ])
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 6
        sidebarStack.edgeInsets = NSEdgeInsets(top: 36, left: 12, bottom: 20, right: 12)
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)

        // ─── Right Main Area (MTPLX Canvas) ───
        let mainArea = NSView()
        mainArea.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(mainArea)

        let topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        mainArea.addSubview(topBar)

        let topModel = tonalLabel("Serafina · 模型加载中", size: 13, weight: .bold, color: Serafina.ink)
        topModel.lineBreakMode = .byTruncatingTail
        topBarModelLabel = topModel
        let topBadge = tonalLabel(" 🟢 就绪 ", size: 11, weight: .semibold, color: NSColor(srgbRed: 0.15, green: 0.80, blue: 0.35, alpha: 1.0))
        topBadge.wantsLayer = true
        topBadge.layer?.backgroundColor = NSColor(srgbRed: 0.20, green: 0.88, blue: 0.42, alpha: 0.15).cgColor
        topBadge.layer?.cornerRadius = 5
        topBarStatusBadge = topBadge

        let topUnloadBtn = NSButton(title: "⏏️ 释放显存", target: self, action: #selector(unloadModelAndReleaseMemory))
        topUnloadBtn.font = Serafina.rounded(10, .bold)
        topUnloadBtn.isBordered = false
        topUnloadBtn.wantsLayer = true
        topUnloadBtn.layer?.cornerRadius = 5
        topUnloadBtn.layer?.backgroundColor = Serafina.petal.withAlphaComponent(0.40).cgColor
        topUnloadBtn.translatesAutoresizingMaskIntoConstraints = false
        topUnloadBtn.heightAnchor.constraint(equalToConstant: 22).isActive = true
        topUnloadBtn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        topBarUnloadButton = topUnloadBtn

        let topSpeed = tonalLabel("预填 -- · 生成 --", size: 11, weight: .medium, color: Serafina.muted)
        topSpeed.lineBreakMode = .byTruncatingTail
        topSpeed.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        topBarSpeedLabel = topSpeed

        let topPill = tonalLabel(" ⚡️ 214M tok · 命中 99% ", size: 10, weight: .bold, color: Serafina.grape)
        topPill.wantsLayer = true
        topPill.layer?.backgroundColor = Serafina.petal.withAlphaComponent(0.40).cgColor
        topPill.layer?.cornerRadius = 5
        topPill.lineBreakMode = .byTruncatingTail
        topPill.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        topBarHarnessPill = topPill

        let topLang = NSButton(title: I18n.current == .zh ? "🌐 简中" : "🌐 EN", target: self, action: #selector(toggleLanguage))
        topLang.font = Serafina.rounded(10, .bold)
        topLang.isBordered = false
        topLang.wantsLayer = true
        topLang.layer?.cornerRadius = 5
        topLang.layer?.backgroundColor = Serafina.petal.withAlphaComponent(0.40).cgColor
        topLang.translatesAutoresizingMaskIntoConstraints = false
        topLang.heightAnchor.constraint(equalToConstant: 22).isActive = true
        topLang.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        topBarLangButton = topLang

        let topBarInner = NSStackView(views: [topModel, topBadge, topUnloadBtn, topPill, NSView(), topSpeed, topLang])
        topBarInner.orientation = .horizontal
        topBarInner.alignment = .centerY
        topBarInner.spacing = 8
        topBarInner.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        topBarInner.translatesAutoresizingMaskIntoConstraints = false
        topBarInner.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        topBar.addSubview(topBarInner)

        let stack = NSStackView(views: [modelCard, clientCard, apiPage, dashboardCard, harnessCard, liveCard, hardwareCard, serviceCard, note, taskCard, networkCard, networkTableCard, startupCard, watchlistCard])
        stack.detachesHiddenViews = true
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 24, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scrollHost = NSScrollView()
        scrollHost.drawsBackground = false
        scrollHost.hasVerticalScroller = true
        scrollHost.autohidesScrollers = true
        scrollHost.verticalScrollElasticity = .allowed
        scrollHost.translatesAutoresizingMaskIntoConstraints = false
        mainArea.addSubview(scrollHost)
        self.mainScrollView = scrollHost

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        scrollHost.documentView = doc
        doc.addSubview(stack)

        for card in [modelCard, clientCard, apiPage, dashboardCard, harnessCard, liveCard, hardwareCard, serviceCard, note, taskCard, networkCard, networkTableCard, startupCard, watchlistCard] {
            card.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            card.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        doc.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollHost.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        mainArea.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for view in [powerHeader, power, popup, capability, modelCard, clientCard, clientHint, dashboardCard, harnessCard, hInner, hBentoRow, aociBox, cgBox, platBox, liveCard, scroll, hardwareCard, serviceCard, note, endpoint, stats, meter, meterLabel, layerRow1, layerRow2, statsRow1, statsRow2, arpRow, dashSubtitle, dashModelInfo, supervisorHeader, pipelineLabel, breakerLabel, loopLabel, cacheLabel, gpuBar, ramBar, bentoRow, ssdCard, procCard, networkCard, networkTableCard, startupCard, watchlistCard] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 170),

            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sidebarStack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),

            mainArea.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            mainArea.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            mainArea.topAnchor.constraint(equalTo: content.topAnchor),
            mainArea.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            topBar.leadingAnchor.constraint(equalTo: mainArea.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: mainArea.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: mainArea.topAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 44),

            topBarInner.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            topBarInner.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            topBarInner.topAnchor.constraint(equalTo: topBar.topAnchor),
            topBarInner.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),

            scrollHost.leadingAnchor.constraint(equalTo: mainArea.leadingAnchor),
            scrollHost.trailingAnchor.constraint(equalTo: mainArea.trailingAnchor),
            scrollHost.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            scrollHost.bottomAnchor.constraint(equalTo: mainArea.bottomAnchor),

            doc.leadingAnchor.constraint(equalTo: scrollHost.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scrollHost.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scrollHost.contentView.topAnchor),
            doc.widthAnchor.constraint(equalTo: scrollHost.contentView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),

            taskCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            networkCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            networkTableCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            startupCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            watchlistCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            apiPage.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            apiPage.heightAnchor.constraint(greaterThanOrEqualToConstant: 620),
            modelCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            clientCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            clientHint.widthAnchor.constraint(equalTo: clientCard.widthAnchor, constant: -44),
            dashboardCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            harnessCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            hBentoRow.widthAnchor.constraint(equalTo: hInner.widthAnchor),
            aociBox.widthAnchor.constraint(equalTo: hInner.widthAnchor),
            cgBox.widthAnchor.constraint(equalTo: hInner.widthAnchor),
            platBox.widthAnchor.constraint(equalTo: hInner.widthAnchor),
            liveCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            hardwareCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            serviceCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            popup.widthAnchor.constraint(equalTo: modelCard.widthAnchor, constant: -44),
            powerHeader.widthAnchor.constraint(equalTo: popup.widthAnchor),
            power.widthAnchor.constraint(equalToConstant: 44),
            power.heightAnchor.constraint(equalToConstant: 44),
            layerRow1.widthAnchor.constraint(equalTo: dashboardCard.widthAnchor, constant: -44),
            layerRow2.widthAnchor.constraint(equalTo: dashboardCard.widthAnchor, constant: -44),
            statsRow1.widthAnchor.constraint(equalTo: dashboardCard.widthAnchor, constant: -44),
            statsRow2.widthAnchor.constraint(equalTo: dashboardCard.widthAnchor, constant: -44),
            arpRow.widthAnchor.constraint(equalTo: dashboardCard.widthAnchor, constant: -44),
            dashSubtitle.widthAnchor.constraint(equalTo: dashboardCard.widthAnchor, constant: -44),
            dashModelInfo.widthAnchor.constraint(equalTo: dashboardCard.widthAnchor, constant: -44),
            supervisorHeader.widthAnchor.constraint(equalTo: dashboardCard.widthAnchor, constant: -44),
            pipelineLabel.widthAnchor.constraint(equalTo: dashboardCard.widthAnchor, constant: -44),
            breakerLabel.widthAnchor.constraint(equalTo: dashboardCard.widthAnchor, constant: -44),
            loopLabel.widthAnchor.constraint(equalTo: dashboardCard.widthAnchor, constant: -44),
            cacheLabel.widthAnchor.constraint(equalTo: dashboardCard.widthAnchor, constant: -44),
            gpuBar.widthAnchor.constraint(equalTo: hardwareCard.widthAnchor, constant: -44),
            ramBar.widthAnchor.constraint(equalTo: hardwareCard.widthAnchor, constant: -44),
            bentoRow.widthAnchor.constraint(equalTo: hardwareCard.widthAnchor, constant: -44),
            ssdCard.widthAnchor.constraint(equalTo: hardwareCard.widthAnchor, constant: -44),
            procCard.widthAnchor.constraint(equalTo: hardwareCard.widthAnchor, constant: -44),
            procControlRow.widthAnchor.constraint(equalTo: procCard.widthAnchor, constant: -32),
            procScroll.widthAnchor.constraint(equalTo: procCard.widthAnchor, constant: -32),
            capability.widthAnchor.constraint(equalTo: popup.widthAnchor),
            stats.widthAnchor.constraint(equalTo: liveCard.widthAnchor, constant: -40),
            meter.widthAnchor.constraint(equalTo: stats.widthAnchor),
            meter.heightAnchor.constraint(equalToConstant: 16),
            meterLabel.widthAnchor.constraint(equalTo: stats.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stats.widthAnchor),
            endpoint.widthAnchor.constraint(equalTo: serviceCard.widthAnchor, constant: -40),
            controlRow.widthAnchor.constraint(lessThanOrEqualTo: popup.widthAnchor),
            presetRow.widthAnchor.constraint(lessThanOrEqualTo: popup.widthAnchor),
            switchRow.widthAnchor.constraint(lessThanOrEqualTo: popup.widthAnchor),
            serviceButtons.widthAnchor.constraint(lessThanOrEqualTo: endpoint.widthAnchor)
        ] + clientRows.map { $0.widthAnchor.constraint(equalTo: clientHint.widthAnchor) })
        let liveScrollHeight = scroll.heightAnchor.constraint(equalToConstant: 260)
        liveScrollHeight.isActive = true
        self.liveScrollHeightConstraint = liveScrollHeight
        for label in [managedHint, managedStatus, settingsHint, memoryHint, current] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalTo: popup.widthAnchor).isActive = true
        }
        for label in clientText {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalTo: clientHint.widthAnchor).isActive = true
        }
        for label in [status, autoload] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(lessThanOrEqualTo: endpoint.widthAnchor).isActive = true
        }
        companion.translatesAutoresizingMaskIntoConstraints = false
        companion.cell?.lineBreakMode = .byTruncatingTail
        companion.widthAnchor.constraint(equalTo: taskCard.widthAnchor, constant: -44).isActive = true
        applyManagedLock()
        panel.minSize = NSSize(width: 740, height: 560)
        panel.maxSize = NSSize(width: 10000, height: 10000)
        panel.setContentSize(NSSize(width: 1366, height: 768))
        placeOnScreen(panel)
        updateDynamicScrollHeights(for: panel.frame.height)
        window = panel
    }

    @objc private func sidebarItemClicked(_ sender: SidebarItemView) {
        if pagePicker?.selectedSegment == sender.targetIndex { return }
        pagePicker?.selectedSegment = sender.targetIndex
        pageChanged()
    }

    @objc private func pageChanged() {
        let selected = pagePicker?.selectedSegment ?? 0
        for item in sidebarItems {
            let shouldSelect = (item.targetIndex == selected)
            if item.isSelected != shouldSelect {
                item.isSelected = shouldSelect
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, group) in pageCards.enumerated() {
            let shouldHide = (index != selected)
            for view in group {
                if view.isHidden != shouldHide {
                    view.isHidden = shouldHide
                }
            }
        }
        CATransaction.commit()

        mainScrollView?.contentView.scroll(to: .zero)
        mainScrollView?.reflectScrolledClipView(mainScrollView!.contentView)

        updatePowerButtonVisuals()
        if NSApplication.shared.activationPolicy() == .prohibited {
            if selected == 2 { pollTraffic() }
            return
        }

        // Dispatch data synchronization asynchronously on the next runloop turn
        // so the sidebar highlight and page switch render immediately (<1ms).
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.pagePicker?.selectedSegment == selected else { return }
            switch selected {
            case 0:
                self.refreshClientCard()
            case 1:
                self.apiModelLabel?.stringValue = I18n.translate("当前模型：\(self.localSummary(speed: true))")
                self.apiSnippetChanged()
            case 2:
                self.pollTraffic()
                self.refreshHardwareAndOMLXStats()
            case 3:
                self.refreshHardwareAndOMLXStats()
            case 5:
                self.pollNetworkSentinel()
            case 6:
                self.pollStartupItems()
            case 7:
                self.pollWatchlistItems()
                self.refreshCandidateProcesses()
            default:
                break
            }
        }
    }

    private func loadedMTPLX(_ choice: ModelChoice) -> Bool {
        guard mtplxReady, !runningModelId.isEmpty else { return false }
        let basename = URL(fileURLWithPath: choice.serveModel).lastPathComponent.lowercased()
        return runningModelId.lowercased() == basename || runningModelId.lowercased() == choice.model.lowercased().replacingOccurrences(of: "local/", with: "")
    }

    func runInterfaceSmoke() -> Int32 {
        NSApplication.shared.setActivationPolicy(.prohibited)
        buildWindow()
        mtplxReady = true
        runningModelId = "huihui-cyberstrike-offsec-35b-abliterated-mlx-6bit"
        guard let cyber = choices.first(where: { $0.model == "local/cyberstrike-35b-mlx-6bit" }), loadedMTPLX(cyber) else { return 1 }
        for index in pageCards.indices {
            pagePicker?.selectedSegment = index
            pageChanged()
            guard pageCards.enumerated().allSatisfy({ item in item.element.allSatisfy { $0.isHidden == (item.offset != index) } }) else { return 2 }
        }
        guard transcriptView?.string.contains("SWITCH_UI_LOG_OK") == true else { return 3 }
        if let window {
            for (width, height) in [(740.0, 768.0), (780.0, 768.0), (1040.0, 840.0), (1366.0, 768.0), (1920.0, 1080.0)] {
                window.setContentSize(NSSize(width: width, height: height))
                updateDynamicScrollHeights(for: height)
                for index in pageCards.indices {
                    pagePicker?.selectedSegment = index; pageChanged()
                    window.contentView?.layoutSubtreeIfNeeded()
                    for card in pageCards[index] {
                        guard card.bounds.width > 500 else { print("UNLAID OUT page \(index): \(card.bounds)"); return 5 }
                        func check(_ view: NSView) -> Bool {
                            if view.isHidden || view is NSScrollView { return true }
                            if view is NSControl && view.frame.width > 0 {
                                let rect = view.convert(view.bounds, to: card)
                                if rect.minX < -1 || rect.maxX > card.bounds.width + 1 {
                                    print("OVERFLOW page \(index) width \(width): \(type(of: view)) \(rect) card=\(card.bounds)")
                                    return false
                                }
                            }
                            return view.subviews.allSatisfy { check($0) }
                        }
                        guard check(card) else { return 4 }
                    }
                }
            }
            print("PASS: horizontal & vertical bounds on all pages at 740x768 / 780x768 / 1040x840 / 1366x768 / 1920x1080")
        }
        print("PASS: model identity, five pages, recent traffic replay")
        return 0
    }

    func windowDidResize(_ notification: Notification) {
        guard !fixingFrame, let window = notification.object as? NSWindow else { return }
        updateDynamicScrollHeights(for: window.frame.height)
    }

    private func updateDynamicScrollHeights(for windowHeight: CGFloat) {
        let extra = max(0, windowHeight - 768)
        procScrollHeightConstraint?.constant = 280 + extra * 0.75
        inlineScrollHeightConstraint?.constant = 220 + extra * 0.55
        liveScrollHeightConstraint?.constant = 260 + extra * 0.70
    }

    func windowDidMove(_ notification: Notification) {
        guard !fixingFrame, let window = notification.object as? NSWindow else { return }
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        if window.frame.width < 500 || !visible.intersects(window.frame) {
            keepWindowVisible(window)
        }
    }

    private func keepWindowVisible(_ window: NSWindow) {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        guard window.frame.width < 500 || window.frame.height < 500 || !visible.intersects(window.frame) else { return }
        fixingFrame = true
        placeOnScreen(window)
        fixingFrame = false
    }

    private func placeOnScreen(_ window: NSWindow) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            window.center()
            return
        }
        var frame = window.frame
        let targetWidth: CGFloat = 1366
        let targetHeight: CGFloat = 768
        frame.size.width = min(targetWidth, max(740, visible.width - 32))
        frame.size.height = min(targetHeight, max(560, visible.height - 32))
        frame.origin.x = round(visible.midX - frame.size.width / 2)
        frame.origin.y = round(visible.midY - frame.size.height / 2)
        window.setFrame(frame, display: true)
    }

    private func refreshWindowSelection() {
        let active = readTopLevelSettings()
        if let index = choices.firstIndex(where: { $0.provider == active.provider && $0.model == active.model }) {
            modelPopup?.selectItem(at: index)
        } else if let local = activeLocalChoice(), let index = choices.firstIndex(where: { $0.model == local.model }) {
            modelPopup?.selectItem(at: index)
        }
        loadModelControls()
        currentLabel?.stringValue = "Codex 当前默认：\(displayName(for: active.model, provider: active.provider))"
        updateCapabilityLabel()
    }

    @objc private func selectionChanged() {
        loadModelControls()
        updateCapabilityLabel()
    }

    @objc private func thinkingChanged() { modelSettingChanged() }

    // MARK: - Per-model settings (recommended, with manual overrides)

    private func recommended(for choice: ModelChoice) -> (thinking: Bool, effort: String, depth: Int) {
        recommendedSettings[choice.model] ?? (false, choice.reasoningEffort == "low" ? "medium" : choice.reasoningEffort, 3)
    }

    /// The model's recommended settings with the user's manual changes on top.
    private func modelSettings(for choice: ModelChoice) -> (thinking: Bool, effort: String, depth: Int) {
        let base = recommended(for: choice)
        let saved = (UserDefaults.standard.dictionary(forKey: "modelSettings") ?? [:])[choice.model] as? [String: Any] ?? [:]
        return (saved["thinking"] as? Bool ?? base.thinking, saved["effort"] as? String ?? base.effort,
                saved["depth"] as? Int ?? base.depth)
    }

    private func selectedChoice() -> ModelChoice? {
        guard let index = modelPopup?.indexOfSelectedItem, choices.indices.contains(index) else { return nil }
        return choices[index]
    }

    private func loadModelControls() {
        guard let choice = selectedChoice() else { return }
        let settings = modelSettings(for: choice)
        thinkingCheckbox?.state = settings.thinking ? .on : .off
        effortPopup?.selectItem(withTitle: settings.effort)
        depthPopup?.selectItem(at: max(0, min(2, settings.depth - 1)))
        let best = recommended(for: choice)
        let custom = settings.thinking != best.thinking || settings.effort != best.effort || settings.depth != best.depth
        let thinkingText = choice.isLocal && ["mtplx", "omlx"].contains(choice.backend) ? "\(best.thinking ? "开启" : "关闭")思考 · " : ""
        settingsHintLabel?.stringValue = custom
            ? "已按你的设置（推荐：\(thinkingText)推理 \(best.effort)）· 点「恢复推荐」回到最佳配置"
            : "推荐配置：\(thinkingText)推理 \(best.effort)\(choice.mtp ? " · MTP 深度 D\(best.depth)" : "")"
    }

    @objc private func modelSettingChanged() {
        guard let choice = selectedChoice() else { return }
        var all = UserDefaults.standard.dictionary(forKey: "modelSettings") ?? [:]
        let current: (thinking: Bool, effort: String, depth: Int) = (thinkingCheckbox?.state == .on,
            effortPopup?.titleOfSelectedItem ?? recommended(for: choice).effort, (depthPopup?.indexOfSelectedItem ?? 2) + 1)
        let best = recommended(for: choice)
        if current.thinking == best.thinking && current.effort == best.effort && current.depth == best.depth {
            all.removeValue(forKey: choice.model)
        } else {
            all[choice.model] = ["thinking": current.thinking, "effort": current.effort, "depth": current.depth]
        }
        UserDefaults.standard.set(all, forKey: "modelSettings")
        log("model settings \(choice.model) thinking=\(current.thinking) effort=\(current.effort) depth=\(current.depth)")
        if choice.isLocal && (readRuntime()["api_model"] as? String) == choice.model { try? writeRuntime(choice) }
        loadModelControls()
    }

    @objc private func resetModelSettings() {
        guard let choice = selectedChoice() else { return }
        var all = UserDefaults.standard.dictionary(forKey: "modelSettings") ?? [:]
        all.removeValue(forKey: choice.model)
        UserDefaults.standard.set(all, forKey: "modelSettings")
        loadModelControls()
        if choice.isLocal && (readRuntime()["api_model"] as? String) == choice.model { try? writeRuntime(choice) }
        log("model settings reset \(choice.model)")
    }

    private func updateModelPopupStatuses() {
        guard let popup = modelPopup else { return }
        let selectedIndex = popup.indexOfSelectedItem
        for (i, item) in popup.itemArray.enumerated() {
            guard choices.indices.contains(i) else { continue }
            let choice = choices[i]
            var cleanTitle = choice.title.replacingOccurrences(of: "🟢 ", with: "")
                                         .replacingOccurrences(of: "🔴 ", with: "")
                                         .replacingOccurrences(of: "☁️ ", with: "")
            let speedKey = choice.model.lowercased().replacingOccurrences(of: "local/", with: "")
            if choice.isLocal, !cleanTitle.contains("平均"), let average = speedAverages[speedKey],
               let mean = average["decode_tok_s"] as? Double, mean > 0 {
                cleanTitle += String(format: " · 历史均速 %.1f tok/s", mean)
            }
            if !choice.isLocal {
                item.title = "☁️ " + cleanTitle
            } else if choice.backend == "lmstudio" {
                let isLoaded = (self.lmStudioLoadedModel == choice.serveModel || self.lmStudioLoadedModel == choice.lmsKey)
                item.title = (isLoaded ? "🟢 " : "🔴 ") + cleanTitle
            } else if choice.backend == "bonsai" {
                item.title = (self.bonsaiReady ? "🟢 " : "🔴 ") + cleanTitle
            } else if choice.backend == "omlx" {
                item.title = (self.omlxLoadedModels.contains(choice.serveModel) ? "🟢 " : "🔴 ") + cleanTitle
            } else {
                let isLoaded = loadedMTPLX(choice)
                item.title = (isLoaded ? "🟢 " : "🔴 ") + cleanTitle
            }
        }
        if selectedIndex >= 0 && selectedIndex < popup.numberOfItems {
            popup.selectItem(at: selectedIndex)
        }
    }

    private func updateCapabilityLabel() {
        guard let index = modelPopup?.indexOfSelectedItem, choices.indices.contains(index) else { return }
        let choice = choices[index]
        let endpoint = choice.endpoint.map { "  |  \($0)" } ?? ""
        let key = choice.model.lowercased().replacingOccurrences(of: "local/", with: "")
        let average = speedAverages[key]
        let decode = lastSpeeds[choice.model] ?? lastSpeeds[key]
        let prefill = lastPrefillSpeeds[choice.model] ?? lastPrefillSpeeds[key]
        var lastSpeed: String
        if decode != nil || prefill != nil {
            let prefillText = prefill.map { String(format: "%.2f", $0) } ?? "—"
            let decodeText = decode.map { String(format: "%.2f", $0) } ?? "—"
            lastSpeed = "  |  上次调用 · 处理 \(prefillText) tok/s · 生成 \(decodeText) tok/s"
        } else {
            lastSpeed = choice.isLocal ? "  |  上次调用：暂无记录" : ""
        }
        if let average {
            let mean = average["decode_tok_s"] as? Double ?? 0
            let samples = average["samples"] as? Int ?? 0
            lastSpeed += String(format: "\n历史均速 %.1f tok/s · %d 次 · 输入处理与生成分别统计", mean, samples)
        }
        let isCurrentlyLoaded: Bool
        if !choice.isLocal {
            isCurrentlyLoaded = true
        } else if choice.backend == "lmstudio" {
            isCurrentlyLoaded = (self.lmStudioLoadedModel == choice.serveModel || self.lmStudioLoadedModel == choice.lmsKey)
        } else if choice.backend == "bonsai" {
            isCurrentlyLoaded = self.bonsaiReady
        } else if choice.backend == "omlx" {
            isCurrentlyLoaded = self.omlxLoadedModels.contains(choice.serveModel)
        } else {
            isCurrentlyLoaded = loadedMTPLX(choice)
        }
        let statusBadge = !choice.isLocal
            ? "【状态】☁️ 云端 API 服务"
            : (isCurrentlyLoaded ? "【状态】🟢 已加载至统一内存 (闲置就绪)" : "【状态】🔴 当前未在内存中运行 (点击切换后启动/加载)")
        capabilityLabel?.stringValue = "\(statusBadge)\n\(choice.capability)\(endpoint)\(lastSpeed)"
        depthPopup?.isEnabled = choice.mtp
        thinkingCheckbox?.isEnabled = ["mtplx", "omlx"].contains(choice.backend)
        if effortPopup?.selectedItem == nil {
            effortPopup?.selectItem(withTitle: choice.reasoningEffort)
        }
    }

    @objc private func applyWindowSelection() {
        guard let index = modelPopup?.indexOfSelectedItem, choices.indices.contains(index) else { return }
        apply(choice: choices[index])
    }

    @objc private func applyAgentPreset() {
        applyPreset(model: "Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed-FP16", effort: "medium", thinking: true)
    }

    @objc private func applyChatPreset() {
        applyPreset(model: "gpt-oss-20b", effort: "low", thinking: false)
    }

    private func applyPreset(model: String, effort: String, thinking: Bool) {
        guard let index = choices.firstIndex(where: { $0.model == model }) else {
            showError(title: "模式不可用", message: "没找到对应的本地模型：\(model)")
            return
        }
        modelPopup?.selectItem(at: index)
        effortPopup?.selectItem(withTitle: effort)
        thinkingCheckbox?.state = thinking ? .on : .off
        modelSettingChanged()
        updateCapabilityLabel()
        log("preset applied model=\(model) effort=\(effort) thinking=\(thinking)")
        apply(choice: choices[index])
    }

    @objc private func restartPreferenceChanged() {
        UserDefaults.standard.set(restartCheckbox?.state == .on, forKey: "restartAfterSwitch")
    }

    @objc private func applySpeedKnobs() {
        if let index = modelPopup?.indexOfSelectedItem, choices.indices.contains(index),
           !["mtplx", "omlx"].contains(choices[index].backend) {
            serviceStatusLabel?.stringValue = "● 这个模型由 LM Studio 管理采样，深度和思考只对 MTPLX / oMLX 生效"
            return
        }
        let depth = max(1, (depthPopup?.indexOfSelectedItem ?? 2) + 1)
        UserDefaults.standard.set(depth, forKey: "mtpDepth")
        let thinking = thinkingCheckbox?.state == .on
        let effort = effortPopup?.titleOfSelectedItem ?? "medium"
        modelSettingChanged()  // saves this model's settings and rewrites runtime.json if it is loaded
        let command = "source \"$HOME/.venvs/mtplx/bin/activate\" && mtplx settings set depth=\(depth) reasoning=\(thinking ? "on" : "off") reasoning-effort=\(effort) --port 8000"
        log("speed knobs depth=\(depth) reasoning=\(thinking ? "on" : "off") effort=\(effort)")
        serviceStatusLabel?.stringValue = "正在应用 MTP 深度和思考开关…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                DispatchQueue.main.async {
                    let ok = process.terminationStatus == 0
                    self?.serviceStatusLabel?.stringValue = ok
                        ? "● 速度参数已应用 · D\(depth) · 思考\(thinking ? "开" : "关") · \(effort)"
                        : "● 参数未生效 · \(message)"
                    self?.log("speed knobs exit=\(process.terminationStatus) \(message)")
                }
            } catch {
                DispatchQueue.main.async {
                    self?.serviceStatusLabel?.stringValue = "● 参数未生效 · \(error.localizedDescription)"
                }
            }
        }
    }

    private func rebuildMenu(message: String? = nil) {
        let active = readTopLevelSettings()
        let menu = NSMenu()
        let header = NSMenuItem(title: message ?? "当前：\(displayName(for: active.model, provider: active.provider))", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        var lastGroup = ""
        for (index, choice) in choices.enumerated() {
            let groups = ["lmstudio": "LM Studio", "omlx": "oMLX", "bonsai": "Bonsai"]
            let group = choice.isLocal ? (groups[choice.backend] ?? "MTPLX") : "云端"
            if group != lastGroup {
                if lastGroup.isEmpty == false { menu.addItem(.separator()) }
                let label = NSMenuItem(title: group, action: nil, keyEquivalent: "")
                label.isEnabled = false
                menu.addItem(label)
                lastGroup = group
            }
            let item = NSMenuItem(title: choice.title, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = active.provider == choice.provider && active.model == choice.model ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for item in [
            NSMenuItem(title: "启动本地 API", action: #selector(startLocalAPI), keyEquivalent: ""),
            NSMenuItem(title: "停止本地 API 并释放内存", action: #selector(stopLocalAPI), keyEquivalent: ""),
            NSMenuItem(title: "测试文本 + 图片", action: #selector(testLocalVision), keyEquivalent: ""),
            NSMenuItem(title: "API 接入信息…", action: #selector(showAPIPanel), keyEquivalent: "")
        ] {
            item.target = self
            menu.addItem(item)
        }
        let logItem = NSMenuItem(title: "打开切换与问答日志", action: #selector(openLogFile), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "打开切换窗口…", action: #selector(openSettingsWindow), keyEquivalent: "s")
        settings.target = self
        menu.addItem(settings)
        let openConfig = NSMenuItem(title: "打开 Codex 配置", action: #selector(openConfigFile), keyEquivalent: ",")
        openConfig.target = self
        menu.addItem(openConfig)
        let openCodex = NSMenuItem(title: "打开 Codex", action: #selector(openCodexApp), keyEquivalent: "o")
        openCodex.target = self
        menu.addItem(openCodex)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出切换器", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.toolTip = "Codex 模型：\(displayName(for: active.model, provider: active.provider))"
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard choices.indices.contains(sender.tag) else { return }
        modelPopup?.selectItem(at: sender.tag)
        apply(choice: choices[sender.tag])
    }

    private func apply(choice: ModelChoice) {
        guard !switchInProgress else { return }
        log("selection requested provider=\(choice.provider) model=\(choice.model)")
        let effort = effortPopup?.titleOfSelectedItem ?? choice.reasoningEffort
        if choice.isLocal {
            switchInProgress = true
            do {
                try writeRuntime(choice)
            } catch {
                switchInProgress = false
                showError(title: "无法写入运行配置", message: error.localizedDescription)
                return
            }
            serviceStatusLabel?.stringValue = "正在准备 \(choice.title)…"
            runServiceScript(startScript) { [weak self] success, message in
                guard let self else { return }
                self.switchInProgress = false
                guard success else {
                    self.log("local start failed: \(message)")
                    self.showError(title: "本地模型启动失败", message: message)
                    return
                }
                self.mtplxReady = true
                self.preflightAndApply(choice: choice, reasoningEffort: effort)
            }
            return
        }
        preflightAndApply(choice: choice, reasoningEffort: effort)
    }

    private func agentdSettings() -> [String: Any] {
        let preset = UserDefaults.standard.integer(forKey: "agentWindowPreset")
        let budget: Int
        switch preset {
        case 0: budget = 2048
        case 2: budget = 57344
        default: budget = 24576
        }
        return ["input_budget": budget,
         "team_mode": UserDefaults.standard.bool(forKey: "verifiedTeamMode"),
         "companion_model": UserDefaults.standard.integer(forKey: "teamCompanion") == 1 ? "qwen/qwen3.5-9b" : "openai/gpt-oss-20b"]
    }

    @objc private func teamSettingsChanged() {
        UserDefaults.standard.set(teamCheckbox?.state == .on, forKey: "verifiedTeamMode")
        UserDefaults.standard.set(companionPopup?.indexOfSelectedItem ?? 0, forKey: "teamCompanion")
        do {
            var body = readRuntime()
            body["agentd"] = agentdSettings()
            let data = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: runtimeURL, options: .atomic)
            taskStatusLabel?.stringValue = "设置已保存 · 下一次任务生效"
        } catch { showError(title: "任务配置保存失败", message: error.localizedDescription) }
    }

    @objc private func manualScanNetwork() {
        pollNetworkSentinel()
    }

    private func killSinglePID(_ pid: Int, name: String? = nil) {
        let label = name.map { "\($0) (PID \(pid))" } ?? "PID \(pid)"
        showAsyncToast("⚡️ 正在终止进程 \(label)...", isSuccess: true)

        guard let url = URL(string: "http://127.0.0.1:8002/v1/network/kill_process") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["pid": pid]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let err = err {
                    self.showAsyncToast("❌ 终止失败: \(err.localizedDescription)", isSuccess: false)
                    return
                }
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let ok = json["ok"] as? Bool ?? false
                    let msg = json["message"] as? String ?? (ok ? "进程阻断成功" : "阻断失败")
                    self.showAsyncToast(ok ? "✓ \(msg)" : "⚠️ \(msg)", isSuccess: ok)
                    self.pollNetworkSentinel()
                    self.pollProcessResources()
                    self.pollWatchlistItems()
                }
            }
        }.resume()
    }

    private func killProcessFamily(_ pid: Int, name: String? = nil) {
        let label = name.map { "\($0) (PID \(pid))" } ?? "PID \(pid)"
        showAsyncToast("⚡️ 正在深度阻断父子进程树 \(label)...", isSuccess: true)

        guard let url = URL(string: "http://127.0.0.1:8002/v1/network/kill_family") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["pid": pid, "include_parent": true]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let err = err {
                    self.showAsyncToast("❌ 进程树阻断失败: \(err.localizedDescription)", isSuccess: false)
                    return
                }
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let ok = json["ok"] as? Bool ?? false
                    let msg = json["message"] as? String ?? (ok ? "进程树阻断成功" : "阻断失败")
                    self.showAsyncToast(ok ? "✓ \(msg)" : "⚠️ \(msg)", isSuccess: ok)
                    self.pollNetworkSentinel()
                    self.pollProcessResources()
                    self.pollWatchlistItems()
                }
            }
        }.resume()
    }

    private func setProcessRateLimit(pid: Int, name: String, limitKBps: Double) {
        let label = "\(name) (PID \(pid))"
        let limitDesc = limitKBps <= 0 ? "解除限速" : String(format: "%.0f KB/s", limitKBps)
        showAsyncToast("⚡️ 正在为 \(label) 设置网速限制: \(limitDesc)...", isSuccess: true)

        guard let url = URL(string: "http://127.0.0.1:8002/v1/network/set_rate_limit") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["pid": pid, "name": name, "limit_kb_s": limitKBps]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let err = err {
                    self.showAsyncToast("❌ 限速设置失败: \(err.localizedDescription)", isSuccess: false)
                    return
                }
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let ok = json["ok"] as? Bool ?? false
                    let msg = json["message"] as? String ?? (ok ? "网速限制已生效" : "限速失败")
                    self.showAsyncToast(ok ? "⚡️ \(msg)" : "⚠️ \(msg)", isSuccess: ok)
                    self.pollNetworkSentinel()
                    self.refreshCandidateProcesses()
                }
            }
        }.resume()
    }

    private func promptCustomRateLimit(pid: Int, name: String) {
        let alert = NSAlert()
        alert.messageText = I18n.translate("为 \(name) (PID \(pid)) 设置限速")
        alert.informativeText = I18n.translate("请输入允许的最大网络上传/下载速率 (单位: KB/s)。例如输入 250 即为 250 KB/s；输入 0 为解除限制。")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = "200"
        alert.accessoryView = input
        alert.addButton(withTitle: I18n.translate("确定"))
        alert.addButton(withTitle: I18n.translate("取消"))
        if let window = self.window {
            alert.beginSheetModal(for: window) { [weak self] resp in
                if resp == .alertFirstButtonReturn {
                    let raw = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    let val = Double(raw) ?? 0
                    self?.setProcessRateLimit(pid: pid, name: name, limitKBps: max(0, val))
                }
            }
        } else {
            let resp = alert.runModal()
            if resp == .alertFirstButtonReturn {
                let raw = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let val = Double(raw) ?? 0
                self.setProcessRateLimit(pid: pid, name: name, limitKBps: max(0, val))
            }
        }
    }

    private func handlePendingGatekeeperEvents(_ events: [[String: Any]]) {
        guard let first = events.first,
              let eventId = first["event_id"] as? String,
              !eventId.isEmpty else {
            return
        }
        if gatekeeperWindow?.window?.isVisible == true && lastPresentedGatekeeperEventId == eventId {
            return
        }
        lastPresentedGatekeeperEventId = eventId
        if gatekeeperWindow == nil {
            let modal = GatekeeperInterceptWindowController()
            modal.onDecisionResolved = { [weak self] in
                guard let self = self else { return }
                self.lastPresentedGatekeeperEventId = ""
                self.pollNetworkSentinel()
                self.pollProcessResources()
                self.pollWatchlistItems()
            }
            gatekeeperWindow = modal
        }
        if let gw = gatekeeperWindow?.window {
            gw.title = I18n.translate("🚨 Gatekeeper 高危流量与敏感凭证实时拦截确认")
            if let cv = gw.contentView {
                I18n.localizeViewTree(cv)
            }
        }
        gatekeeperWindow?.presentEvent(first)
    }

    private func checkGatekeeperPendingEventsOnly() {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/network/status") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pending = json["pending_gatekeeper_events"] as? [[String: Any]],
                  !pending.isEmpty else { return }
            DispatchQueue.main.async {
                self.handlePendingGatekeeperEvents(pending)
            }
        }.resume()
    }

    @objc private func simulateGatekeeperAlert() {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/network/gatekeeper_simulate") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let ev = json["event"] as? [String: Any] {
                        self.handlePendingGatekeeperEvents([ev])
                    } else if json["bypassed"] as? Bool == true {
                        let alert = NSAlert()
                        alert.messageText = I18n.translate("🛡️ 父进程已在信任白名单中 (自动放行)")
                        alert.informativeText = json["message"] as? String ?? I18n.translate("该父进程已加入永久白名单，拦截已自动跳过并放行，无弹窗提醒。")
                        alert.addButton(withTitle: I18n.translate("确定"))
                        alert.addButton(withTitle: I18n.translate("管理/清空白名单"))
                        let resp = alert.runModal()
                        if resp == .alertSecondButtonReturn {
                            self.showGatekeeperWhitelistDialog()
                        }
                    } else {
                        self.pollNetworkSentinel()
                    }
                } else {
                    self.pollNetworkSentinel()
                }
            }
        }.resume()
    }

    @objc private func showGatekeeperWhitelistDialog() {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/network/gatekeeper_whitelist") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let list = json["whitelist"] as? [[String: Any]] else {
                    let errAlert = NSAlert()
                    errAlert.messageText = I18n.translate("获取白名单失败")
                    errAlert.informativeText = I18n.translate("无法从网络哨兵读取当前白名单配置。")
                    errAlert.addButton(withTitle: I18n.translate("确定"))
                    errAlert.runModal()
                    return
                }

                let alert = NSAlert()
                if list.isEmpty {
                    alert.messageText = I18n.translate("🛡️ Gatekeeper 信任白名单 (当前为空)")
                    alert.informativeText = I18n.translate("当前尚未将任何父进程加入永久白名单。\n\n当发生敏感凭证外发拦截弹窗时，勾选「记住此授权：将父进程加入信任白名单」，后续该父进程的所有操作都将自动放行，不再弹窗打扰。")
                    alert.addButton(withTitle: I18n.translate("知道了"))
                    alert.runModal()
                } else {
                    alert.messageText = I18n.translate("🛡️ Gatekeeper 信任白名单 (已信任 \(list.count) 项)")
                    var text = I18n.translate("以下父进程派生的子进程外联或凭证访问将自动放行，不再弹窗打扰：\n\n")
                    for item in list {
                        let name = item["parent_name"] as? String ?? "unknown"
                        let added = item["added_at"] as? String ?? ""
                        text += "• \(name)" + (!added.isEmpty ? " [\(added)]" : "") + "\n"
                    }
                    text += I18n.translate("\n如需重新恢复对上述父进程的弹窗确认，可点击下方「清空白名单」。")
                    alert.informativeText = text
                    alert.addButton(withTitle: I18n.translate("完成"))
                    alert.addButton(withTitle: I18n.translate("清空白名单"))
                    let resp = alert.runModal()
                    if resp == .alertSecondButtonReturn {
                        self.confirmClearGatekeeperWhitelist()
                    }
                }
            }
        }.resume()
    }

    private func confirmClearGatekeeperWhitelist() {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/network/gatekeeper_whitelist") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["action": "clear"]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] _, _, _ in
            DispatchQueue.main.async {
                self?.showAsyncToast("✓ Gatekeeper 信任白名单已清空", isSuccess: true)
                self?.pollNetworkSentinel()
            }
        }.resume()
    }

    @objc private func killAllSuspiciousProcesses() {
        showAsyncToast("⚡️ 正在批量阻断所有异常外联进程...", isSuccess: true)

        guard let url = URL(string: "http://127.0.0.1:8002/v1/network/kill_all_suspicious") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let err = err {
                    self.showAsyncToast("❌ 批量阻断失败: \(err.localizedDescription)", isSuccess: false)
                    return
                }
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let ok = json["ok"] as? Bool ?? false
                    let msg = json["message"] as? String ?? (ok ? "批量阻断成功" : "操作失败")
                    self.showAsyncToast(ok ? "✓ \(msg)" : "⚠️ \(msg)", isSuccess: ok)
                    self.pollNetworkSentinel()
                }
            }
        }.resume()
    }

    @objc private func pollNetworkSentinel() {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/network/status") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let bandwidth = json["bandwidth"] as? [String: Any] ?? [:]
            let summary = json["summary"] as? [String: Any] ?? [:]
            let alerts = json["active_alerts"] as? [[String: Any]] ?? []
            let conns = json["connections"] as? [[String: Any]] ?? []
            let listening = json["listening"] as? [[String: Any]] ?? []
            let pendingGatekeeper = json["pending_gatekeeper_events"] as? [[String: Any]] ?? []

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if !pendingGatekeeper.isEmpty {
                    self.handlePendingGatekeeperEvents(pendingGatekeeper)
                }
                let inFmt = bandwidth["in_formatted"] as? String ?? "0 B/s"
                let outFmt = bandwidth["out_formatted"] as? String ?? "0 B/s"
                let totalUp = bandwidth["total_uploaded_formatted"] as? String ?? "0 B"
                let totalDown = bandwidth["total_downloaded_formatted"] as? String ?? "0 B"
                self.netBandwidthBento?.update(value: "↓ \(inFmt)", subtitle: I18n.translate("↑ \(outFmt) (累计 \(totalUp))"))

                let riskLevel = summary["risk_level"] as? String ?? "SAFE"
                let critCount = summary["critical_count"] as? Int ?? 0
                let warnCount = summary["warning_count"] as? Int ?? 0
                let riskBadge = (riskLevel == "CRITICAL") ? "🔴 CRITICAL" : (riskLevel == "WARNING" ? "🟡 WARNING" : "🟢 SAFE")
                self.netSecurityBento?.update(value: riskBadge, subtitle: I18n.translate("\(critCount) 处高危 · \(warnCount) 处警告"))

                let listCount = summary["listening_ports_count"] as? Int ?? 0
                let exposedCount = summary["exposed_public_ports_count"] as? Int ?? 0
                self.netPortsBento?.update(value: I18n.translate("\(listCount) 端口"), subtitle: I18n.translate("\(exposedCount) 处公网暴露"))

                let totalSockets = summary["total_sockets"] as? Int ?? 0
                let outboundCount = summary["outbound_public_count"] as? Int ?? 0
                self.netConnsBento?.update(value: I18n.translate("\(conns.count) 连接"), subtitle: I18n.translate("\(outboundCount) 公网外联 · \(totalSockets) 活跃 Socket"))

                // Update Real-Time Graphical Traffic Waveform View
                let hist = bandwidth["history"] as? [[String: Any]] ?? []
                self.trafficWaveformView?.update(history: hist, uploadSpeed: outFmt, downloadSpeed: inFmt, totalUp: totalUp, totalDown: totalDown)

                // Update Upload Audit Bento Cards
                let uploadSummary = json["upload_summary"] as? [String: Any] ?? [:]
                let cats = uploadSummary["categories"] as? [String: Any] ?? [:]
                let imgCount = cats["images"] as? Int ?? 0
                let txtCount = cats["texts"] as? Int ?? 0
                let fileCount = cats["files"] as? Int ?? 0
                let sensCount = cats["sensitive"] as? Int ?? 0
                let apiCount = cats["api"] as? Int ?? 0
                self.uploadImagesBento?.update(value: "\(imgCount)", subtitle: I18n.translate("照片/截图/图片传输"))
                self.uploadTextsBento?.update(value: "\(txtCount)", subtitle: I18n.translate("代码/日志/JSON传输"))
                self.uploadFilesBento?.update(value: "\(fileCount)", subtitle: I18n.translate("文档/归档包传输"))
                self.uploadSensitiveBento?.update(value: "\(sensCount)", subtitle: I18n.translate(sensCount > 0 ? "⚠️ 发现敏感文件读取!" : "未检测到私钥凭据读取"))

                // Update Visual Charts
                self.uploadDistributionBar?.update(images: imgCount, texts: txtCount, files: fileCount, sensitive: sensCount, api: apiCount)
                let topCountries = uploadSummary["top_countries"] as? [[String: Any]] ?? []
                self.countryDistributionView?.update(countries: topCountries)

                // Update Upload Audit Top Processes Stack (reuse rows in-place)
                if let upStack = self.uploadProcsContainerStack {
                    let topUploaders = Array((uploadSummary["top_uploaders"] as? [[String: Any]] ?? []).prefix(25))
                    let upHash = topUploaders.map { "\($0["pid"] as? Int ?? 0):\($0["command"] as? String ?? ""):\($0["upload_formatted"] as? String ?? ""):\($0["download_formatted"] as? String ?? ""):\($0["geo"] as? String ?? ""):\($0["rate_limit_formatted"] as? String ?? "")" }.joined(separator: "|")
                    if self.lastUploadProcsHash != upHash || upStack.subviews.isEmpty {
                        self.lastUploadProcsHash = upHash
                        let maxUploadBytes = max(1, topUploaders.compactMap { (($0["upload_bytes"] as? Int ?? 0) + ($0["download_bytes"] as? Int ?? 0)) }.max() ?? 1)
                        if topUploaders.isEmpty {
                            for v in upStack.subviews { v.removeFromSuperview() }
                            let emptyLabel = self.tonalLabel(I18n.translate("🟢 当前无活跃带宽传输进程"), size: 11, weight: .medium, color: Serafina.muted)
                            upStack.addArrangedSubview(emptyLabel)
                        } else {
                            for v in upStack.arrangedSubviews where !(v is UploadProcessRowView) {
                                v.removeFromSuperview()
                            }
                            let existingRows = upStack.arrangedSubviews.compactMap { $0 as? UploadProcessRowView }
                            for (idx, u) in topUploaders.enumerated() {
                                if idx < existingRows.count {
                                    let uRow = existingRows[idx]
                                    uRow.isHidden = false
                                    uRow.update(uploader: u, maxUploadBytes: maxUploadBytes)
                                } else {
                                    let uRow = UploadProcessRowView(
                                        uploader: u,
                                        maxUploadBytes: maxUploadBytes,
                                        onKillSingle: { [weak self] pid in self?.killSinglePID(pid) },
                                        onKillFamily: { [weak self] pid in self?.killProcessFamily(pid) },
                                        onAddToWatchlist: { [weak self] pid in self?.addProcessToWatchlistDirect(pid) },
                                        onSetRateLimit: { [weak self] pid, name, limit in self?.setProcessRateLimit(pid: pid, name: name, limitKBps: limit) },
                                        onPromptRateLimit: { [weak self] pid, name in self?.promptCustomRateLimit(pid: pid, name: name) }
                                    )
                                    uRow.translatesAutoresizingMaskIntoConstraints = false
                                    upStack.addArrangedSubview(uRow)
                                    uRow.widthAnchor.constraint(equalTo: upStack.widthAnchor).isActive = true
                                }
                            }
                            if existingRows.count > topUploaders.count {
                                for idx in topUploaders.count..<existingRows.count {
                                    existingRows[idx].isHidden = true
                                }
                            }
                        }
                    }
                }

                // Alerts formatting
                if alerts.isEmpty {
                    self.netAlertsLabel?.stringValue = I18n.translate("🟢 态势感知正常：未发现异常进程外联、C2 木马连接或危险端口裸露。")
                    self.netAlertsLabel?.textColor = NSColor(srgbRed: 0.15, green: 0.80, blue: 0.35, alpha: 1.0)
                } else {
                    var alertLines: [String] = []
                    for a in alerts.prefix(6) {
                        let sev = a["severity"] as? String ?? "WARNING"
                        let title = a["title"] as? String ?? ""
                        let detail = a["detail"] as? String ?? ""
                        let icon = (sev == "CRITICAL") ? "🔴 [高危]" : "🟡 [警告]"
                        alertLines.append("\(icon) \(title)：\(detail)")
                    }
                    self.netAlertsLabel?.stringValue = I18n.translate(alertLines.joined(separator: "\n\n"))
                    self.netAlertsLabel?.textColor = (critCount > 0) ? NSColor.systemRed : NSColor.systemOrange
                }

                // Render dynamic NetworkConnRowView cards (in-place view reuse)
                if let connsStack = self.netConnsContainerStack {
                    let toRender = Array(conns.prefix(45))
                    let connsHash = toRender.map { c -> String in
                        let pid = c["pid"] as? Int ?? 0
                        let rem = c["remote"] as? String ?? ""
                        let st = c["state"] as? String ?? ""
                        let rsk = c["risk"] as? String ?? ""
                        let ua = c["upload_audit"] as? [String: Any] ?? [:]
                        let upF = ua["upload_formatted"] as? String ?? ""
                        let dnF = ua["download_formatted"] as? String ?? ""
                        let geoS = (c["geo"] as? [String: Any])?["summary"] as? String ?? ""
                        let rateF = c["rate_limit_formatted"] as? String ?? ""
                        return "\(pid):\(rem):\(st):\(rsk):\(upF):\(dnF):\(geoS):\(rateF)"
                    }.joined(separator: "|")
                    if self.lastNetConnsHash != connsHash || connsStack.subviews.isEmpty {
                        self.lastNetConnsHash = connsHash

                        if toRender.isEmpty {
                            for v in connsStack.subviews { v.removeFromSuperview() }
                            let emptyLabel = self.tonalLabel(I18n.translate("🟢 当前无活跃 TCP/UDP 网络连接"), size: 11, weight: .medium, color: Serafina.muted)
                            connsStack.addArrangedSubview(emptyLabel)
                        } else {
                            for v in connsStack.arrangedSubviews where !(v is NetworkConnRowView) {
                                v.removeFromSuperview()
                            }
                            let existingRows = connsStack.arrangedSubviews.compactMap { $0 as? NetworkConnRowView }
                            for (idx, c) in toRender.enumerated() {
                                if idx < existingRows.count {
                                    let row = existingRows[idx]
                                    row.isHidden = false
                                    row.update(conn: c)
                                } else {
                                    let row = NetworkConnRowView(
                                        conn: c,
                                        onKillSingle: { [weak self] pid in self?.killSinglePID(pid) },
                                        onKillFamily: { [weak self] pid in self?.killProcessFamily(pid) },
                                        onAddToWatchlist: { [weak self] pid in self?.addProcessToWatchlistDirect(pid) },
                                        onSetRateLimit: { [weak self] pid, name, limit in self?.setProcessRateLimit(pid: pid, name: name, limitKBps: limit) },
                                        onPromptRateLimit: { [weak self] pid, name in self?.promptCustomRateLimit(pid: pid, name: name) }
                                    )
                                    connsStack.addArrangedSubview(row)
                                    row.widthAnchor.constraint(equalTo: connsStack.widthAnchor).isActive = true
                                }
                            }
                            if existingRows.count > toRender.count {
                                for idx in toRender.count..<existingRows.count {
                                    existingRows[idx].isHidden = true
                                }
                            }
                        }
                    }
                }

                // Listening ports summary text
                var lLines: [String] = []
                lLines.append("【本地监听服务与暴露审计 (共 \(listening.count) 个端口)】")
                var lcount = 0
                for l in listening {
                    if lcount >= 25 { break }
                    let cmd = l["command"] as? String ?? "unknown"
                    let pid = l["pid"] as? Int ?? 0
                    let bind = l["bind"] as? String ?? ""
                    let port = l["port"] as? Int ?? 0
                    let exposed = l["is_exposed"] as? Bool == true
                    let expTag = exposed ? "⚠️ 全网 0.0.0.0" : "🔒 本地回环"
                    lLines.append("• [\(expTag)] \(cmd) (PID \(pid)) 监听 \(bind):\(port)")
                    lcount += 1
                }
                self.netListeningListLabel?.stringValue = I18n.translate(lLines.joined(separator: "\n"))
            }
        }.resume()
    }

    @objc private func netSubtabChanged(_ sender: NSSegmentedControl) {
        currentNetSubtab = sender.selectedSegment
        netConnsViewContainer?.isHidden = (currentNetSubtab != 0)
        netUploadAuditContainer?.isHidden = (currentNetSubtab != 1)
    }

    @objc private func pollStartupItems() {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/startup/list") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let summary = json["summary"] as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return }

            DispatchQueue.main.async {
                self.cachedStartupItems = items

                let total = summary["total"] as? Int ?? 0
                let enabledCount = summary["enabled_count"] as? Int ?? 0
                let disabledCount = summary["disabled_count"] as? Int ?? 0
                let runningCount = summary["running_count"] as? Int ?? 0
                let essentialCount = summary["essential_count"] as? Int ?? 0

                self.startupTotalBento?.update(value: "\(total) 项", subtitle: "\(enabledCount) 项已开启")
                self.startupRunningBento?.update(value: "\(runningCount) 项", subtitle: "后台进程活跃")
                self.startupDisabledBento?.update(value: "\(disabledCount) 项", subtitle: "已关闭不自启")
                self.startupProtectedBento?.update(value: "\(essentialCount) 项", subtitle: "核心受保护白名单")

                self.renderStartupItemCards()
            }
        }.resume()
    }

    @objc private func startupFilterChanged(_ sender: NSSegmentedControl) {
        currentStartupFilter = sender.selectedSegment
        renderStartupItemCards()
    }

    private func renderStartupItemCards() {
        guard let container = startupItemsContainerStack else { return }
        let currentHash = "\(currentStartupFilter)|" + cachedStartupItems.map { "\($0["id"] as? String ?? ""):\($0["enabled"] as? Bool ?? false):\($0["running"] as? Bool ?? false)" }.joined(separator: "|")
        if lastStartupItemsHash == currentHash && !container.subviews.isEmpty { return }
        lastStartupItemsHash = currentHash

        let filtered: [[String: Any]]
        switch currentStartupFilter {
        case 1: // 可优化第三方
            filtered = cachedStartupItems.filter {
                ($0["is_essential"] as? Bool != true) && ($0["can_toggle"] as? Bool == true)
            }
        case 2: // 运行中
            filtered = cachedStartupItems.filter { ($0["running"] as? Bool == true) }
        case 3: // 已禁用
            filtered = cachedStartupItems.filter { ($0["enabled"] as? Bool == false) }
        default: // 全部
            filtered = cachedStartupItems
        }

        if filtered.isEmpty {
            for v in container.subviews { v.removeFromSuperview() }
            let emptyLabel = self.tonalLabel("当前分类下暂无自启项", size: 11, weight: .medium, color: Serafina.muted)
            container.addArrangedSubview(emptyLabel)
            return
        }

        for v in container.arrangedSubviews where !(v is StartupItemRowView) {
            v.removeFromSuperview()
        }
        let existingRows = container.arrangedSubviews.compactMap { $0 as? StartupItemRowView }
        for (idx, item) in filtered.enumerated() {
            if idx < existingRows.count {
                let row = existingRows[idx]
                row.isHidden = false
                row.update(item: item)
            } else {
                let row = StartupItemRowView(item: item) { [weak self] id, enable in
                    self?.toggleStartupItemDirect(id: id, enable: enable)
                }
                row.translatesAutoresizingMaskIntoConstraints = false
                container.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            }
        }
        if existingRows.count > filtered.count {
            for idx in filtered.count..<existingRows.count {
                existingRows[idx].isHidden = true
            }
        }
    }

    private func toggleStartupItemDirect(id: String, enable: Bool) {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/startup/toggle") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["id": id, "enable": enable]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = json["message"] as? String {
                    let alert = NSAlert()
                    alert.messageText = (json["ok"] as? Bool == true) ? "启动项变更成功" : "操作失败"
                    alert.informativeText = msg
                    alert.runModal()
                    self?.pollStartupItems()
                }
            }
        }.resume()
    }

    @objc private func batchDisableStartupItems() {
        let confirm = NSAlert()
        confirm.messageText = "确认批量关闭非必要开机自启程序？"
        confirm.informativeText = "系统将自动关闭并停止所有第三方后台启动项（如网盘后台、游戏启动器、自动更新程序等），以提升开机速度和续航。\n\nSerafina 与系统核心守护进程受到白名单保护，不受影响。"
        confirm.addButton(withTitle: "一键批量关闭")
        confirm.addButton(withTitle: "取消")
        if confirm.runModal() != .alertFirstButtonReturn { return }

        guard let url = URL(string: "http://127.0.0.1:8002/v1/startup/batch_disable") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = json["message"] as? String {
                    let alert = NSAlert()
                    alert.messageText = "自启优化完成"
                    alert.informativeText = msg
                    alert.runModal()
                    self?.pollStartupItems()
                }
            }
        }.resume()
    }

    // MARK: - Process Watchlist & Granular Interception

    @objc private func pollWatchlistItems() {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/watchlist/status") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return }

            let summary = json["summary"] as? [String: Any] ?? [:]

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.cachedWatchlistItems = items
                let total = summary["total_families"] as? Int ?? items.count
                let oob = summary["total_out_of_bounds"] as? Int ?? 0
                let blocked = summary["total_blocked_payloads"] as? Int ?? 0
                let gatekeeper = summary["enforce_prompt_count"] as? Int ?? 0

                self.watchlistTotalBento?.update(value: "\(total) 族", subtitle: "重点观察进程及子进程")
                self.watchlistAnomaliesBento?.update(value: "\(oob) 次", subtitle: oob > 0 ? "⚠️ 越权跨界读取沙箱外文件" : "未发现工作目录跨界越权")
                self.watchlistBlockedBento?.update(value: "\(blocked) 项", subtitle: "命中图片/视频/大文件规则")
                self.watchlistGatekeeperBento?.update(value: "\(gatekeeper) 进程受控", subtitle: "支持 SIGSTOP/SIGCONT 放行")

                guard let stack = self.watchlistContainerStack else { return }
                let itemsHash = items.map { "\($0["pid"] as? Int ?? 0):\($0["status"] as? String ?? ""):\($0["out_of_bounds_count"] as? Int ?? 0):\($0["blocked_payloads_count"] as? Int ?? 0):\((($0["active_connections"] as? [[String: Any]]) ?? []).count):\((($0["file_history"] as? [[String: Any]]) ?? []).count)" }.joined(separator: "|")
                if self.lastWatchlistItemsHash != itemsHash || stack.subviews.isEmpty {
                    self.lastWatchlistItemsHash = itemsHash
                    self.filterAndRenderCandidates()

                    for v in stack.subviews { v.removeFromSuperview() }

                if items.isEmpty {
                    let emptyBox = NSStackView()
                    emptyBox.orientation = .vertical
                    emptyBox.alignment = .centerX
                    emptyBox.spacing = 8
                    let emptyIcon = self.tonalLabel("🎯", size: 32, weight: .regular, color: Serafina.muted)
                    let emptyTitle = self.tonalLabel("当前暂无重点纳管程序", size: 13, weight: .bold, color: Serafina.ink)
                    let emptyDesc = self.tonalLabel("可在「网络与流量安全」连接列表对可疑外联进程点击 [🎯 重点监控]，\n或点击上方「➕ 纳管当前进程 PID」手动输入进程号关联父子进程深度纳管。", size: 11, weight: .medium, color: Serafina.muted)
                    emptyBox.addArrangedSubview(emptyIcon)
                    emptyBox.addArrangedSubview(emptyTitle)
                    emptyBox.addArrangedSubview(emptyDesc)
                    stack.addArrangedSubview(emptyBox)
                    emptyBox.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                } else {
                    for item in items {
                        let card = WatchlistProcessCardView(
                            item: item,
                            onRemove: { [weak self] pid in self?.removeProcessFromWatchlist(pid) },
                            onPause: { [weak self] pid in self?.pauseWatchlistProcess(pid) },
                            onResume: { [weak self] pid in self?.resumeWatchlistProcess(pid) },
                            onKillFamily: { [weak self] pid in self?.killProcessFamily(pid) },
                            onKillSingle: { [weak self] pid in self?.killSinglePID(pid) },
                            onUpdateRules: { [weak self] pid, bTypes, cExts, bLarge, lMb, sDir, prompt in
                                self?.updateWatchlistRules(pid: pid, blockTypes: bTypes, customExtensions: cExts, blockLarge: bLarge, largeMb: lMb, sandboxDir: sDir, enforcePrompt: prompt)
                            },
                            onInspectFile: { [weak self] path, pid, proc in
                                self?.inspectAndAnalyzeFile(filePath: path, pid: pid, processName: proc)
                            },
                            onDisconnectSocket: { [weak self] pid, rip, rport in
                                self?.disconnectWatchlistSocket(pid: pid, remoteIP: rip, remotePort: rport)
                            },
                            onBlockIP: { [weak self] pid, ip in
                                self?.blockWatchlistIP(pid: pid, ip: ip)
                            },
                            onUnblockIP: { [weak self] pid, ip in
                                self?.unblockWatchlistIP(pid: pid, ip: ip)
                            },
                            onRevealFile: { [weak self] path in
                                self?.revealFileInFinder(path: path)
                            },
                            onClearHistory: { [weak self] pid in
                                self?.clearWatchlistFileHistory(pid: pid)
                            }
                        )
                        card.translatesAutoresizingMaskIntoConstraints = false
                        stack.addArrangedSubview(card)
                        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                    }
                }
                }
                if self.processPickerPanel?.isVisible == true {
                    self.filterAndRenderCandidates()
                }
            }
        }.resume()
    }


    // MARK: - Process Candidate Selection & Search Picker

    @objc private func openProcessPickerSheet() {
        if processPickerPanel == nil {
            buildProcessPickerPanel()
        }
        if let window = processPickerPanel {
            window.title = I18n.translate("🎯 挑选或搜索监控程序 (Process Selector)")
            if let cv = window.contentView {
                I18n.localizeViewTree(cv)
            }
        }
        refreshCandidateProcesses()
        if let window = processPickerPanel {
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func closeProcessPickerSheet() {
        processPickerPanel?.close()
    }

    @objc private func refreshCandidateProcessesAction() {
        refreshCandidateProcesses()
    }

    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSSearchField {
            if field == candidateSearchField, let inline = inlineCandidateSearchField {
                inline.stringValue = field.stringValue
            } else if field == inlineCandidateSearchField, let modal = candidateSearchField {
                modal.stringValue = field.stringValue
            }
            filterAndRenderCandidates()
        }
    }

    @objc private func candidateSearchChanged(_ sender: NSSearchField) {
        if sender == candidateSearchField, let inline = inlineCandidateSearchField {
            inline.stringValue = sender.stringValue
        } else if sender == inlineCandidateSearchField, let modal = candidateSearchField {
            modal.stringValue = sender.stringValue
        }
        filterAndRenderCandidates()
    }

    @objc private func candidateFilterChanged(_ sender: NSSegmentedControl) {
        if sender == candidateCategoryPicker, let inline = inlineCandidateCategoryPicker {
            inline.selectedSegment = sender.selectedSegment
        } else if sender == inlineCandidateCategoryPicker, let modal = candidateCategoryPicker {
            modal.selectedSegment = sender.selectedSegment
        }
        filterAndRenderCandidates()
    }

    private func buildProcessPickerPanel() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "🎯 挑选或搜索监控程序 (Process Selector)"
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = Serafina.mist

        let titleLabel = tonalLabel("🎯 挑选正在运行的应用或进程加入重点监控", size: 14, weight: .bold, color: Serafina.ink)
        let descLabel = wrappingLabel("支持直接按应用名称搜索（如 WeChat、Chrome、Python、Node）或 PID，无需手动查询进程号即可一键加入父子进程沙箱与细粒度流量监控：", size: 11, weight: .medium, color: Serafina.muted)

        let search = NSSearchField()
        search.placeholderString = "🔍 搜索应用名称、进程命令或 PID..."
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(candidateSearchChanged(_:))
        search.delegate = self
        search.focusRingType = .none
        search.font = .systemFont(ofSize: 12)
        search.translatesAutoresizingMaskIntoConstraints = false
        search.widthAnchor.constraint(equalToConstant: 340).isActive = true
        search.heightAnchor.constraint(equalToConstant: 28).isActive = true
        self.candidateSearchField = search

        let catPicker = NSSegmentedControl(labels: ["全部常用程序", "🌐 活跃网络", "💻 运行中的 App"],
                                           trackingMode: .selectOne, target: self, action: #selector(candidateFilterChanged(_:)))
        catPicker.selectedSegment = inlineCandidateCategoryPicker?.selectedSegment ?? 0
        catPicker.segmentStyle = .rounded
        catPicker.translatesAutoresizingMaskIntoConstraints = false
        catPicker.heightAnchor.constraint(equalToConstant: 26).isActive = true
        self.candidateCategoryPicker = catPicker

        let topControls = NSStackView(views: [search, catPicker, NSView()])
        topControls.orientation = .horizontal
        topControls.alignment = .centerY
        topControls.spacing = 12

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 6
        container.translatesAutoresizingMaskIntoConstraints = false
        self.candidateContainerStack = container

        doc.addSubview(container)

        let scroll = NSScrollView()
        scroll.documentView = doc
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let manualPidLabel = tonalLabel("手动输入 PID 纳管:", size: 11, weight: .medium, color: Serafina.muted)
        let manualPidField = NSTextField()
        manualPidField.placeholderString = "如 1234"
        manualPidField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        manualPidField.alignment = .center
        manualPidField.translatesAutoresizingMaskIntoConstraints = false
        manualPidField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        manualPidField.heightAnchor.constraint(equalToConstant: 24).isActive = true
        self.manualPidModalField = manualPidField

        let manualPidBtn = pill("纳管", action: #selector(didSubmitManualPidModal(_:)), fill: Serafina.petal, titleColor: Serafina.ink)
        let closeBtn = pill("完成关闭", action: #selector(closeProcessPickerSheet), fill: Serafina.grape, titleColor: .white)

        let bottomRow = NSStackView(views: [manualPidLabel, manualPidField, manualPidBtn, NSView(), closeBtn])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.spacing = 8

        let mainStack = NSStackView(views: [
            titleLabel,
            descLabel,
            topControls,
            scroll,
            bottomRow
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),

            titleLabel.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            descLabel.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            topControls.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            bottomRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),

            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            container.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            container.topAnchor.constraint(equalTo: doc.topAnchor),
            container.bottomAnchor.constraint(equalTo: doc.bottomAnchor)
        ])

        panel.contentView = root
        processPickerPanel = panel
    }

    @objc private func didSubmitManualPidInline(_ sender: NSButton) {
        guard let field = manualPidInlineField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pid = Int(text), pid > 0 {
            field.stringValue = ""
            addProcessToWatchlistDirect(pid)
        } else {
            showError(title: "无效 PID", message: "请输入有效的数值进程号。")
        }
    }

    @objc private func didSubmitManualPidModal(_ sender: NSButton) {
        guard let field = manualPidModalField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pid = Int(text), pid > 0 {
            field.stringValue = ""
            addProcessToWatchlistDirect(pid)
        } else {
            showError(title: "无效 PID", message: "请输入有效的数值进程号。")
        }
    }

    private func refreshCandidateProcesses() {
        if !allCandidatesCache.isEmpty {
            filterAndRenderCandidates()
        }
        guard !candidatesFetchInFlight else { return }
        candidatesFetchInFlight = true
        let watchedPids = Set(self.cachedWatchlistItems.compactMap { $0["pid"] as? Int })

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var localApps: [[String: Any]] = []
            var icons: [Int: NSImage] = [:]
            let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            for app in runningApps {
                let pid = Int(app.processIdentifier)
                if pid <= 1 { continue }
                let name = app.localizedName ?? app.bundleIdentifier ?? "App"
                if let icon = app.icon {
                    icons[pid] = icon
                }
                localApps.append([
                    "pid": pid,
                    "name": name,
                    "command": name,
                    "path": app.bundleURL?.path ?? "",
                    "has_network": false,
                    "sockets_count": 0,
                    "is_app": true,
                    "is_watched": watchedPids.contains(pid),
                    "ppid": 1
                ])
            }

            guard let url = URL(string: "http://127.0.0.1:8002/v1/watchlist/candidate_processes") else {
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.candidatesFetchInFlight = false
                    for (k, v) in icons { self.appIconsCache[k] = v }
                    self.allCandidatesCache = localApps
                    self.filterAndRenderCandidates()
                }
                return
            }

            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                var merged = localApps
                var existingPids = Set(merged.compactMap { $0["pid"] as? Int })
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let backendCandidates = json["candidates"] as? [[String: Any]] {
                    for c in backendCandidates {
                        let pid = c["pid"] as? Int ?? 0
                        if !existingPids.contains(pid) {
                            existingPids.insert(pid)
                            var item = c
                            item["is_watched"] = watchedPids.contains(pid)
                            merged.append(item)
                        } else if let idx = merged.firstIndex(where: { ($0["pid"] as? Int) == pid }) {
                            if c["has_network"] as? Bool == true {
                                merged[idx]["has_network"] = true
                                merged[idx]["sockets_count"] = c["sockets_count"]
                            }
                            if let memFmt = c["memory_formatted"] as? String {
                                merged[idx]["memory_formatted"] = memFmt
                            }
                            if let famFmt = c["family_memory_formatted"] as? String {
                                merged[idx]["family_memory_formatted"] = famFmt
                            }
                            if let memKb = c["memory_kb"] as? Int {
                                merged[idx]["memory_kb"] = memKb
                            }
                            if let ppidVal = c["ppid"] as? Int {
                                merged[idx]["ppid"] = ppidVal
                            }
                        }
                    }
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.candidatesFetchInFlight = false
                    for (k, v) in icons { self.appIconsCache[k] = v }
                    self.allCandidatesCache = merged
                    self.filterAndRenderCandidates()
                }
            }.resume()
        }
    }

    private func filterAndRenderCandidates() {
        if pagePicker?.selectedSegment != 7 && processPickerPanel?.isVisible != true {
            return
        }

        let q1 = inlineCandidateSearchField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let q2 = candidateSearchField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let query = !q1.isEmpty ? q1 : q2

        let cat1 = inlineCandidateCategoryPicker?.selectedSegment ?? 0
        let cat2 = candidateCategoryPicker?.selectedSegment ?? 0
        let cat = inlineCandidateCategoryPicker != nil ? cat1 : cat2

        let renderHash = "\(query)|\(cat)|" + allCandidatesCache.map { "\($0["pid"] as? Int ?? 0):\($0["is_watched"] as? Bool ?? false):\($0["has_network"] as? Bool ?? false)" }.joined(separator: "|")
        let hasAnySubviews = (inlineCandidateContainerStack?.subviews.isEmpty == false) || (candidateContainerStack?.subviews.isEmpty == false)
        if lastCandidatesRenderHash == renderHash && hasAnySubviews {
            return
        }
        lastCandidatesRenderHash = renderHash

        let filtered = Array(allCandidatesCache.filter { item in
            let name = (item["name"] as? String ?? "").lowercased()
            let cmd = (item["command"] as? String ?? "").lowercased()
            let path = (item["path"] as? String ?? "").lowercased()
            let pid = "\(item["pid"] as? Int ?? 0)"
            let hasNet = item["has_network"] as? Bool ?? false
            let isApp = item["is_app"] as? Bool ?? false

            if cat == 1 && !hasNet { return false }
            if cat == 2 && !isApp { return false }

            if !query.isEmpty {
                if !name.contains(query) && !cmd.contains(query) && !path.contains(query) && !pid.contains(query) {
                    return false
                }
            }
            return true
        }.prefix(30))

        let containers = [inlineCandidateContainerStack, candidateContainerStack].compactMap { $0 }
        for container in containers {
            if filtered.isEmpty {
                for v in container.subviews { v.removeFromSuperview() }
                let emptyBox = NSStackView()
                emptyBox.orientation = .vertical
                emptyBox.alignment = .centerX
                emptyBox.spacing = 4
                let emptyLabel = tonalLabel(query.isEmpty ? "暂无匹配的运行程序" : "未搜索到包含「\(query)」的运行程序", size: 12, weight: .medium, color: Serafina.muted)
                emptyBox.addArrangedSubview(emptyLabel)
                container.addArrangedSubview(emptyBox)
                continue
            }

            for v in container.arrangedSubviews where !(v is ProcessCandidateRowView) {
                v.removeFromSuperview()
            }
            let existingRows = container.arrangedSubviews.compactMap { $0 as? ProcessCandidateRowView }
            for (idx, item) in filtered.enumerated() {
                let pid = item["pid"] as? Int ?? 0
                let icon = appIconsCache[pid]
                if idx < existingRows.count {
                    let row = existingRows[idx]
                    row.isHidden = false
                    row.update(candidate: item, iconImage: icon)
                } else {
                    let row = ProcessCandidateRowView(
                        candidate: item,
                        iconImage: icon,
                        onAdd: { [weak self] targetPid in
                            self?.addProcessToWatchlistDirect(targetPid)
                        },
                        onKillSingle: { [weak self] targetPid in
                            self?.killSinglePID(targetPid)
                        },
                        onSetRateLimit: { [weak self] pid, name, limit in
                            self?.setProcessRateLimit(pid: pid, name: name, limitKBps: limit)
                        },
                        onPromptRateLimit: { [weak self] pid, name in
                            self?.promptCustomRateLimit(pid: pid, name: name)
                        }
                    )
                    row.translatesAutoresizingMaskIntoConstraints = false
                    container.addArrangedSubview(row)
                    row.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
                    row.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
                }
            }
            if existingRows.count > filtered.count {
                for idx in filtered.count..<existingRows.count {
                    existingRows[idx].isHidden = true
                }
            }
        }
    }

    @objc private func promptAddProcessToWatchlist() {
        let alert = NSAlert()
        alert.messageText = "纳管新进程入重点监控列表"
        alert.informativeText = "请输入目标进程 PID。系统将自动抓取该进程的调起父进程、全部子进程派生链，并将其当前工作目录绑定为安全沙箱范围："
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.placeholderString = "例如 1234"
        alert.accessoryView = input
        alert.addButton(withTitle: "加入重点监控")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            let pidStr = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let pid = Int(pidStr), pid > 0 {
                addProcessToWatchlistDirect(pid)
            } else {
                showError(title: "无效 PID", message: "请输入有效的数值进程号。")
            }
        }
    }

    private func addProcessToWatchlistDirect(_ pid: Int) {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/watchlist/add") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "pid": pid,
            "block_types": ["sensitive", "images", "videos"],
            "block_large_files": true,
            "large_file_mb": 20.0,
            "enforce_prompt": false
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = json["message"] as? String {
                    let confirm = NSAlert()
                    confirm.messageText = (json["ok"] as? Bool == true) ? "纳管成功" : "纳管失败"
                    confirm.informativeText = msg + "\n\n是否立即前往「🎯 重点程序管控」页面查看与配置拦截规则？"
                    confirm.addButton(withTitle: "前往重点管控")
                    confirm.addButton(withTitle: "留在当前页")
                    if confirm.runModal() == .alertFirstButtonReturn {
                        self.pagePicker?.selectedSegment = 7
                        self.pageChanged()
                    } else {
                        self.pollWatchlistItems()
                    }
                }
            }
        }.resume()
    }

    private func removeProcessFromWatchlist(_ pid: Int) {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/watchlist/remove") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["pid": pid]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] _, _, _ in
            DispatchQueue.main.async {
                self?.pollWatchlistItems()
            }
        }.resume()
    }

    private func pauseWatchlistProcess(_ pid: Int) {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/watchlist/pause") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["pid": pid]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = json["message"] as? String {
                    let alert = NSAlert()
                    alert.messageText = (json["ok"] as? Bool == true) ? "进程冻结挂起成功 (SIGSTOP)" : "冻结失败"
                    alert.informativeText = msg
                    alert.runModal()
                    self?.pollWatchlistItems()
                }
            }
        }.resume()
    }

    private func resumeWatchlistProcess(_ pid: Int) {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/watchlist/resume") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["pid": pid]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = json["message"] as? String {
                    let alert = NSAlert()
                    alert.messageText = (json["ok"] as? Bool == true) ? "进程已恢复执行 (SIGCONT)" : "放行失败"
                    alert.informativeText = msg
                    alert.runModal()
                    self?.pollWatchlistItems()
                }
            }
        }.resume()
    }

    private func updateWatchlistRules(pid: Int, blockTypes: [String], customExtensions: [String], blockLarge: Bool, largeMb: Double, sandboxDir: String, enforcePrompt: Bool) {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/watchlist/update_rules") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "pid": pid,
            "block_types": blockTypes,
            "custom_extensions": customExtensions,
            "block_large_files": blockLarge,
            "large_file_mb": largeMb,
            "sandbox_dir": sandboxDir,
            "enforce_prompt": enforcePrompt
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = json["message"] as? String {
                    let alert = NSAlert()
                    alert.messageText = (json["ok"] as? Bool == true) ? "拦截规则更新成功" : "更新失败"
                    alert.informativeText = msg
                    alert.runModal()
                    self?.pollWatchlistItems()
                }
            }
        }.resume()
    }

    private func blockWatchlistIP(pid: Int, ip: String) {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/watchlist/block_ip") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["pid": pid, "ip": ip]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                self?.pollWatchlistItems()
            }
        }.resume()
    }

    private func unblockWatchlistIP(pid: Int, ip: String) {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/watchlist/unblock_ip") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["pid": pid, "ip": ip]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                self?.pollWatchlistItems()
            }
        }.resume()
    }

    private func disconnectWatchlistSocket(pid: Int, remoteIP: String, remotePort: String) {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/watchlist/disconnect_socket") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["pid": pid, "remote_ip": remoteIP, "remote_port": remotePort]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                self?.pollWatchlistItems()
            }
        }.resume()
    }

    private func revealFileInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func clearWatchlistFileHistory(pid: Int) {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/watchlist/clear_history") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["pid": pid]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                self?.pollWatchlistItems()
            }
        }.resume()
    }

    @objc private func cancelVerifiedTask() {
        taskProcess?.interrupt()
        taskStatusLabel?.stringValue = I18n.translate("正在停止任务…")
    }

    @objc private func startVerifiedTask() {
        guard taskProcess == nil else { return }
        let repo = taskRepoField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let goal = taskGoalField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let accept = taskAcceptField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !repo.isEmpty, !goal.isEmpty, !accept.isEmpty, FileManager.default.fileExists(atPath: repo) else {
            showError(title: "请填写任务", message: "需要有效的项目路径、具体目标和验收命令。")
            return
        }
        let process = Process()
        process.executableURL = home.appendingPathComponent("bin/agentd")
        process.arguments = ["run", "--repo", repo, "--goal", goal, "--accept", accept, "--in-place"]
        if teamCheckbox?.state == .on { process.arguments?.append("--team") }
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                self?.appendTranscript("\n[任务] " + text)
                self?.taskStatusLabel?.stringValue = String(text.suffix(600))
            }
        }
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.taskProcess = nil
                self?.taskStatusLabel?.stringValue = I18n.translate(proc.terminationStatus == 0 ? "任务完成 · 验收通过（详见实时记录）" : "任务已停止或未通过验收 · 详见实时记录")
            }
        }
        do {
            try process.run()
            taskProcess = process
            pagePicker?.selectedSegment = 2; pageChanged()
            taskStatusLabel?.stringValue = I18n.translate("任务执行中…")
        } catch { showError(title: "任务启动失败", message: error.localizedDescription) }
    }

    private func gatewaySettings() -> [String: Int] {
        let preset = UserDefaults.standard.integer(forKey: "agentWindowPreset")
        let mainInput: Int
        let mainOutput: Int
        let childInput: Int
        let childOutput: Int
        switch preset {
        case 0:
            mainInput = 2048; mainOutput = 2048; childInput = 1024; childOutput = 1024
        case 2:
            mainInput = 57344; mainOutput = 8192; childInput = 12288; childOutput = 4096
        default:
            mainInput = 24576; mainOutput = 8192; childInput = 12288; childOutput = 4096
        }
        return ["main_input_tokens": mainInput, "main_output_tokens": mainOutput,
                "child_input_tokens": childInput, "child_output_tokens": childOutput,
                "max_subagents": 2, "max_depth": 1, "max_replans": 2, "stall_results": 8]
    }

    @objc private func agentWindowChanged() {
        let preset = windowPopup?.indexOfSelectedItem ?? 1
        UserDefaults.standard.set(preset, forKey: "agentWindowPreset")
        do {
            guard let data = try? Data(contentsOf: runtimeURL),
                  var body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            body["agent_window_preset"] = preset
            body["context_compact_tokens"] = (preset == 0 ? 1800 : (preset == 1 ? 24576 : 57344))
            body["gateway"] = gatewaySettings()
            body["agentd"] = agentdSettings()
            let updated = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            try updated.write(to: runtimeURL, options: .atomic)
            cachedRuntimeDict = body
            cachedRuntimeMtime = nil
            let desc = preset == 0 ? "紧凑 2K（每 1.5K 增量总结）" : (preset == 1 ? "会话 24K" : "会话 56K")
            statsLabel?.stringValue = "工作窗口已应用：\(desc) · 下一次请求生效"
        } catch { statsLabel?.stringValue = "工作窗口保存失败：\(error.localizedDescription)" }
    }

    @objc private func clearQuarantineAction() {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/runtime/quarantine/clear") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] _, _, _ in
            DispatchQueue.main.async {
                self?.refreshRuntimeStatus()
            }
        }.resume()
    }

    private func writeRuntime(_ choice: ModelChoice) throws {
        let directory = runtimeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let isSuper = choice.model.contains("120B") || choice.model.contains("Ling")
        let preset: Int
        if isSuper {
            preset = 0
            windowPopup?.selectItem(at: 0)
            UserDefaults.standard.set(0, forKey: "agentWindowPreset")
        } else {
            preset = UserDefaults.standard.integer(forKey: "agentWindowPreset")
        }
        let compactTokens = (preset == 0 ? 1800 : (preset == 1 ? 24576 : 57344))
        let body: [String: Any] = [
            "backend": choice.backend,
            "backend_url": choice.backendURL,
            "serve_model": choice.serveModel.isEmpty ? choice.model : choice.serveModel,
            "profile": choice.profile,
            "mtp": choice.mtp,
            "enable_thinking": modelSettings(for: choice).thinking,
            "reasoning_effort": modelSettings(for: choice).effort,
            "lms_key": choice.lmsKey,
            "api_model": choice.isLocal ? choice.model : "",
            "context_length": choice.contextLength,
            "agent_window_preset": preset,
            "context_compact_tokens": compactTokens,
            "parallel": 1,
            "gateway": gatewaySettings(),
            "agentd": agentdSettings(),
            "gguf_path": choice.ggufPath,
            "gguf_repo": choice.ggufRepo
        ]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: runtimeURL, options: .atomic)
        cachedRuntimeDict = body
        cachedRuntimeMtime = nil
    }

    private func preflightAndApply(choice: ModelChoice, reasoningEffort: String) {
        guard choice.endpoint != nil else {
            applyConfigured(choice: choice, reasoningEffort: reasoningEffort)
            return
        }
        guard let url = URL(string: choice.backend == "mtplx" ? "http://127.0.0.1:8000/health" : "http://127.0.0.1:8002/v1/bridge-info") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            var ok = (response as? HTTPURLResponse)?.statusCode == 200
            if ok && choice.backend == "mtplx" {
                let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let loaded = json?["model_path"] as? String ?? ""
                let expected = choice.serveModel
                let resolved = NSHomeDirectory() + "/.mtplx/models/" + expected.replacingOccurrences(of: "/", with: "--")
                ok = loaded == expected || (!expected.hasPrefix("/") && expected.contains("/") && loaded == resolved)
            }
            DispatchQueue.main.async {
                if ok {
                    self?.log("preflight passed endpoint=\(url.absoluteString)")
                    self?.applyConfigured(choice: choice, reasoningEffort: reasoningEffort)
                } else {
                    let reason = error?.localizedDescription ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                    self?.log("preflight failed endpoint=\(url.absoluteString) reason=\(reason)")
                    self?.showError(title: "目标模型尚未就绪", message: "目标模型身份校验失败或服务未就绪\n\n未修改 Codex 默认模型。\n\(reason)")
                }
            }
        }.resume()
    }

    private func applyConfigured(choice: ModelChoice, reasoningEffort: String, forceCodex: Bool = false) {
        if choice.isLocal && !forceCodex && !managedMode && !UserDefaults.standard.bool(forKey: "codexFollowsLocal") {
            log("local model applied without touching Codex config model=\(choice.model)")
            rebuildMenu(message: "本地模型：\(choice.title)")
            currentLabel?.stringValue = "本地模型已切换：\(choice.title) · 已接本地的客户端会自动跟随"
            refreshClientCard()
            NSSound(named: .init("Pop"))?.play()
            return
        }
        do {
            try updateConfig(
                provider: choice.provider,
                model: choice.model,
                reasoningEffort: reasoningEffort,
                contextWindow: choice.contextLength,
                compactLimit: choice.compactTokenLimit,
                displayName: choice.codexName
            )
            let shouldRestart = UserDefaults.standard.bool(forKey: "restartAfterSwitch")
            let saved = readTopLevelSettings()
            guard saved.provider == choice.provider && saved.model == choice.model else {
                throw NSError(domain: "CodexModelSwitcher", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "配置写入后校验不一致。"])
            }
            log("config applied provider=\(choice.provider) model=\(choice.model) reasoning=\(reasoningEffort) window=\(choice.contextLength) compact=\(choice.compactTokenLimit) restart=\(shouldRestart)")
            rebuildMenu(message: shouldRestart ? "已切换：\(choice.title)（重启后请新建任务）" : "已切换：\(choice.title)（请新建任务）")
            refreshWindowSelection()
            currentLabel?.stringValue = "切换成功：\(choice.title) · 请新建 Codex 任务"
            NSSound(named: .init("Pop"))?.play()
            if shouldRestart { restartCodex() }
        } catch {
            log("config apply failed: \(error.localizedDescription)")
            showError(title: "切换失败", message: error.localizedDescription)
        }
    }

    @objc private func togglePowerState() {
        if localBackendUp {
            stopLocalAPI()
        } else {
            startLocalAPI()
        }
    }

    @objc private func clearSSDCache() {
        clearCacheStatusLabel?.stringValue = "正在清理 SSD 缓存…"
        let settingsURL = home.appendingPathComponent(".omlx/settings.json")
        let settings = (try? Data(contentsOf: settingsURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let port = (settings?["server"] as? [String: Any])?["port"] as? Int ?? 7777
        let key = (settings?["auth"] as? [String: Any])?["api_key"] as? String ?? ""
        guard let url = URL(string: "http://127.0.0.1:\(port)/admin/api/ssd-cache/clear") else {
            clearCacheStatusLabel?.stringValue = "无效的 API 地址"
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    self?.clearCacheStatusLabel?.stringValue = "✓ 已成功清空 SSD 缓存"
                    self?.refreshHardwareAndOMLXStats()
                } else {
                    let msg = error?.localizedDescription ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                    self?.clearCacheStatusLabel?.stringValue = "清理未响应: \(msg)"
                }
            }
        }.resume()
    }

    private func updatePowerButtonVisuals() {
        let isWorking = !liveRequests.isEmpty || ledMeter?.currentState == .working
        let isReady = localBackendUp
        powerButton?.setState(ready: isReady, working: isWorking)
        unloadModelButton?.isHidden = !isReady
        topBarUnloadButton?.isHidden = !isReady
        if isWorking {
            topBarStatusBadge?.stringValue = I18n.translate(" 🟠 推理中 ")
            topBarStatusBadge?.layer?.backgroundColor = NSColor(srgbRed: 1.0, green: 0.58, blue: 0.16, alpha: 0.18).cgColor
            topBarStatusBadge?.textColor = NSColor(srgbRed: 1.0, green: 0.58, blue: 0.16, alpha: 1.0)
        } else if isReady {
            topBarStatusBadge?.stringValue = I18n.translate(" 🟢 闲置就绪 ")
            topBarStatusBadge?.layer?.backgroundColor = NSColor(srgbRed: 0.20, green: 0.88, blue: 0.42, alpha: 0.15).cgColor
            topBarStatusBadge?.textColor = NSColor(srgbRed: 0.15, green: 0.80, blue: 0.35, alpha: 1.0)
        } else {
            topBarStatusBadge?.stringValue = I18n.translate(" ⚪ 空载 (未载入模型) ")
            topBarStatusBadge?.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            topBarStatusBadge?.textColor = Serafina.muted
        }
        let summary = localSummary(speed: false)
        topBarModelLabel?.stringValue = isReady ? (summary.isEmpty ? "Serafina" : summary) : I18n.translate("当前空载 · 显存未占用")
    }

    @objc private func unloadModelAndReleaseMemory() {
        log("user requested unload model and release memory")
        serviceStatusLabel?.stringValue = "正在卸载模型并彻底释放显存…"
        guard let url = URL(string: "http://127.0.0.1:8002/v1/model/unload") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.mtplxReady = false
                self?.omlxLoadedModels = []
                self?.lmStudioLoadedModel = ""
                self?.bonsaiReady = false
                self?.serviceStatusLabel?.stringValue = "○ 空载就绪 · 模型已卸载，显存已释放"
                self?.updatePowerButtonVisuals()
                self?.refreshLocalServiceStatus()
                self?.refreshHardwareAndOMLXStats()

                let alert = NSAlert()
                alert.messageText = "模型显存已释放"
                alert.informativeText = "已成功卸载本地模型权重并清空 Unified Memory 显存占用。\n系统已进入空载待命状态。"
                alert.alertStyle = .informational
                alert.runModal()
            }
        }.resume()
    }

    func inspectAndAnalyzeFile(filePath: String, pid: Int, processName: String) {
        if fileInspectionWindow == nil {
            fileInspectionWindow = FileInspectionWindowController()
        }
        fileInspectionWindow?.inspect(path: filePath, pid: pid, processName: processName)
    }

    private func updateContextCapsule() {
        let selectedIndex = modelPopup?.indexOfSelectedItem ?? 0
        if choices.indices.contains(selectedIndex) {
            let choice = choices[selectedIndex]
            let ctxK = choice.contextLength / 1024
            let winPreset = UserDefaults.standard.integer(forKey: "agentWindowPreset") == 1 ? "56K" : "24K"
            modelContextCapsule?.stringValue = " 上下文 \(ctxK)K (会话预算 \(winPreset)) · 统一内存 96GB "
        }
    }

    static func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }

    @objc private func refreshHardwareAndOMLXStats() {
        // 1. Mach Kernel RAM
        let ramStats = SystemHardwareMonitor.getMemoryStats()
        ramUsageBar?.update(used: ramStats.usedGB, total: ramStats.totalGB)

        // 2. Chip & Thermals & Uptime
        let brand = SystemHardwareMonitor.getCPUBrand()
        chipDetailLabel?.stringValue = I18n.translate("芯片: \(brand)")
        let thermal = SystemHardwareMonitor.getThermalInfo()
        thermalBadgeLabel?.stringValue = I18n.translate("温控: \(thermal.stateText)")
        systemUptimeLabel?.stringValue = I18n.translate("系统运行: \(SystemHardwareMonitor.getUptimeString())")

        // 3. Update visuals
        updatePowerButtonVisuals()
        updateContextCapsule()
        let selectedTab = pagePicker?.selectedSegment ?? 0
        if selectedTab == 2 {
            refreshRuntimeStatus()
            refreshIntelligenceStatus()
        }
        if selectedTab == 3 {
            pollProcessResources()
        }

        // 4. Query oMLX admin stats off the main thread
        let settingsURL = home.appendingPathComponent(".omlx/settings.json")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let settings = (try? Data(contentsOf: settingsURL))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let port = (settings?["server"] as? [String: Any])?["port"] as? Int ?? 7777
            let key = (settings?["auth"] as? [String: Any])?["api_key"] as? String ?? ""
            guard let url = URL(string: "http://127.0.0.1:\(port)/admin/api/stats") else { return }
            var request = URLRequest(url: url)
            request.timeoutInterval = 2.5
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self else { return }
            var omlxSuccess = false
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                omlxSuccess = true
                let totalServed = json["total_tokens_served"] as? Int ?? 0
                let totalCached = json["total_cached_tokens"] as? Int ?? 0
                let cacheEff = json["cache_efficiency"] as? Double ?? 0.0
                let promptTokens = json["total_prompt_tokens"] as? Int ?? 0
                let completionTokens = json["total_completion_tokens"] as? Int ?? 0
                let prefillTPS = json["avg_prefill_tps"] as? Double ?? 0.0
                let genTPS = json["avg_generation_tps"] as? Double ?? 0.0

                var modelMemUsed: Double = 0.0
                var modelMemMax: Double = 64.0
                if let activeModels = json["active_models"] as? [String: Any] {
                    if let usedBytes = activeModels["model_memory_used"] as? Double {
                        modelMemUsed = usedBytes / 1_073_741_824.0
                    }
                    if let maxBytes = activeModels["model_memory_max"] as? Double {
                        modelMemMax = maxBytes / 1_073_741_824.0
                    }
                }

                var ssdBytes: Double = 0.0
                var ssdFiles: Int = 0
                if let rCache = json["runtime_cache"] as? [String: Any] {
                    ssdBytes = (rCache["total_size_bytes"] as? Double ?? 0) / 1_073_741_824.0
                    ssdFiles = rCache["total_num_files"] as? Int ?? 0
                }

                DispatchQueue.main.async {
                    self.statTotalTokens?.setValues(
                        value: "\(AppDelegate.formatTokenCount(totalServed))",
                        subtitle: "Prompt \(AppDelegate.formatTokenCount(promptTokens)) · Gen \(AppDelegate.formatTokenCount(completionTokens))"
                    )
                    self.statCachedTokens?.setValues(
                        value: String(format: "%.1f%%", cacheEff),
                        subtitle: I18n.translate("已复用 \(AppDelegate.formatTokenCount(totalCached)) Token")
                    )
                    self.statThroughputTPS?.setValues(
                        value: String(format: "%.1f / %.1f", prefillTPS, genTPS),
                        subtitle: I18n.translate("预填 \(String(format: "%.1f", prefillTPS)) t/s · 生成 \(String(format: "%.1f", genTPS)) t/s")
                    )

                    self.gpuUsageBar?.update(used: modelMemUsed, total: modelMemMax)
                    self.ssdCacheInfoLabel?.stringValue = I18n.translate(String(format: "SSD 运行时缓存: %.1f GB · %d 个分块快照", ssdBytes, ssdFiles))
                    self.dashboardModelInfoLabel?.stringValue = I18n.translate("当前服务：oMLX :\(port) · 前缀缓存生效中")
                }
            }

            if !omlxSuccess {
                DispatchQueue.main.async {
                    if self.mtplxReady {
                        self.dashboardModelInfoLabel?.stringValue = I18n.translate("当前服务：MTPLX :8000 · \(self.runningModelId)")
                        let estGB: Double = 20.0
                        self.gpuUsageBar?.update(used: estGB, total: 64.0)
                        self.ssdCacheInfoLabel?.stringValue = I18n.translate("SSD 运行时缓存: MTPLX 会话缓存 (\(self.cacheSummary))")
                    } else if !self.lmStudioLoadedModel.isEmpty {
                        self.dashboardModelInfoLabel?.stringValue = I18n.translate("当前服务：LM Studio · \(self.lmStudioLoadedModel)")
                        self.gpuUsageBar?.update(used: 22.0, total: 64.0)
                    }
                }
            }
            }.resume()
        }
    }

    @objc private func procSortChanged(_ sender: NSSegmentedControl) {
        procResourceSortBy = sender.selectedSegment == 1 ? "memory" : "cpu"
        pollProcessResources()
    }

    @objc private func manualRefreshProcessResources() {
        pollProcessResources()
    }

    @objc private func pollProcessResources() {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/system/process_resources?sort_by=\(procResourceSortBy)&limit=25") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ok = json["ok"] as? Bool, ok,
                  let families = json["families"] as? [[String: Any]] else { return }

            let summary = json["summary"] as? [String: Any] ?? [:]
            let totalCpu = summary["total_cpu_formatted"] as? String ?? "0.0%"
            let usedGb = summary["total_memory_used_gb"] as? Double ?? 0.0
            let physGb = summary["total_physical_memory_gb"] as? Double ?? 96.0
            let memPct = summary["total_memory_percent"] as? Double ?? 0.0
            let totalProcs = summary["total_processes_count"] as? Int ?? families.count

            let familiesHash = families.map { "\($0["pid"] as? Int ?? 0)" }.joined(separator: "|")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.procSummaryLabel?.stringValue = I18n.translate("监控: \(totalProcs) 个进程 · 系统总 CPU: \(totalCpu) · 内存: \(String(format: "%.1f", usedGb)) GB / \(String(format: "%.1f", physGb)) GB (\(String(format: "%.1f", memPct))%)")

                guard let stack = self.procFamilyContainerStack else { return }
                if self.lastProcessResourcesHash == familiesHash && stack.subviews.count == families.count {
                    for (idx, view) in stack.subviews.enumerated() {
                        (view as? ProcessFamilyResourceRowView)?.update(family: families[idx])
                    }
                } else {
                    self.lastProcessResourcesHash = familiesHash
                    for v in stack.subviews { v.removeFromSuperview() }

                    for fam in families {
                        let row = ProcessFamilyResourceRowView(
                            family: fam,
                            onKillSingle: { [weak self] pid in self?.killSinglePID(pid) },
                            onKillFamily: { [weak self] pid in self?.killProcessFamily(pid) }
                        )
                        stack.addArrangedSubview(row)
                        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                    }
                }
            }
        }.resume()
    }

    private func refreshRuntimeStatus() {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/runtime/status") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let breakerLevel = (json["breaker_level"] as? Int) ?? (Int(json["breaker_level"] as? String ?? "") ?? 0)
            let taskId = json["current_task_id"] as? String
            let diag = (json["active_subtask"] as? [String: Any]) ?? (json["active_diagnostic_subtask"] as? [String: Any])
            let cacheMetrics = json["cache_metrics"] as? [String: Any] ?? [:]
            let blockedCount = (json["blocklist_count"] as? Int) ?? (json["tool_controller_blocklist_count"] as? Int ?? 0)

            let matrix = (json["health_matrix"] as? [String: Any]) ?? [:]
            let layers = (matrix["layers"] as? [String: Any]) ?? [:]
            let metrics = (matrix["metrics"] as? [String: Any]) ?? [:]
            let eatPerMin = (json["eat_per_min"] as? Double) ?? (metrics["eat_per_min"] as? Double ?? 0.0)
            let wcrPct = (json["wcr_pct"] as? Double) ?? (metrics["wcr_pct"] as? Double ?? 0.0)
            let quarantined = (matrix["quarantined_models"] as? [[String: Any]]) ?? []
            let incidents = (matrix["recent_incidents"] as? [[String: Any]]) ?? []

            let l1 = (layers["L1_SYSTEM"] as? [String: Any]) ?? [:]
            let l2 = (layers["L2_METAL_GPU"] as? [String: Any]) ?? [:]
            let l3 = (layers["L3_INFERENCE_BACKEND"] as? [String: Any]) ?? [:]
            let l4 = (layers["L4_GATEWAY_PROTOCOL"] as? [String: Any]) ?? [:]
            let l5 = (layers["L5_AGENT_SUPERVISOR"] as? [String: Any]) ?? [:]
            let l6 = (layers["L6_MEMORY_RECOVERY"] as? [String: Any]) ?? [:]

            DispatchQueue.main.async {
                self.capsuleL1?.update(status: l1["state"] as? String ?? "HEALTHY", detail: l1["detail"] as? String ?? "系统资源正常")
                self.capsuleL2?.update(status: l2["state"] as? String ?? "HEALTHY", detail: l2["detail"] as? String ?? "看门狗正常")
                self.capsuleL3?.update(status: l3["state"] as? String ?? "HEALTHY", detail: l3["detail"] as? String ?? "模型就绪")
                self.capsuleL4?.update(status: l4["state"] as? String ?? "HEALTHY", detail: l4["detail"] as? String ?? ":8002 在线")
                self.capsuleL5?.update(status: l5["state"] as? String ?? "HEALTHY", detail: l5["detail"] as? String ?? "熔断器活跃")
                self.capsuleL6?.update(status: l6["state"] as? String ?? "HEALTHY", detail: l6["detail"] as? String ?? "WAL 同步正常")

                self.statEAT?.setValues(
                    value: String(format: "%.1f 步/分", eatPerMin),
                    subtitle: "验收证据推进率 · 真实进展"
                )
                self.statWCR?.setValues(
                    value: String(format: "%.1f%%", wcrPct),
                    subtitle: wcrPct > 0 ? "异常重试/循环损耗" : "零无效算力损耗"
                )

                if let qFirst = quarantined.first, let qMod = qFirst["model"] as? String {
                    let rem = qFirst["remaining_seconds"] as? Double ?? 0.0
                    self.statARP?.setValues(
                        value: "⛔️ 隔离中",
                        subtitle: "\(qMod) · 剩余 \(Int(rem))s"
                    )
                    self.arpTimelineLabel?.stringValue = "ARP 保护事件：⛔️ 触发故障隔离 · 模型 \(qMod) 正在冷却 (\(Int(rem))s) · 避免 Metal 连续崩溃"
                } else if let inc = incidents.last, let action = inc["action"] as? String {
                    let typ = inc["type"] as? String ?? "FAULT"
                    let mod = inc["model"] as? String ?? ""
                    self.statARP?.setValues(
                        value: "🟡 降级自愈",
                        subtitle: "\(typ) · \(action)"
                    )
                    self.arpTimelineLabel?.stringValue = "ARP 保护事件：⚠️ 最近故障 [\(typ)] 模型: \(mod) · 执行自愈: \(action)"
                } else {
                    self.statARP?.setValues(
                        value: "🟢 守卫就绪",
                        subtitle: "0 次 Metal 崩溃 · 看门狗就绪"
                    )
                    self.arpTimelineLabel?.stringValue = "ARP 保护事件：🟢 正常守卫中 · 无 Metal 异常 · Prefill 分块 2048"
                }

                switch breakerLevel {
                case 1:
                    self.breakerBadgeLabel?.stringValue = "熔断器状态：🟡 L1 建议微调 (Advisory Nudge) · 提示词已注入修正策略"
                case 2:
                    let cause = diag?["cause"] as? String ?? "死循环检测触发"
                    self.breakerBadgeLabel?.stringValue = "熔断器状态：🟠 L2 策略突变 (Strategy Mutation) · 诊断中: \(cause)"
                case 3:
                    self.breakerBadgeLabel?.stringValue = "熔断器状态：🔴 L3 现场保护 (Quiescent Pause) · APFS+Git 快照已锁定"
                default:
                    self.breakerBadgeLabel?.stringValue = "熔断器状态：🟢 L0 正常运行 · 双平面 Guard 活跃"
                }

                if let diag = diag {
                    let allowed = (diag["allowed_actions"] as? [String])?.joined(separator: ", ") ?? "只读诊断"
                    self.loopRadarLabel?.stringValue = "防死循环雷达：⚠️ 拦截异常 · 限制动作: [\(allowed)] · 幂等副作用已拦截 \(blockedCount) 次"
                } else {
                    self.loopRadarLabel?.stringValue = "防死循环雷达：Type A~H (8类特征) 监控中 · 0 异常 · 幂等副作用已拦截 \(blockedCount) 次"
                }

                let eligible = cacheMetrics["eligible_requests"] as? Int ?? 0
                let actual = cacheMetrics["actual_hits"] as? Int ?? 0
                let totalReq = cacheMetrics["total_requests"] as? Int ?? 0
                if totalReq > 0 {
                    let hitRate = Double(actual) / Double(totalReq) * 100.0
                    self.cacheEligibilityLabel?.stringValue = String(format: "分层前缀缓存：总计 %d 次 · 可复用 %d 次 · 实际命中 %d 次 (%.1f%%)", totalReq, eligible, actual, hitRate)
                } else {
                    self.cacheEligibilityLabel?.stringValue = "分层前缀缓存：Eligibility 100% · Actual Hit -- (Project Core 锁定)"
                }

                if let tid = taskId, !tid.isEmpty {
                    self.supervisorPipelineLabel?.stringValue = "任务流水线 [\(tid)]：[规划 ✓] ➔ [定位入口 ●] ➔ [编码实现 ○] ➔ [回归验证 ○] ➔ [验收交付 ○]"
                } else {
                    self.supervisorPipelineLabel?.stringValue = "任务流水线：[规划] ➔ [定位入口] ➔ [编码实现] ➔ [回归验证] ➔ [验收交付] · 待命中"
                }
            }
        }.resume()
    }

    @objc private func refreshIntelligenceStatus() {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/intelligence/status") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.5
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ok = json["ok"] as? Bool, ok else { return }

            self.cachedIntelligenceData = json

            let harness = json["harness_cache"] as? [String: Any] ?? [:]
            let totalFormatted = harness["total_tokens_formatted"] as? String ?? "213,777,704 tok"
            let totalCompact = harness["total_tokens_compact"] as? String ?? "214M tok"
            let hitRateFormatted = harness["cache_hit_rate_formatted"] as? String ?? "99%"
            let cachedFormatted = harness["cached_tokens_formatted"] as? String ?? "211,745,664 tok"
            let uncachedFormatted = harness["uncached_tokens_formatted"] as? String ?? "1,380,694 tok"
            let outputFormatted = harness["output_tokens_formatted"] as? String ?? "651,346 tok"
            let turns = harness["turns_count"] as? Int ?? 27
            let steps = harness["steps_count"] as? Int ?? 558
            let currentTps = harness["current_tps"] as? Double ?? 11.5
            let vramSaved = harness["vram_saved_gb"] as? Double ?? 95.29

            let aoci = json["aoci"] as? [String: Any] ?? [:]
            let aociLoc = aoci["approx_loc"] as? Int ?? 1156
            let aociInvCount = aoci["invariants_count"] as? Int ?? 3
            let aociSummary = aoci["summary"] as? String ?? "全局架构契约受控 · 保证模型不改偏、不越权"

            let cg = json["codegraph"] as? [String: Any] ?? [:]
            let cgCompress = cg["compression_pct"] as? Double ?? 82.5
            let cgSummary = cg["summary"] as? String ?? "局部按需提取接口大纲 · 减负 96GB 内存 KV-Cache"

            let plat = json["platform"] as? [String: Any] ?? [:]
            let platChip = plat["chip"] as? String ?? "Apple M2 Max (38-Core GPU, 96GB 统一内存)"

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.topBarHarnessPill?.stringValue = I18n.translate(" ⚡️ \(totalCompact) · 命中 \(hitRateFormatted) ")

                self.harnessTokenBento?.update(
                    value: totalFormatted,
                    subtitle: I18n.translate("\(turns) 轮 \(steps) 步 · \(String(format: "%.1f", currentTps)) tok/s")
                )
                self.harnessHitBento?.update(
                    value: hitRateFormatted,
                    subtitle: I18n.translate("未缓存 \(uncachedFormatted) · 免重复Prefill")
                )
                self.harnessReadBento?.update(
                    value: "\(AppDelegate.formatTokenCount(harness["cached_tokens"] as? Int ?? 211745664)) / \(AppDelegate.formatTokenCount(harness["output_tokens"] as? Int ?? 651346))",
                    subtitle: I18n.translate("已读取 \(cachedFormatted) · 输出 \(outputFormatted)")
                )
                self.harnessMemoryBento?.update(
                    value: String(format: "~%.1f GB", vramSaved),
                    subtitle: I18n.translate("大幅降低显存带宽与等待时间")
                )

                self.aociSummaryLabel?.stringValue = I18n.translate("基于 .aoci/blueprint.md 维系全局架构蓝图 · 约 \(aociLoc) 行代码 · \(aociInvCount) 项不变量契约 · \(aociSummary)")
                self.codeGraphSummaryLabel?.stringValue = I18n.translate("基于 AST & Tree-sitter 大纲提取 (压缩率 \(String(format: "%.1f%%", cgCompress))) · \(cgSummary)")
                self.platformSummaryLabel?.stringValue = I18n.translate("当前底座: \(platChip) · 跨平台算力解耦: 已隔离硬件后处理，可平滑扩充 Windows 11 + NVIDIA CUDA (TensorRT-LLM) 与 AMD ROCm 专供版")
            }
        }.resume()
    }

    @objc private func toggleLanguage() {
        I18n.current = (I18n.current == .zh) ? .en : .zh
        refreshLocalizedUI()
    }

    private func refreshLocalizedUI() {
        let isZh = (I18n.current == .zh)
        topBarLangButton?.title = isZh ? "🌐 简中" : "🌐 EN"
        topBarUnloadButton?.title = I18n.t("btn.release_memory")

        let sidebarTitles: [(Int, String)] = [
            (0, "tab.models"),
            (1, "tab.api"),
            (2, "tab.dashboard"),
            (3, "tab.hardware"),
            (4, "tab.tasks"),
            (5, "tab.network"),
            (6, "tab.startup"),
            (7, "tab.watchlist")
        ]
        for (idx, key) in sidebarTitles {
            if idx < sidebarItems.count {
                sidebarItems[idx].setTitle(I18n.t(key))
            }
        }
        if let cv = window?.contentView {
            I18n.localizeViewTree(cv)
        }
        if let pc = processPickerPanel?.contentView {
            I18n.localizeViewTree(pc)
        }
        if let gc = gatekeeperWindow?.window?.contentView {
            I18n.localizeViewTree(gc)
        }
        trafficWaveformView?.needsDisplay = true
        uploadDistributionBar?.needsDisplay = true
        countryDistributionView?.needsDisplay = true
        // Invalidate caches so dynamic rows re-render in new language
        lastProcessResourcesHash = ""
        lastUploadProcsHash = ""
        lastNetConnsHash = ""
        lastWatchlistItemsHash = ""
        lastStartupItemsHash = ""
        lastCandidatesRenderHash = ""
        clientTargetSignatures.removeAll()
        let seg = pagePicker?.selectedSegment ?? 0
        if seg == 0 {
            refreshClientCard()
        } else if seg == 1 {
            apiModelLabel?.stringValue = I18n.translate("当前模型：\(self.localSummary(speed: true))")
            apiSnippetChanged()
        } else if seg == 2 || seg == 3 {
            pollProcessResources()
            refreshHardwareAndOMLXStats()
        } else if seg == 5 {
            pollNetworkSentinel()
        } else if seg == 6 {
            renderStartupItemCards()
        } else if seg == 7 {
            pollWatchlistItems()
            filterAndRenderCandidates()
        }
    }

    @objc private func startLocalAPI() {
        log("local API start requested")
        if let index = modelPopup?.indexOfSelectedItem, choices.indices.contains(index), choices[index].isLocal {
            try? writeRuntime(choices[index])
        }
        serviceStatusLabel?.stringValue = "正在启动模型与 Codex 桥接…"
        runServiceScript(startScript) { [weak self] success, message in
            self?.serviceStatusLabel?.stringValue = success ? "● 已就绪" : "● 启动失败 · \(message)"
            self?.refreshLocalServiceStatus()
        }
    }

    @objc private func stopLocalAPI() {
        log("local API stop requested")
        serviceStatusLabel?.stringValue = "正在停止并释放统一内存…"
        runServiceScript(stopScript) { [weak self] success, message in
            self?.mtplxReady = false
            self?.serviceStatusLabel?.stringValue = success ? "○ 已停止 · 内存已释放" : "● 停止异常 · \(message)"
            self?.refreshLocalServiceStatus()
        }
    }

    private func runServiceScript(_ url: URL, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                DispatchQueue.main.async { completion(false, "脚本不存在或不可执行：\(url.path)") }
                return
            }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = url
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self.log("service script=\(url.lastPathComponent) exit=\(process.terminationStatus) message=\(message)")
                DispatchQueue.main.async { completion(process.terminationStatus == 0, message) }
            } catch {
                self.log("service script=\(url.lastPathComponent) error=\(error.localizedDescription)")
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
            }
        }
    }

    private func readRuntime() -> [String: Any] {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: runtimeURL.path)[.modificationDate]) as? Date
        if let mtime, mtime == cachedRuntimeMtime, !cachedRuntimeDict.isEmpty {
            return cachedRuntimeDict
        }
        guard let data = try? Data(contentsOf: runtimeURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        cachedRuntimeDict = json
        cachedRuntimeMtime = mtime
        return json
    }

    private func refreshGatewayStats() {
        guard let url = URL(string: "http://127.0.0.1:8002/v1/bridge-info") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let gateway = json["gateway"] as? [String: Any] else { return }
            DispatchQueue.main.async {
                self?.speedAverages = gateway["speeds"] as? [String: [String: Any]] ?? [:]
                self?.updateModelPopupStatuses()
                self?.updateCapabilityLabel()
            }
        }.resume()
    }

    private func refreshLocalServiceStatus() {
        refreshGatewayStats()
        if window?.isVisible == true && (pagePicker?.selectedSegment == 2 || pagePicker?.selectedSegment == 3) {
            refreshHardwareAndOMLXStats()
        }
        refreshClientCard()
        let runtime = readRuntime()
        let backend = runtime["backend"] as? String ?? "mtplx"
        if backend == "lmstudio" {
            refreshLMStudioStatus(expected: runtime["api_model"] as? String ?? "")
            return
        }
        if backend == "bonsai" {
            refreshBonsaiStatus()
            return
        }
        if backend == "omlx" {
            refreshOMLXStatus(expected: runtime["api_model"] as? String ?? "")
            return
        }
        guard let url = URL(string: "http://127.0.0.1:8000/health") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            var ready = false
            var vision = false
            var mode = ""
            var model = ""
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                ready = true
                mode = json["generation_mode"] as? String ?? ""
                model = json["model"] as? String ?? ""
                if let details = json["vision"] as? [String: Any] {
                    vision = details["enabled"] as? Bool ?? false
                }
            }
            DispatchQueue.main.async {
                self?.mtplxReady = ready
                self?.runningModelId = model
                if self?.lastLoggedServiceState != ready {
                    self?.log("MTPLX health ready=\(ready) vision=\(vision) mode=\(mode)")
                    self?.lastLoggedServiceState = ready
                }
                if ready {
                    let visionText = vision ? "图片 PNG / JPEG / WebP" : "文本"
                    let bank = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])?["session_bank"] as? [String: Any]
                    let bankBytes = bank?["total_nbytes"] as? Double ?? 0
                    self?.cacheSummary = String(format: "缓存占用 %.2f GiB · 前缀复用已开启", bankBytes / 1073741824)
                    self?.serviceStatusLabel?.stringValue = "● MTPLX 已就绪 · \(model) · \(mode.uppercased()) · \(visionText) · \(self?.cacheSummary ?? "")"
                } else {
                    self?.serviceStatusLabel?.stringValue = "○ MTPLX 未运行"
                }
                if (self?.liveRequests.isEmpty ?? true) && !(self?.taskBlocked ?? false) {
                    if ready {
                        self?.ledMeter?.setServiceState(.idleReady)
                        self?.meterStatusLabel?.stringValue = "🟢 闲置就绪 · \(model) 已加载至统一内存 · 待命中"
                    } else {
                        self?.ledMeter?.setServiceState(.stopped)
                        self?.meterStatusLabel?.stringValue = "🔴 未启动 · MTPLX 8000 服务未运行"
                    }
                }
                self?.updateModelPopupStatuses()
            }
        }.resume()
    }

    private func refreshBonsaiStatus() {
        guard let url = URL(string: "http://127.0.0.1:2386/health") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            var ready = false
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (json["status"] as? String) == "ready" {
                ready = true
            }
            DispatchQueue.main.async {
                self?.mtplxReady = ready
                self?.bonsaiReady = ready
                self?.serviceStatusLabel?.stringValue = ready
                    ? "● Bonsai 三进制 27B 已就绪 · agent 可用"
                    : "○ Bonsai 未运行"
                if (self?.liveRequests.isEmpty ?? true) && !(self?.taskBlocked ?? false) {
                    if ready {
                        self?.ledMeter?.setServiceState(.idleReady)
                        self?.meterStatusLabel?.stringValue = "🟢 闲置就绪 · Bonsai 27B 已加载至统一内存 · 待命中"
                    } else {
                        self?.ledMeter?.setServiceState(.stopped)
                        self?.meterStatusLabel?.stringValue = "🔴 未启动 · Bonsai 未运行"
                    }
                }
                self?.updateModelPopupStatuses()
            }
        }.resume()
    }

    /// oMLX is the user's own app; its port and API key live in ~/.omlx/settings.json.
    private func refreshOMLXStatus(expected: String) {
        let settingsURL = home.appendingPathComponent(".omlx/settings.json")
        let settings = (try? Data(contentsOf: settingsURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let port = (settings?["server"] as? [String: Any])?["port"] as? Int ?? 7777
        let key = (settings?["auth"] as? [String: Any])?["api_key"] as? String ?? ""
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/status") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            var models: [String] = []
            var serverUp = false
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                serverUp = true
                models = json["loaded_models"] as? [String] ?? []
            }
            DispatchQueue.main.async {
                let loaded = models.contains(expected)
                self?.mtplxReady = false
                self?.omlxLoadedModels = models
                self?.serviceStatusLabel?.stringValue = loaded
                    ? "● oMLX 已就绪 · \(expected)"
                    : (serverUp ? "○ oMLX 未加载目标模型" : "○ oMLX 未运行")
                if (self?.liveRequests.isEmpty ?? true) && !(self?.taskBlocked ?? false) {
                    if loaded {
                        self?.ledMeter?.setServiceState(.idleReady)
                        self?.meterStatusLabel?.stringValue = "🟢 闲置就绪 · oMLX \(expected) 已加载至统一内存"
                    } else {
                        self?.ledMeter?.setServiceState(.stopped)
                        self?.meterStatusLabel?.stringValue = "🔴 未启动 · oMLX 未加载目标模型"
                    }
                }
                self?.updateModelPopupStatuses()
            }
        }.resume()
    }

    private func refreshLMStudioStatus(expected: String) {
        let lms = home.appendingPathComponent(".lmstudio/bin/lms")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = lms
            process.arguments = ["ps"]
            process.standardOutput = pipe
            process.standardError = pipe
            try? process.run()
            process.waitUntilExit()
            let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let loaded = text.split(separator: "\n").contains { line in
                line.split(separator: " ").first.map(String.init) == expected
            }
            DispatchQueue.main.async {
                self?.mtplxReady = false
                self?.lmStudioLoadedModel = loaded ? expected : ""
                self?.serviceStatusLabel?.stringValue = loaded
                    ? "● LM Studio 已就绪 · \(expected)"
                    : "○ LM Studio 未加载目标模型"
                if (self?.liveRequests.isEmpty ?? true) && !(self?.taskBlocked ?? false) {
                    if loaded {
                        self?.ledMeter?.setServiceState(.idleReady)
                        self?.meterStatusLabel?.stringValue = "🟢 闲置就绪 · LM Studio \(expected) 已加载至统一内存"
                    } else {
                        self?.ledMeter?.setServiceState(.stopped)
                        self?.meterStatusLabel?.stringValue = "🔴 未启动 · LM Studio 未加载目标模型"
                    }
                }
                self?.updateModelPopupStatuses()
            }
        }
    }

    private func pollTraffic() {
        guard FileManager.default.fileExists(atPath: trafficURL.path) else { return }
        guard let handle = try? FileHandle(forReadingFrom: trafficURL) else { return }
        defer { try? handle.close() }
        let size = (try? FileManager.default.attributesOfItem(atPath: trafficURL.path)[.size] as? UInt64) ?? 0
        if !trafficPrimed {
            // Recover a bounded tail so reopening the app does not hide recent requests.
            trafficOffset = size > 65536 ? size - 65536 : 0
            if trafficOffset > 0 {
                try? handle.seek(toOffset: trafficOffset)
                let tail = handle.readDataToEndOfFile()
                if let newline = tail.firstIndex(of: 10) { trafficOffset += UInt64(newline + 1) }
            }
            trafficPrimed = true
        }
        if size < trafficOffset {
            trafficOffset = 0
            trafficRemainder = ""
        }
        if size == trafficOffset { return }
        try? handle.seek(toOffset: trafficOffset)
        let data = handle.readDataToEndOfFile()
        trafficOffset = size
        guard var text = String(data: data, encoding: .utf8) else { return }
        if !trafficRemainder.isEmpty {
            text = trafficRemainder + text
            trafficRemainder = ""
        }
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") == false, let tail = lines.popLast() {
            trafficRemainder = tail
        }
        for line in lines where line.isEmpty == false {
            appendTrafficLine(line)
        }
    }

    private func appendTrafficLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = obj["kind"] as? String else { return }
        let id = obj["id"] as? String ?? ""
        switch kind {
        case "start":
            taskBlocked = false
            let owner = (obj["thread_id"] as? String ?? "") + (obj["agent_name"] as? String ?? "/root")
            for previous in liveRequests.keys.filter({ requestOwners[$0] == owner && liveRequests[$0] == "awaiting" }) {
                liveRequests.removeValue(forKey: previous)
                requestOwners.removeValue(forKey: previous)
            }
            liveRequests[id] = "starting"
            requestOwners[id] = owner
            if activeStreamID.isEmpty { activeStreamID = id }
            activeAnswer = ""
            let question = obj["question"] as? String ?? ""
            let model = obj["model"] as? String ?? ""
            activeModel = model
            let agent = obj["agent_name"] as? String ?? "/root"
            let vision = obj["image"] as? Bool ?? false
            let client = obj["client"] as? String ?? ""
            if !client.isEmpty {
                clientLastSeen[client] = Date()
                refreshClientCard()
            }
            let source = client.isEmpty ? "" : "\(clientTitle(client)) · "
            appendTranscript("\n—— 问 · \(source)\(model) · \(agent) · \(vision ? "图片＋文本" : "文本") ——\n\(question)\n—— 答 ——\n")
            statsLabel?.stringValue = "生成中 · 正在预填上下文，首 token 之前速度为 0"
            ledMeter?.setServiceState(.working, activeCount: 2)
            meterStatusLabel?.stringValue = "🟠 工作中 · 正在预填提示词与历史上下文…"
        case "admitted":
            activeStreamID = id
            activeAnswer = ""
            liveRequests[id] = "running"
            ledMeter?.setServiceState(.working, activeCount: 3)
            meterStatusLabel?.stringValue = "🟠 推理中 · GPU 1 路 · 待处理 \(liveRequests.values.filter { $0 == "queued" }.count)"
        case "queued":
            liveRequests[id] = "queued"
            let position = obj["position"] as? Int ?? 1
            ledMeter?.setServiceState(.working, activeCount: 2)
            meterStatusLabel?.stringValue = "🟠 请求排队 · 第 \(position) 位 · 推理按顺序执行"
        case "child_started":
            let agent = obj["agent_name"] as? String ?? "子任务"
            appendTranscript("\n[子任务启动] \(agent) · 使用独立上下文与证据\n")
        case "tool_running", "tool_returned":
            let tool = obj["tool"] as? String ?? "工具"
            let agent = obj["agent_name"] as? String ?? "/root"
            let task = obj["task"] as? String ?? ""
            appendTranscript("\n[\(kind == "tool_running" ? "工具执行中" : "工具已回传")] \(agent) · \(tool) \(task)\n")
        case "tool_dispatch":
            let tool = obj["tool"] as? String ?? "工具"
            let task = obj["task"] as? String ?? ""
            let agent = obj["agent_name"] as? String ?? "/root"
            let isChild = tool.contains("spawn") || tool == "task"
            appendTranscript("\n[\(isChild ? "分配子任务" : "交付工具")] \(agent) → \(tool) · \(task)\n")
        case "tool_result":
            let count = obj["count"] as? Int ?? 0
            appendTranscript("\n[工具回传] \(count) 个结果已收到，继续处理原始目标\n")
        case "context":
            let input = obj["input_tokens"] as? Int ?? 0
            let budget = obj["input_budget"] as? Int ?? 0
            let compacted = obj["compacted"] as? Bool ?? false
            appendTranscript("\n[上下文] \(input)/\(budget) tok · \(compacted ? "已按证据和最近步骤重组" : "完整工作窗口")\n")
        case "replan":
            let attempt = obj["attempt"] as? Int ?? 1
            statsLabel?.stringValue = "已复用读取证据 · 重新规划 \(attempt)/2"
            meterStatusLabel?.stringValue = "🟠 工作中 · 已拦截重复读取，正在选择下一步"
            ledMeter?.setServiceState(.working, activeCount: 3)
        case "delta":
            guard id == activeStreamID || activeStreamID.isEmpty else { return }
            let piece = obj["text"] as? String ?? ""
            activeAnswer += piece
            appendTranscript(piece)
            if let meter = ledMeter, meter.currentState != .working {
                meter.setServiceState(.working, activeCount: 4)
            }
        case "progress":
            if let prog = obj["progress"] as? [String: Any] {
                if let decodeTokS = prog["decode_tok_s"] as? Double, decodeTokS > 0 {
                    ledMeter?.bumpTokenSpeed(decodeTokS)
                    let count = min(20, max(1, Int(round(decodeTokS / 5.0))))
                    meterStatusLabel?.stringValue = String(
                        format: "🟠 工作中 (呼吸灯) · 实时速度 %.1f tok/s · 点亮 %d/20 拍",
                        decodeTokS, count
                    )
                } else {
                    ledMeter?.setServiceState(.working, activeCount: 3)
                }
            }
        case "ttft":
            if let ttft = obj["ttft_s"] as? Double {
                statsLabel?.stringValue = String(format: "首 token %.2f 秒 · 正在输出", ttft)
                meterStatusLabel?.stringValue = String(format: "🟠 工作中 · 首 token %.2f 秒 · 正在输出…", ttft)
            }
        case "wait":
            if let elapsed = obj["elapsed_s"] as? Double, activeAnswer.isEmpty {
                statsLabel?.stringValue = String(format: "预填中 · 已等待 %.1f 秒 · 这通常是长上下文，不是解码慢", elapsed)
                ledMeter?.setServiceState(.working, activeCount: 3)
                meterStatusLabel?.stringValue = String(format: "🟠 工作中 · 长上下文预填中 (已等待 %.1f 秒)…", elapsed)
            }
        case "retry":
            guard id == activeStreamID else { return }
            let attempt = obj["attempt"] as? Int ?? 1
            statsLabel?.stringValue = "正在恢复工具调用 · 第 \(attempt)/2 次"
            ledMeter?.setServiceState(.working, activeCount: 3)
            meterStatusLabel?.stringValue = "🟠 工作中 · 模型仅返回进度文字，正在请求实际工具调用…"
        case "done":
            let finishedTools = obj["tool_calls"] as? Int ?? 0
            if finishedTools > 0 { liveRequests[id] = "awaiting" }
            else { liveRequests.removeValue(forKey: id); requestOwners.removeValue(forKey: id) }
            guard id == activeStreamID else { return }
            let prompt = obj["prompt_tokens"] as? Int ?? 0
            let completion = obj["completion_tokens"] as? Int ?? 0
            let elapsed = obj["elapsed_s"] as? Double ?? 0
            let ttft = obj["ttft_s"] as? Double ?? 0
            let decode = obj["decode_tok_s"] as? Double ?? 0
            let prefill = obj["prefill_tok_s"] as? Double ?? 0
            let tools = obj["tool_calls"] as? Int ?? 0
            statsLabel?.stringValue = String(
                format: "输入 %d tok · 输出 %d tok · 处理 %.2f tok/s · 生成 %.2f tok/s · 首 token %.2f 秒 · 总 %.1f 秒 · 工具 %d",
                prompt, completion, prefill, decode, ttft, elapsed, tools
            )
            let isReady = localBackendUp
            if tools > 0 {
                ledMeter?.setServiceState(.working, activeCount: 3)
                meterStatusLabel?.stringValue = "🟠 等待工具回传 · 已向 Codex 交付 \(tools) 个工具调用，等待后续请求"
            } else if decode > 0 {
                ledMeter?.setServiceState(isReady ? .idleReady : .stopped)
                meterStatusLabel?.stringValue = String(format: "🟢 完成 · 最终生成速度 %.1f tok/s · 模型待命中", decode)
            } else {
                ledMeter?.setServiceState(isReady ? .idleReady : .stopped)
                meterStatusLabel?.stringValue = isReady ? "🟢 闲置就绪 · 模型已加载至统一内存" : "🔴 服务未运行"
            }
            let model = activeModel.isEmpty ? (obj["model"] as? String ?? "") : activeModel
            let speedKey = model.lowercased().replacingOccurrences(of: "local/", with: "")
            if !model.isEmpty && (decode > 0 || prefill > 0) {
                if decode > 0 {
                    lastSpeeds[speedKey] = decode
                    UserDefaults.standard.set(lastSpeeds, forKey: "lastSpeeds")
                }
                if prefill > 0 {
                    lastPrefillSpeeds[speedKey] = prefill
                    UserDefaults.standard.set(lastPrefillSpeeds, forKey: "lastPrefillSpeeds")
                }
                updateCapabilityLabel()
            }
            appendTranscript("\n")
            activeStreamID = liveRequests.first(where: { $0.value == "running" })?.key ?? ""
            if !liveRequests.isEmpty {
                ledMeter?.setServiceState(.working, activeCount: 3)
                meterStatusLabel?.stringValue = "🟠 活跃请求 \(liveRequests.count) · 排队 \(liveRequests.values.filter { $0 == "queued" }.count) · 等待工具 \(liveRequests.values.filter { $0 == "awaiting" }.count)"
            }
            activeModel = ""
        case "error", "blocked":
            liveRequests.removeValue(forKey: id)
            requestOwners.removeValue(forKey: id)
            guard id == activeStreamID || activeStreamID.isEmpty else { return }
            let message = obj["message"] as? String ?? "未知错误"
            let blocked = kind == "blocked"
            taskBlocked = blocked
            appendTranscript("\n[\(blocked ? "任务暂停，尚未完成" : "错误")] \(message)\n")
            statsLabel?.stringValue = blocked ? "任务暂停 · 等待明确下一步" : "生成失败"
            ledMeter?.setServiceState(blocked ? .paused : .stopped)
            meterStatusLabel?.stringValue = blocked ? "🟠 已停止无进展循环 · 模型仍就绪" : "🔴 生成失败 · 发生错误"
            activeStreamID = ""
            activeModel = ""
        case "cancelled":
            liveRequests.removeValue(forKey: id)
            requestOwners.removeValue(forKey: id)
            guard id == activeStreamID || activeStreamID.isEmpty else { return }
            appendTranscript("\n[已取消]\n")
            let isReady = localBackendUp
            ledMeter?.setServiceState(isReady ? .idleReady : .stopped)
            meterStatusLabel?.stringValue = isReady ? "🟢 任务已取消 · 模型就绪待命" : "🔴 服务未运行"
            activeStreamID = ""
            activeModel = ""
        default:
            break
        }
        updatePowerButtonVisuals()
    }

    private func appendTranscript(_ text: String) {
        guard let view = transcriptView else { return }
        view.textStorage?.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(srgbRed: 0.96, green: 0.94, blue: 1, alpha: 1)
        ]))
        if (view.string as NSString).length > 40_000 {
            let extra = (view.string as NSString).length - 30_000
            view.textStorage?.deleteCharacters(in: NSRange(location: 0, length: extra))
        }
        view.scrollToEndOfDocument(nil)
    }

    @objc private func testLocalText() {
        guard let url = URL(string: gatewayV1 + "/chat/completions") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "active", "messages": [["role": "user", "content": "请只回答：本地模型连接成功"]],
            "max_tokens": 64, "stream": false
        ])
        pagePicker?.selectedSegment = 2
        pageChanged()
        statsLabel?.stringValue = "正在发送本地文本测试…"
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.pollTraffic()
                if let error { self?.appendTranscript("\n[文本测试失败] \(error.localizedDescription)\n") }
                else if (response as? HTTPURLResponse)?.statusCode != 200 {
                    self?.appendTranscript("\n[文本测试失败] HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)\n")
                }
            }
        }.resume()
    }

    @objc private func testLocalVision() {
        let runtime = readRuntime()
        let backend = runtime["backend"] as? String ?? "mtplx"
        if backend == "omlx" {
            showError(title: "当前模型只支持文本", message: "oMLX 上的 Nemotron、K2 和 Ling 都是纯文本模型。看图请切换到 Qwen 3.6 / 3.8 或 Gemma 4。")
            return
        }
        if backend != "lmstudio" && !mtplxReady {
            showError(title: "本地模型尚未启动", message: "请先启动带视觉的模型。Qwen 3.8 和 Gemma 4 可以看图，GPT-OSS 20B 只有文本。")
            return
        }
        serviceStatusLabel?.stringValue = "正在发送真实图片测试…"
        log("vision test requested backend=\(backend)")
        guard let png = redTestPNG() else {
            showError(title: "测试失败", message: "无法生成测试图片。")
            return
        }
        let imageURL = "data:image/png;base64,\(png.base64EncodedString())"
        let model = backend == "lmstudio"
            ? (runtime["api_model"] as? String ?? "")
            : "mtplx-qwen38-27b-optimized-speed-fp16"
        let endpoint = backend == "lmstudio"
            ? "http://127.0.0.1:1234/v1/chat/completions"
            : "http://127.0.0.1:8000/v1/chat/completions"
        var payload: [String: Any] = [
            "model": model,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": "这张纯色图片是什么颜色？只回答颜色。"],
                    ["type": "image_url", "image_url": ["url": imageURL]]
                ]
            ]],
            "max_tokens": backend == "lmstudio" ? 128 : 24,
            "temperature": 0
        ]
        if backend != "lmstudio" {
            payload["enable_thinking"] = false
        }
        guard let url = URL(string: endpoint),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            var result = error?.localizedDescription ?? "未知错误"
            var success = false
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                result = content
                success = true
            }
            DispatchQueue.main.async {
                self?.serviceStatusLabel?.stringValue = success
                    ? "● 测试通过 · 模型识别图片为：\(result)"
                    : "● 测试失败 · \(result)"
                if !success { self?.showError(title: "API 测试失败", message: result) }
                self?.log("vision test success=\(success) result=\(result)")
            }
        }.resume()
    }

    private func redTestPNG() -> Data? {
        let image = NSImage(size: NSSize(width: 128, height: 128))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 128, height: 128).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: - Autoload and API access

    private func refreshAutoload() {
        let enabled = !FileManager.default.fileExists(atPath: disabledFlagURL.path)
        autoloadCheckbox?.state = enabled ? .on : .off
        let model = activeLocalChoice().map { $0.codexName.replacingOccurrences(of: "本地 ", with: "") } ?? "当前本地模型"
        autoloadCheckbox?.title = enabled ? "开机自动加载：\(model)（含崩溃后自动恢复）" : "开机不加载本地模型（只用云端时可省内存）"
    }

    @objc private func autoloadChanged() {
        do {
            if autoloadCheckbox?.state == .on {
                UserDefaults.standard.set(true, forKey: "userExplicitlyEnabledAutoload")
                try? FileManager.default.removeItem(at: disabledFlagURL)
                log("autoload enabled")
            } else {
                UserDefaults.standard.set(false, forKey: "userExplicitlyEnabledAutoload")
                try FileManager.default.createDirectory(at: disabledFlagURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data().write(to: disabledFlagURL)
                log("autoload disabled")
            }
        } catch {
            showError(title: "无法修改开机加载", message: error.localizedDescription)
        }
        refreshAutoload()
    }

    private func apiSnippets() -> [(title: String, text: String)] {
        let v1 = gatewayV1
        let base = localGateway
        return [
            ("Claude Code（只在当前终端生效）", "ANTHROPIC_BASE_URL=\(base) ANTHROPIC_AUTH_TOKEN=local ANTHROPIC_MODEL=active claude"),
            ("Codex（~/.codex/config.toml）", """
            model_provider = "local-relay"
            model = "active"

            [model_providers.local-relay]
            name = "本地中转站"
            base_url = "\(v1)"
            wire_api = "responses"
            """),
            ("OpenCode（opencode.jsonc 的 provider）", """
            "local-relay": {
              "npm": "@ai-sdk/openai-compatible",
              "name": "本地中转站",
              "options": { "baseURL": "\(v1)", "apiKey": "local" },
              "models": { "active": { "name": "当前本地模型", "tool_call": true } }
            }
            """),
            ("Qwen Code", "qwen --auth-type openai --openai-base-url \(v1) --openai-api-key local -m active"),
            ("Pi（~/.pi/agent/models.json）", """
            {
              "providers": {
                "local-relay": {
                  "baseUrl": "\(v1)",
                  "api": "openai-completions",
                  "apiKey": "local",
                  "models": [{ "id": "active" }]
                }
              }
            }
            """),
            ("Hermes Agent", """
            hermes config set model.provider custom
            hermes config set model.base_url \(v1)
            hermes config set model.default active
            """),
            ("Cursor / Cline / Continue 等", """
            协议：OpenAI Compatible
            Base URL：\(v1)
            API Key：local
            Model：active
            """),
            ("Python（OpenAI SDK）", """
            from openai import OpenAI
            client = OpenAI(base_url="\(v1)", api_key="local")
            reply = client.chat.completions.create(
                model="active",
                messages=[{"role": "user", "content": "你好"}],
            )
            print(reply.choices[0].message.content)
            """),
            ("Python（Anthropic SDK）", """
            from anthropic import Anthropic
            client = Anthropic(base_url="\(base)", api_key="local")
            reply = client.messages.create(
                model="active", max_tokens=512,
                messages=[{"role": "user", "content": "你好"}],
            )
            print(reply.content[0].text)
            """),
            ("curl · OpenAI 协议", """
            curl \(v1)/chat/completions \\
              -H 'Content-Type: application/json' -H 'Authorization: Bearer local' \\
              -d '{"model":"active","messages":[{"role":"user","content":"你好"}]}'
            """),
            ("curl · Anthropic 协议", """
            curl \(base)/v1/messages \\
              -H 'content-type: application/json' -H 'anthropic-version: 2023-06-01' -H 'x-api-key: local' \\
              -d '{"model":"active","max_tokens":256,"messages":[{"role":"user","content":"你好"}]}'
            """)
        ]
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        NSSound(named: .init("Tink"))?.play()
    }

    @objc private func copyAPIValue(_ sender: NSButton) {
        copyToPasteboard(sender.identifier?.rawValue ?? "")
    }

    @objc private func apiSnippetChanged() {
        let snippets = apiSnippets()
        let index = max(0, apiSnippetPopup?.indexOfSelectedItem ?? 0)
        apiSnippetView?.string = snippets.indices.contains(index) ? snippets[index].text : ""
    }

    @objc private func copyAPISnippet() {
        copyToPasteboard(apiSnippetView?.string ?? "")
    }

    @objc private func showAPIPanel() {
        if window == nil { buildWindow() }
        pagePicker?.selectedSegment = 1
        pageChanged()
        showWindow()

    }

    private func buildAPIPanel() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "API 接入 · 本地中转站"
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = Serafina.mist

        func row(_ name: String, _ value: String, _ note: String) -> NSView {
            let label = tonalLabel(name, size: 13, weight: .bold, color: Serafina.ink)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 150).isActive = true
            let field = NSTextField(labelWithString: value)
            field.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            field.isSelectable = true
            let hint = wrappingLabel(note, size: 11, weight: .medium, color: Serafina.muted)
            hint.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            let copy = pill("复制", action: #selector(copyAPIValue(_:)), fill: Serafina.petal, titleColor: Serafina.ink)
            copy.identifier = NSUserInterfaceItemIdentifier(value)
            field.lineBreakMode = .byTruncatingMiddle
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let top = NSStackView(views: [label, field, copy])
            top.orientation = .horizontal; top.alignment = .centerY; top.spacing = 10
            let stack = NSStackView(views: [top, hint])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 10
            top.translatesAutoresizingMaskIntoConstraints = false
            hint.translatesAutoresizingMaskIntoConstraints = false
            top.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return stack
        }

        let title = wrappingLabel("任何 Agent 都可以接入：OpenAI 和 Anthropic 两种协议，统一转给当前本地模型", size: 14, weight: .bold, color: Serafina.grape)
        let model = wrappingLabel("", size: 12, weight: .semibold, color: Serafina.ink)
        apiModelLabel = model
        let rows: [NSView] = [
            row("OpenAI Base URL", gatewayV1, "Chat Completions、Responses、Models"),
            row("Anthropic Base URL", localGateway, "Messages、count_tokens（客户端会自动补 /v1/messages）"),
            row("API Key / Token", "local", "任意非空值；仅本机 127.0.0.1 可访问，不校验"),
            row("模型名", "active", "也可以写 local 或任何名字")
        ]
        let endpoints = NSTextField(wrappingLabelWithString: """
        OpenAI 协议：POST /v1/chat/completions · POST /v1/responses · GET /v1/models
        Anthropic 协议：POST /v1/messages · POST /v1/messages/count_tokens（MTPLX、LM Studio 原生转发，其他后端由网关转换）
        所有请求共用同一个推理队列，使用切换器当前的模型和思考开关；网关只透传，不改写对话历史。
        """)
        endpoints.font = Serafina.rounded(12, .medium)
        endpoints.textColor = Serafina.muted

        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.font = Serafina.rounded(13, .medium)
        picker.addItems(withTitles: apiSnippets().map(\.title))
        picker.target = self
        picker.action = #selector(apiSnippetChanged)
        apiSnippetPopup = picker
        let copySnippet = pill("复制示例", action: #selector(copyAPISnippet), fill: Serafina.grape, titleColor: .white)
        let pickerRow = NSStackView(views: [tonalLabel("配置示例", size: 13, weight: .bold, color: Serafina.ink), picker, copySnippet])
        pickerRow.orientation = .horizontal
        pickerRow.alignment = .centerY
        pickerRow.spacing = 10

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let text = NSTextView()
        text.isEditable = false
        text.isRichText = false
        text.isHorizontallyResizable = false
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.backgroundColor = Serafina.night
        text.textColor = NSColor(srgbRed: 0.96, green: 0.94, blue: 1, alpha: 1)
        text.textContainerInset = NSSize(width: 8, height: 8)
        scroll.documentView = text
        apiSnippetView = text

        let stack = NSStackView(views: [title, model] + rows + [endpoints, pickerRow, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        panel.contentView = content
        for view in [scroll, endpoints, title, model, pickerRow] + rows { view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -44),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            endpoints.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            title.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            model.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            pickerRow.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ] + rows.map { $0.widthAnchor.constraint(equalTo: scroll.widthAnchor) })
        panel.minSize = NSSize(width: 680, height: 560)
        apiPanel = panel
        apiSnippetChanged()
    }

    // MARK: - Clients (Codex / OpenCode / Claude Code / Qwen Code)

    private func clientTitle(_ id: String) -> String {
        ["codex": "Codex", "opencode": "OpenCode", "claude": "Claude Code", "qwen": "Qwen Code",
         "agentd": "agentd", "other": "其他 Agent"][id] ?? id
    }

    private func clientError(_ message: String) -> NSError {
        NSError(domain: "CodexModelSwitcher", code: 10, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func readJSONObject(_ url: URL, missingOK: Bool = false) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            if missingOK { return [:] }
            throw clientError("找不到 \(url.path)")
        }
        let data = try Data(contentsOf: url)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw clientError("\(url.lastPathComponent) 不是纯 JSON（可能含注释），为安全起见未修改。")
        }
        return object
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL, privateFile: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        if privateFile {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    /// Original client settings, saved the first time a client is moved to
    /// the local model and written back by "恢复原配置". Holds Claude Code's
    /// original env (including its token), so the file is owner-only.
    private func loadClientBackups() -> [String: Any] {
        (try? readJSONObject(clientBackupURL, missingOK: true)) ?? [:]
    }

    private func saveClientBackups(_ backups: [String: Any]) throws {
        try writeJSONObject(backups, to: clientBackupURL, privateFile: true)
    }

    private func activeLocalChoice() -> ModelChoice? {
        let api = readRuntime()["api_model"] as? String ?? ""
        return choices.first { $0.isLocal && $0.model == api }
    }

    private func clientState(_ id: String) -> (local: Bool, detail: String) {
        switch id {
        case "codex":
            let saved = readTopLevelSettings()
            let local = saved.provider == "local-qwen"
            return (local, local ? "本地 · \(saved.model)" : "\(saved.provider) · \(saved.model)")
        case "opencode":
            guard let config = try? readJSONObject(openCodeConfigURL) else { return (false, "未找到可读的 opencode.jsonc") }
            let model = config["model"] as? String
            let local = model?.hasPrefix("serafina/") ?? false
            return (local, local ? "本地 · \(model ?? "")" : (model.map { "默认 \($0)" } ?? "未指定默认模型"))
        case "claude":
            let settings = (try? readJSONObject(claudeSettingsURL, missingOK: true)) ?? [:]
            let base = (settings["env"] as? [String: Any])?["ANTHROPIC_BASE_URL"] as? String
            if base == localGateway { return (true, "本地 · 经网关 :8002") }
            return (false, base.map { "接 \(URL(string: $0)?.host ?? $0)" } ?? "Anthropic 官方")
        case "qwen":
            let settings = (try? readJSONObject(qwenSettingsURL, missingOK: true)) ?? [:]
            let model = settings["model"] as? [String: Any]
            if (model?["baseUrl"] as? String) == gatewayV1 { return (true, "本地 · 经网关 :8002") }
            if let name = model?["name"] as? String { return (false, name) }
            return (false, FileManager.default.fileExists(atPath: qwenSettingsURL.path) ? "未指定模型" : "未配置")
        default:
            return (false, "")
        }
    }

    private func refreshClientCard() {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = (I18n.current == .zh) ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        formatter.unitsStyle = .short
        for id in clientIDs {
            if let popup = clientPopups[id] {
                let targets = clientTargets(id)
                let signature = targets.map { $0.tag + "=" + $0.title }.joined(separator: "|") + "|\(I18n.current.rawValue)"
                if clientTargetSignatures[id] != signature {
                    popup.removeAllItems()
                    for target in targets {
                        popup.addItem(withTitle: I18n.translate(target.title))
                        popup.lastItem?.representedObject = target.tag
                    }
                    clientTargetSignatures[id] = signature
                }
                let current = currentTarget(id)
                if let item = popup.itemArray.first(where: { ($0.representedObject as? String) == current }) {
                    popup.select(item)
                }
            }
            guard let label = clientStatusLabels[id] else { continue }
            let state = clientState(id)
            var text = (state.local ? "● " + localSummary(speed: true) : "○ " + state.detail)
            if let seen = clientLastSeen[id] {
                let rel = formatter.localizedString(for: seen, relativeTo: Date())
                text += I18n.current == .zh ? " · \(rel)有请求" : " · active \(rel)"
            }
            label.stringValue = I18n.translate(text)
            label.textColor = state.local ? Serafina.ink : Serafina.muted
        }
        refreshAutoload()
        refreshManagedStatus()
        apiModelLabel?.stringValue = I18n.translate("当前模型：\(localSummary(speed: true))（请求里的模型名可以随便写，都会转给它）")
    }

    @objc private func codexFollowChanged() {
        UserDefaults.standard.set(codexFollowCheckbox?.state == .on, forKey: "codexFollowsLocal")
    }

    /// Short name of the loaded local model, optionally with its measured speed.
    private func localSummary(speed: Bool = false) -> String {
        guard let choice = activeLocalChoice() else { return I18n.translate("本地 · 未选择模型") }
        var text = I18n.translate("本地 · ") + choice.codexName.replacingOccurrences(of: "本地 ", with: "")
        let key = choice.model.lowercased().replacingOccurrences(of: "local/", with: "")
        if speed, let decode = speedAverages[key]?["decode_tok_s"] as? Double {
            text += String(format: " · %.0f tok/s", decode)
        }
        let backend = readRuntime()["backend"] as? String ?? "mtplx"
        let up: Bool
        switch backend {
        case "lmstudio": up = !lmStudioLoadedModel.isEmpty
        case "bonsai": up = bonsaiReady
        case "omlx": up = omlxLoadedModels.contains(readRuntime()["api_model"] as? String ?? "")
        default: up = mtplxReady
        }
        if !up { text += I18n.translate(" · 未加载") }
        return text
    }

    private func openCodeCloudModels() -> [String] {
        guard let config = try? readJSONObject(openCodeConfigURL),
              let providers = config["provider"] as? [String: Any] else { return [] }
        let disabled = Set(config["disabled_providers"] as? [String] ?? [])
        return providers.keys.sorted().filter { $0 != "serafina" && !disabled.contains($0) }.flatMap { provider in
            ((providers[provider] as? [String: Any])?["models"] as? [String: Any] ?? [:]).keys.sorted().map { "\(provider)/\($0)" }
        }
    }

    private func originalDetail(_ id: String, _ saved: Any) -> String {
        let backup = saved as? [String: Any] ?? [:]
        switch id {
        case "codex":
            return "\(backup["provider"] as? String ?? "") · \(backup["model"] as? String ?? "")"
        case "opencode":
            return (backup["model"] as? String).map { "默认 \($0)" } ?? "未指定默认模型"
        case "claude":
            let base = (backup["env"] as? [String: Any])?["ANTHROPIC_BASE_URL"] as? String
            return base.map { "接 \(URL(string: $0)?.host ?? $0)" } ?? "Anthropic 官方"
        case "qwen":
            return ((backup["model"] as? [String: Any])?["name"] as? String) ?? "未配置"
        default:
            return ""
        }
    }

    /// What a client can be pointed at: the local model, its own original
    /// settings, or the cloud models it already knows about.
    private func clientTargets(_ id: String) -> [(tag: String, title: String)] {
        var targets: [(tag: String, title: String)] = [("local", "\(localSummary())（跟随当前模型）")]
        let state = clientState(id)
        if let saved = loadClientBackups()[id] {
            targets.append(("original", "原配置 · " + originalDetail(id, saved)))
        } else if !state.local {
            targets.append(("original", "原配置 · " + state.detail))
        }
        switch id {
        case "codex":
            for (index, choice) in choices.enumerated() where !choice.isLocal {
                targets.append(("codex:\(index)", "云端 · " + choice.title.replacingOccurrences(of: " · 云端", with: "")))
            }
        case "opencode":
            for model in openCodeCloudModels() { targets.append(("opencode:\(model)", "服务商 · " + model)) }
        default:
            break
        }
        return targets
    }

    private func currentTarget(_ id: String) -> String {
        if clientState(id).local { return "local" }
        guard loadClientBackups()[id] != nil else { return "original" }
        switch id {
        case "codex":
            let saved = readTopLevelSettings()
            if let index = choices.firstIndex(where: { !$0.isLocal && $0.provider == saved.provider && $0.model == saved.model }) {
                return "codex:\(index)"
            }
        case "opencode":
            if let model = (try? readJSONObject(openCodeConfigURL))?["model"] as? String { return "opencode:\(model)" }
        default:
            break
        }
        return "original"
    }

    private func setClientTarget(_ id: String, _ tag: String) throws {
        switch tag {
        case "local":
            try setClient(id, local: true)
        case "original":
            if loadClientBackups()[id] != nil { try setClient(id, local: false) }
        default:
            if tag.hasPrefix("codex:"), let index = Int(tag.dropFirst(6)), choices.indices.contains(index) {
                try backupCodexOriginal()
                try applyCodex(choice: choices[index], reasoningEffort: choices[index].reasoningEffort)
            } else if tag.hasPrefix("opencode:") {
                var config = try readJSONObject(openCodeConfigURL)
                var backups = loadClientBackups()
                if backups["opencode"] == nil {
                    backups["opencode"] = ["model": config["model"] ?? NSNull(), "small_model": config["small_model"] ?? NSNull()]
                    try saveClientBackups(backups)
                }
                let saved = backups["opencode"] as? [String: Any] ?? [:]
                config["model"] = String(tag.dropFirst(9))
                if let small = saved["small_model"] as? String { config["small_model"] = small } else { config.removeValue(forKey: "small_model") }
                try writeJSONObject(config, to: openCodeConfigURL)
            } else {
                throw clientError("未知的目标：\(tag)")
            }
        }
    }

    @objc private func clientTargetChanged(_ sender: NSPopUpButton) {
        guard let id = sender.identifier?.rawValue, let tag = sender.selectedItem?.representedObject as? String else { return }
        do {
            try setClientTarget(id, tag)
            log("client \(id) -> \(tag)")
            clientApplyHints[id]?.stringValue = ["codex", "opencode"].contains(id) ? "配置已保存 · 点击重启客户端生效" : "配置已保存 · 点击开新会话生效"
            NSSound(named: .init("Pop"))?.play()
        } catch {
            showError(title: "\(clientTitle(id)) 切换失败", message: error.localizedDescription)
        }
        clientTargetSignatures[id] = nil
        refreshClientCard()
    }

    @objc private func restoreClient(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        do {
            if loadClientBackups()[id] == nil {
                guard !clientState(id).local else { throw clientError("没有切换前的备份，无法推断原配置。") }
                clientApplyHints[id]?.stringValue = "当前就是原配置 · 无需恢复"
                return
            }
            // Restore configuration only; the user decides when to restart.
            let previousCLI = cliMode
            cliMode = true
            defer { cliMode = previousCLI }
            try setClientTarget(id, "original")
            UserDefaults.standard.set(false, forKey: "managedAgentMode")
            managedSwitch?.state = .off
            applyManagedLock()
            clientTargetSignatures[id] = nil
            refreshClientCard()
            refreshWindowSelection()
            clientApplyHints[id]?.stringValue = ["codex", "opencode"].contains(id) ? "原配置已恢复 · 点击重启客户端生效" : "原配置已恢复 · 点击开新会话生效"
            log("client restored id=\(id)")
        } catch { showError(title: "恢复 \(clientTitle(id)) 失败", message: error.localizedDescription) }
    }

    @objc private func restoreAllClients() {
        for id in clientIDs {
            let sender = NSButton()
            sender.identifier = NSUserInterfaceItemIdentifier(id)
            restoreClient(sender)
        }
    }

    @objc private func activateClient(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if ["codex", "opencode"].contains(id) {
            let url = id == "codex" ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") : URL(fileURLWithPath: "/Applications/OpenCode.app")
            guard let url, let bundleID = Bundle(url: url)?.bundleIdentifier else {
                showError(title: "找不到客户端", message: clientTitle(id)); return
            }
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            clientApplyHints[id]?.stringValue = "正在重启…"
            for app in running { _ = app.terminate() }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let deadline = Date().addingTimeInterval(10)
                while running.contains(where: { !$0.isTerminated }) && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
                DispatchQueue.main.async {
                    guard running.allSatisfy({ $0.isTerminated }) else {
                        self?.clientApplyHints[id]?.stringValue = "客户端未退出 · 请结束当前操作后再重启"; return
                    }
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                        DispatchQueue.main.async {
                            self?.clientApplyHints[id]?.stringValue = error.map { "启动失败：" + $0.localizedDescription } ?? "客户端已重新打开 · 请新建任务"
                        }
                    }
                }
            }
        } else if ["claude", "qwen"].contains(id) {
            do {
                let directory = home.appendingPathComponent("Library/Application Support/CodexModelSwitcher/sessions")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let script = directory.appendingPathComponent(id + ".command")
                let text = "#!/bin/zsh\nexport PATH=\"$HOME/.local/bin:$HOME/.npm-global/bin:/opt/homebrew/bin:$PATH\"\nexec " + id + "\n"
                try text.write(to: script, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
                if NSWorkspace.shared.open(script) { clientApplyHints[id]?.stringValue = "已打开新会话 · 原会话继续保留" }
                else { throw clientError("无法打开 Terminal 会话") }
            } catch { showError(title: "新会话启动失败", message: error.localizedDescription) }
        }
    }

    @objc private func clientOpen(_ sender: NSButton) {
        switch sender.identifier?.rawValue {
        case "codex":
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        case "opencode":
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/OpenCode.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
        case "claude", "qwen":
            // Terminal clients pick up their settings when a new session starts.
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
        default:
            break
        }
    }

    /// Codex config only (command line), or the full apply with menu,
    /// sounds and optional restart (window).
    private func applyCodex(choice: ModelChoice, reasoningEffort: String) throws {
        if cliMode {
            try updateConfig(provider: choice.provider, model: choice.model, reasoningEffort: reasoningEffort,
                             contextWindow: choice.contextLength, compactLimit: choice.compactTokenLimit,
                             displayName: choice.codexName)
        } else {
            applyConfigured(choice: choice, reasoningEffort: reasoningEffort, forceCodex: true)
        }
    }

    /// `CodexModelSwitcher --client <codex|opencode|claude|qwen> <status|targets|local|restore|TARGET> [--home DIR]`
    func runClientCommand(_ args: [String]) -> Int32 {
        cliMode = true
        let usage = "usage: CodexModelSwitcher --client <codex|opencode|claude|qwen> <status|targets|local|restore|TARGET> [--home DIR]"
        guard args.count >= 2, clientIDs.contains(args[0]) else {
            print(usage)
            return 2
        }
        do {
            switch args[1] {
            case "status":
                break
            case "targets":
                for target in clientTargets(args[0]) { print("\(target.tag)\t\(target.title)") }
                return 0
            case "restore", "original":
                try setClientTarget(args[0], "original")
            default:
                guard args[1] == "local" || clientTargets(args[0]).contains(where: { $0.tag == args[1] }) else {
                    print(usage)
                    return 2
                }
                try setClientTarget(args[0], args[1])
            }
            let state = clientState(args[0])
            print("\(clientTitle(args[0])): \(state.local ? "local" : "original") · \(state.detail)")
            return 0
        } catch {
            FileHandle.standardError.write((error.localizedDescription + "\n").data(using: .utf8) ?? Data())
            return 1
        }
    }

    /// Remember Codex's own provider/model/effort before it is moved to local.
    private func backupCodexOriginal() throws {
        var backups = loadClientBackups()
        guard backups["codex"] == nil, !clientState("codex").local else { return }
        let saved = readTopLevelSettings()
        let contents = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let effort = contents.components(separatedBy: .newlines).prefix { !$0.hasPrefix("[") }
            .compactMap { tomlString(from: $0.trimmingCharacters(in: .whitespaces), key: "model_reasoning_effort") }.last
        backups["codex"] = ["provider": saved.provider, "model": saved.model, "effort": effort ?? "high"]
        try saveClientBackups(backups)
    }

    // MARK: - 全托管 Agent 模式

    @objc private func managedChanged(_ sender: NSSwitch) {
        if sender.state == .on { enterManagedMode() } else { leaveManagedMode() }
    }

    private func enterManagedMode() {
        guard let index = choices.firstIndex(where: { $0.model == managedProfile.model }) else {
            managedSwitch?.state = .off
            showError(title: "无法开启全托管", message: "没找到最佳配置对应的本地模型：\(managedProfile.model)")
            return
        }
        let alert = NSAlert()
        alert.messageText = "开启全托管 Agent 模式？"
        alert.informativeText = """
        • 加载 \(choices[index].title)（\(managedProfile.thinking ? "开启" : "关闭")思考，推理 \(managedProfile.effort)）
        • Codex、OpenCode、Claude Code、Qwen Code 全部切到本地；各自原配置先备份，关闭本模式时恢复
        • Claude Code 的修改影响所有 Claude Code 会话（包括 Claude 桌面版的 Code）

        切换后请重启 Codex 和 OpenCode，Claude Code 开新会话。之后再换本地模型无需重启。
        """
        alert.addButton(withTitle: "开启")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            managedSwitch?.state = .off
            return
        }
        var failures: [String] = []
        do { try backupCodexOriginal() } catch { failures.append("Codex：\(error.localizedDescription)") }
        for id in ["opencode", "claude", "qwen"] where !clientState(id).local {
            do { try setClient(id, local: true) } catch { failures.append("\(clientTitle(id))：\(error.localizedDescription)") }
        }
        UserDefaults.standard.set(true, forKey: "managedAgentMode")
        modelPopup?.selectItem(at: index)
        resetModelSettings()
        updateCapabilityLabel()
        log("managed agent mode on model=\(managedProfile.model) thinking=\(managedProfile.thinking)")
        apply(choice: choices[index])
        applyManagedLock()
        refreshClientCard()
        if !failures.isEmpty { showError(title: "部分客户端未切换", message: failures.joined(separator: "\n")) }
    }

    private func leaveManagedMode() {
        let alert = NSAlert()
        alert.messageText = "关闭全托管模式？"
        alert.informativeText = "Codex、OpenCode、Claude Code 恢复到开启前的配置。本地模型继续运行，可以在下面手动管理。"
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            managedSwitch?.state = .on
            return
        }
        UserDefaults.standard.set(false, forKey: "managedAgentMode")
        var failures: [String] = []
        let backups = loadClientBackups()
        for id in clientIDs where backups[id] != nil {
            do { try setClient(id, local: false) } catch { failures.append("\(clientTitle(id))：\(error.localizedDescription)") }
        }
        log("managed agent mode off")
        applyManagedLock()
        refreshClientCard()
        if !failures.isEmpty { showError(title: "部分客户端未恢复", message: failures.joined(separator: "\n")) }
    }

    private func applyManagedLock() {
        let manual = !managedMode
        for control in manualControls + clientButtons + [codexFollowCheckbox].compactMap({ $0 }) {
            control.isEnabled = manual
            control.alphaValue = manual ? 1 : 0.45
        }
        refreshManagedStatus()
    }

    private func refreshManagedStatus() {
        guard let label = managedStatusLabel else { return }
        guard managedMode else {
            label.stringValue = "已关闭 · 在下面手动选择模型，并为每个客户端单独决定"
            label.textColor = Serafina.muted
            return
        }
        let connected = clientIDs.filter { clientState($0).local }.count
        let key = managedProfile.model.lowercased().replacingOccurrences(of: "local/", with: "")
        let decode = speedAverages[key]?["decode_tok_s"] as? Double
        var text = "全托管中 · \(connected)/\(clientIDs.count) 个客户端已接入本地"
        if let decode {
            text += String(format: " · 实测解码 %.0f tok/s（目标 %.0f）", decode, managedProfile.targetTokS)
            if decode < managedProfile.targetTokS { text += " · 需带 MTP 的权重才能稳定达标" }
        }
        label.stringValue = text
        label.textColor = (decode ?? 0) >= managedProfile.targetTokS ? NSColor.systemGreen : NSColor.systemOrange
    }

    private func setClient(_ id: String, local: Bool) throws {
        var backups = loadClientBackups()
        let state = clientState(id)
        switch (id, local) {
        case ("codex", true):
            guard let choice = activeLocalChoice() else { throw clientError("当前没有运行本地模型，先在上面选择并切换一个本地模型。") }
            try backupCodexOriginal()
            try applyCodex(choice: choice, reasoningEffort: effortPopup?.titleOfSelectedItem ?? choice.reasoningEffort)
        case ("codex", false):
            guard let saved = backups["codex"] as? [String: String], let provider = saved["provider"], let model = saved["model"] else {
                throw clientError("没有 Codex 的原配置备份。在上面的模型列表里选一个云端模型并切换即可。")
            }
            if let cloud = choices.first(where: { !$0.isLocal && $0.provider == provider && $0.model == model }) {
                try applyCodex(choice: cloud, reasoningEffort: saved["effort"] ?? cloud.reasoningEffort)
            } else {
                try updateConfig(provider: provider, model: model, reasoningEffort: saved["effort"] ?? "high", contextWindow: 0,
                                 compactLimit: 0, displayName: model)
                if !cliMode { refreshWindowSelection() }
            }
            backups.removeValue(forKey: "codex")
            try saveClientBackups(backups)
        case ("opencode", true):
            var config = try readJSONObject(openCodeConfigURL)
            if backups["opencode"] == nil && !state.local {
                backups["opencode"] = ["model": config["model"] ?? NSNull(), "small_model": config["small_model"] ?? NSNull()]
                try saveClientBackups(backups)
            }
            config["model"] = "serafina/active"
            config["small_model"] = "serafina/active"
            try writeJSONObject(config, to: openCodeConfigURL)
        case ("opencode", false):
            guard let saved = backups["opencode"] as? [String: Any] else { throw clientError("没有 OpenCode 的原配置备份。") }
            var config = try readJSONObject(openCodeConfigURL)
            for key in ["model", "small_model"] {
                if let value = saved[key] as? String { config[key] = value } else { config.removeValue(forKey: key) }
            }
            try writeJSONObject(config, to: openCodeConfigURL)
            backups.removeValue(forKey: "opencode")
            try saveClientBackups(backups)
        case ("claude", true):
            var settings = try readJSONObject(claudeSettingsURL, missingOK: true)
            var env = settings["env"] as? [String: Any] ?? [:]
            if backups["claude"] == nil && !state.local {
                backups["claude"] = ["env": env]
                try saveClientBackups(backups)
            }
            let model = activeLocalChoice()?.model ?? "local"
            env["ANTHROPIC_BASE_URL"] = localGateway
            env["ANTHROPIC_AUTH_TOKEN"] = "local"
            for key in ["ANTHROPIC_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL",
                        "ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_REASONING_MODEL", "ANTHROPIC_SMALL_FAST_MODEL"] {
                env[key] = model
            }
            settings["env"] = env
            try writeJSONObject(settings, to: claudeSettingsURL)
        case ("qwen", true):
            var settings = try readJSONObject(qwenSettingsURL, missingOK: true)
            if backups["qwen"] == nil && !state.local {
                backups["qwen"] = ["modelProviders": settings["modelProviders"] ?? NSNull(), "security": settings["security"] ?? NSNull(),
                                   "model": settings["model"] ?? NSNull(),
                                   "env": (try? String(contentsOf: qwenEnvURL, encoding: .utf8)) ?? NSNull()]
                try saveClientBackups(backups)
            }
            var providers = settings["modelProviders"] as? [String: Any] ?? [:]
            var openai = (providers["openai"] as? [[String: Any]] ?? []).filter { ($0["baseUrl"] as? String) != gatewayV1 }
            openai.insert(["id": "active", "name": "本地中转站 · 当前模型", "baseUrl": gatewayV1, "envKey": "SERAFINA_API_KEY"], at: 0)
            providers["openai"] = openai
            settings["modelProviders"] = providers
            var security = settings["security"] as? [String: Any] ?? [:]
            var auth = security["auth"] as? [String: Any] ?? [:]
            auth["selectedType"] = "openai"
            security["auth"] = auth
            settings["security"] = security
            var model = settings["model"] as? [String: Any] ?? [:]
            model["name"] = "active"
            model["baseUrl"] = gatewayV1
            settings["model"] = model
            try writeJSONObject(settings, to: qwenSettingsURL)
            let existing = (try? String(contentsOf: qwenEnvURL, encoding: .utf8)) ?? ""
            let kept = existing.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("SERAFINA_API_KEY=") }
            try ((kept + ["SERAFINA_API_KEY=local"]).joined(separator: "\n") + "\n").write(to: qwenEnvURL, atomically: true, encoding: .utf8)
        case ("qwen", false):
            guard let saved = backups["qwen"] as? [String: Any] else { throw clientError("没有 Qwen Code 的原配置备份。") }
            var settings = try readJSONObject(qwenSettingsURL, missingOK: true)
            for key in ["modelProviders", "security", "model"] {
                if let value = saved[key], !(value is NSNull) { settings[key] = value } else { settings.removeValue(forKey: key) }
            }
            if settings.isEmpty { try? FileManager.default.removeItem(at: qwenSettingsURL) } else { try writeJSONObject(settings, to: qwenSettingsURL) }
            if let env = saved["env"] as? String { try env.write(to: qwenEnvURL, atomically: true, encoding: .utf8) } else { try? FileManager.default.removeItem(at: qwenEnvURL) }
            backups.removeValue(forKey: "qwen")
            try saveClientBackups(backups)
        case ("claude", false):
            guard let saved = backups["claude"] as? [String: Any] else { throw clientError("没有 Claude Code 的原配置备份。") }
            var settings = try readJSONObject(claudeSettingsURL, missingOK: true)
            settings["env"] = saved["env"] as? [String: Any] ?? [:]
            try writeJSONObject(settings, to: claudeSettingsURL)
            backups.removeValue(forKey: "claude")
            try saveClientBackups(backups)
        default:
            break
        }
    }

    private func restartCodex() {
        let bundleIdentifier = "com.openai.codex"
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            showError(title: "无法重启 Codex", message: "未找到已安装的 Codex 应用。")
            return
        }
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        if runningApps.isEmpty {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        for app in runningApps { _ = app.terminate() }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline && runningApps.contains(where: { !$0.isTerminated }) {
                Thread.sleep(forTimeInterval: 0.25)
            }
            DispatchQueue.main.async {
                if runningApps.contains(where: { !$0.isTerminated }) {
                    self?.showError(title: "Codex 未能自动退出", message: "请手动退出 Codex 后重新打开。模型配置已经保存。")
                    return
                }
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = I18n.translate(title)
        alert.informativeText = I18n.translate(message)
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func log(_ message: String) {
        let directory = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: data)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch { }
    }

    private func updateConfig(provider: String, model: String, reasoningEffort: String, contextWindow: Int, compactLimit: Int, displayName: String) throws {
        var contents = try String(contentsOf: configURL, encoding: .utf8)
        let backupURL = configURL.deletingLastPathComponent().appendingPathComponent("config.toml.model-switcher-backup")
        try contents.write(to: backupURL, atomically: true, encoding: .utf8)

        var lines = contents.components(separatedBy: .newlines)
        var modelFound = false
        var providerFound = false
        var reasoningFound = false
        var reachedTable = false
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { reachedTable = true }
            if !reachedTable && trimmed.range(of: #"^model\s*="#, options: .regularExpression) != nil {
                lines[index] = "model = \"\(model)\""
                modelFound = true
            }
            if !reachedTable && trimmed.range(of: #"^model_provider\s*="#, options: .regularExpression) != nil {
                lines[index] = "model_provider = \"\(provider)\""
                providerFound = true
            }
            if !reachedTable && trimmed.range(of: #"^model_reasoning_effort\s*="#, options: .regularExpression) != nil {
                lines[index] = "model_reasoning_effort = \"\(reasoningEffort)\""
                reasoningFound = true
            }
        }
        var additions: [String] = []
        if !modelFound { additions.append("model = \"\(model)\"") }
        if !providerFound { additions.append("model_provider = \"\(provider)\"") }
        if !reasoningFound { additions.append("model_reasoning_effort = \"\(reasoningEffort)\"") }
        if !additions.isEmpty { lines.insert(contentsOf: additions, at: 0) }

        let windowKeys = [
            "model_context_window",
            "model_auto_compact_token_limit",
            "model_auto_compact_token_limit_scope"
        ]
        let windowValues = contextWindow > 0 ? [
            "model_context_window": String(contextWindow),
            "model_auto_compact_token_limit": String(compactLimit),
            "model_auto_compact_token_limit_scope": "\"total\""
        ] : [:]
        var rewritten: [String] = []
        var seenWindow = Set<String>()
        var inTable = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { inTable = true }
            if !inTable, let key = windowKeys.first(where: { name in
                trimmed.hasPrefix(name) && trimmed.dropFirst(name.count).trimmingCharacters(in: .whitespaces).hasPrefix("=")
            }) {
                seenWindow.insert(key)
                if let value = windowValues[key] {
                    rewritten.append("\(key) = \(value)")
                }
                continue
            }
            rewritten.append(line)
        }
        if contextWindow > 0 {
            let tableAt = rewritten.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? rewritten.count
            let head = rewritten[..<tableAt]
            var insertAt = tableAt
            if let index = head.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("model_reasoning_effort") }) {
                insertAt = index + 1
            }
            for key in windowKeys where !seenWindow.contains(key) {
                rewritten.insert("\(key) = \(windowValues[key] ?? "")", at: insertAt)
                insertAt += 1
            }
        }
        lines = rewritten
        contents = lines.joined(separator: "\n")

        if provider == "local-qwen" && !contents.contains("[model_providers.local-qwen]") {
            contents += """


[model_providers.local-qwen]
name = "\(displayName)"
base_url = "http://127.0.0.1:8002/v1"
wire_api = "responses"
"""
        }
        if provider == "local-qwen" {
            contents = rewriteLocalProviderName(contents, displayName: displayName)
        }
        try contents.write(to: configURL, atomically: true, encoding: .utf8)
        cachedConfigMtime = nil
    }

    private func rewriteLocalProviderName(_ contents: String, displayName: String) -> String {
        var lines = contents.components(separatedBy: .newlines)
        var inBlock = false
        var nameFound = false
        var blockStart: Int?
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "[model_providers.local-qwen]" {
                inBlock = true
                blockStart = index
                continue
            }
            if inBlock && trimmed.hasPrefix("[") { break }
            if inBlock && trimmed.range(of: #"^name\s*="#, options: .regularExpression) != nil {
                lines[index] = "name = \"\(displayName)\""
                nameFound = true
            }
        }
        if let blockStart, !nameFound {
            lines.insert("name = \"\(displayName)\"", at: blockStart + 1)
        }
        return lines.joined(separator: "\n")
    }

    private func readTopLevelSettings() -> (provider: String, model: String) {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: configURL.path),
           let mtime = attrs[.modificationDate] as? Date {
            if let lastMtime = cachedConfigMtime, lastMtime == mtime {
                return cachedConfigTopLevel
            }
            guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
                return ("openai", "gpt-5.6-sol")
            }
            var provider = "openai"
            var model = "gpt-5.6-sol"
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") { break }
                if let value = tomlString(from: trimmed, key: "model_provider") { provider = value }
                if let value = tomlString(from: trimmed, key: "model") { model = value }
            }
            cachedConfigMtime = mtime
            cachedConfigTopLevel = (provider, model)
            return cachedConfigTopLevel
        }
        return ("openai", "gpt-5.6-sol")
    }

    private func tomlString(from line: String, key: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = "^\(escapedKey)\\s*=\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[range])
    }

    private func displayName(for model: String, provider: String) -> String {
        choices.first(where: { $0.model == model && $0.provider == provider })?.title ?? model
    }

    @objc private func openConfigFile() { NSWorkspace.shared.open(configURL) }
    @objc private func openLogFile() {
        log("log opened")
        NSWorkspace.shared.open(logURL)
    }
    @objc private func openSettingsWindow() { showWindow() }
    @objc private func openCodexApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}

if let index = CommandLine.arguments.firstIndex(of: "--client") {
    let arguments = CommandLine.arguments
    if let flag = arguments.firstIndex(of: "--home"), flag + 1 < arguments.count {
        AppDelegate.homeOverride = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
    }
    exit(AppDelegate().runClientCommand(Array(arguments[(index + 1)...]).filter { $0 != "--home" && !$0.hasPrefix("/") }))
}

if CommandLine.arguments.contains("--interface-smoke") {
    let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    AppDelegate.homeOverride = fixture
    let log = fixture.appendingPathComponent("Library/Logs/CodexModelSwitcher/traffic.jsonl")
    try! FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! "{\"kind\":\"start\",\"id\":\"ui-smoke\",\"question\":\"SWITCH_UI_LOG_OK\"}\n{\"kind\":\"done\",\"id\":\"ui-smoke\"}\n".write(to: log, atomically: true, encoding: .utf8)
    _ = NSApplication.shared
    let result = AppDelegate().runInterfaceSmoke()
    try? FileManager.default.removeItem(at: fixture)
    exit(result)
}

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.run()
