#!/bin/zsh
set -u

MNEMOS_DIR="/Users/mac/Code_Start/MNEMOS"
PYTHON_BIN="/Users/mac/.venvs/mtplx/bin/python"
[[ ! -x "$PYTHON_BIN" ]] && PYTHON_BIN="$(which python3)"

LOG_DIR="$HOME/Library/Logs/CodexModelSwitcher"
mkdir -p "$LOG_DIR"

echo "========================================="
echo "   MNEMOS 智能中枢与网络安全哨兵启动中...   "
echo "========================================="

# 1. 检查或启动 8002 网关与网络哨兵代理
is_running=false
if curl -fsS --max-time 1.5 http://127.0.0.1:8002/v1/bridge-info >/dev/null 2>&1; then
    is_running=true
fi

if [[ "$is_running" == "true" ]]; then
    echo "✓ 网关核心与网络监控 (127.0.0.1:8002) 正在运行中"
else
    echo "▶ 正在启动 8002 网关与网络流量监控哨兵..."
    for pid in $(lsof -nP -tiTCP:8002 -sTCP:LISTEN 2>/dev/null); do
        kill -TERM "$pid" 2>/dev/null || true
    done
    sleep 0.5
    nohup "$PYTHON_BIN" "$MNEMOS_DIR/mtplx-responses-proxy.py" --host 127.0.0.1 --port 8002 > "$LOG_DIR/gateway.log" 2>&1 &
    
    for i in {1..20}; do
        if curl -fsS --max-time 1 http://127.0.0.1:8002/v1/bridge-info >/dev/null 2>&1; then
            echo "✓ 8002 网关与网络哨兵启动成功！"
            is_running=true
            break
        fi
        sleep 0.5
    done
fi

# 2. 启动桌面 App
APP_PATH="$HOME/Desktop/MNEMOS.app"
if [[ -d "$APP_PATH" ]]; then
    echo "▶ 正在打开 MNEMOS 控制面板..."
    open "$APP_PATH"
else
    echo "⚠ 未找到 $APP_PATH，请先编译安装！"
fi

echo "========================================="
echo "   MNEMOS 就绪 (可在状态栏或面板中查看)   "
echo "========================================="
