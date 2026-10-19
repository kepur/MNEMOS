# [AOCI 仓库架构蓝图] CodexModelSwitcher
- 规模概览：约 36,820 行代码 · 314 个文件 · 核心语言: 无后缀: 92个, .py: 79个, .plist: 49个, .icns: 47个, .json: 23个

## 1. 关键入口与调度主控 (Entry Points)
- 🚀 `build-app.sh`
- 🚀 `main.swift`
- 🚀 `main.swift.bak`
- 🚀 `main.swift.v3.bak`
- 🚀 `backups/main-pre-client-buttons-1791554549.swift`
- 🚀 `backups/main-pre-cyberstrike-1791550318.swift`
- 🚀 `backups/main-pre-layout-1791554765.swift`
- 🚀 `backups/main-pre-tabs-1791552042.swift`

## 2. 顶层模块结构 (Module Structure)
  📁 serafina_runtime/
  📁 backups/
    📁 backups/Codex Model Switcher-3.0-20261009-130119.app/
    📁 backups/Codex Model Switcher-3.6-20261012-132630.app/
    📁 backups/Codex Model Switcher-3.6-20261012-220918.app/
    📁 backups/Codex Model Switcher-3.1-20261009-162338.app/
    📁 backups/Codex Model Switcher-3.3-20261011-093221.app/
    📁 backups/Codex Model Switcher-3.6-20261013-151855.app/
    📁 backups/Codex Model Switcher-3.0-20261009-143046.app/
    📁 backups/Codex Model Switcher-3.6-20261012-141234.app/
    📁 backups/Codex Model Switcher-3.5-20261011-212343.app/
    📁 backups/Codex Model Switcher-3.6-20261013-120103.app/
    📁 backups/Codex Model Switcher-3.6-20261012-131117.app/
    📁 backups/Codex Model Switcher-3.2-20261011-092514.app/
    📁 backups/Codex Model Switcher-3.0-20261009-143143.app/
    📁 backups/Codex Model Switcher-3.1-20261009-170239.app/

## 3. 核心实体与服务契约 (Core Symbols)
- `Identity` (gateway_core.py:64)
- `Blocked` (gateway_core.py:155)
- `Cancelled` (gateway_core.py:156)
- `SerialQueue` (gateway_core.py:177)
- `Store` (gateway_core.py:227)
- `Gateway` (gateway_core.py:262)
- `SerafinaBackground` (main.swift:33)
- `TonalCard` (main.swift:44)
- `FrostCard` (main.swift:60)
- `FlippedView` (main.swift:118)
- `LEDMeterView` (main.swift:129)
- `SerafinaButton` (main.swift:255)
- `HardwareMetricBar` (main.swift:424)
- `HardwareBentoCard` (main.swift:568)
- `TrafficWaveformView` (main.swift:635)

## 4. 架构设计不变量与安全守则 (Architectural Invariants)
- ⚠️ 本地原生高吞吐执行，杜绝冗余全文件 dump 刷屏；
- ⚠️ 跨文件查找优先调用 CodeGraph (code_outline / code_callers)，实现精准外科手术式查询；
- ⚠️ 核心配置、私钥凭据与模型权重路径受到 Serafina 网络沙箱与 Watchlist 保护；