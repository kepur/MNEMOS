#!/bin/zsh
set -u

echo "========================================="
echo "   正在停止 MNEMOS 服务与控制面板...      "
echo "========================================="

# 1. 关闭桌面 App
pkill -TERM -f "MNEMOS.app/Contents/MacOS/MNEMOS" 2>/dev/null || true
pkill -TERM -f "Codex Model Switcher.app" 2>/dev/null || true

# 2. 关闭 8002 网关
for pid in $(lsof -nP -tiTCP:8002 -sTCP:LISTEN 2>/dev/null); do
    command=$(ps -p "$pid" -o command= 2>/dev/null || true)
    if [[ "$command" == *"mtplx-responses-proxy.py"* ]]; then
        kill -TERM "$pid" 2>/dev/null || true
        echo "✓ 已停止 8002 网关进程 (PID $pid)"
    fi
done

echo "✓ MNEMOS 控制面板与网关监控已停止。"
