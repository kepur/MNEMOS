#!/bin/zsh
# Hot-swap the :8002 gateway without reloading the model.
#
# start-qwen38.sh restarts the proxy within ~2s when it exits, but
# mtplx-health-watch.sh (every 30s) treats a missing bridge as "service down"
# and reloads everything. Pause the watcher for the swap.
set -eu

src="${0:A:h}"
state_dir="$HOME/.local/state/mtplx-qwen38"
flag="$state_dir/disabled"

if [[ -f "$flag" ]]; then
  echo "service is stopped (disabled flag present); copying files only"
  cp "$src/gateway_core.py" "$src/mtplx-responses-proxy.py" "$src/omlx_ctl.py" "$HOME/bin/"
  cp -R "$src/serafina_runtime" "$HOME/bin/"
  exit 0
fi

(cd "$src" && python3 -m unittest -q test_gateway test_bridge test_runtime) || { echo "tests failed; not deploying" >&2; exit 1; }

touch "$flag"
trap 'rm -f "$flag"' EXIT
cp "$src/gateway_core.py" "$src/mtplx-responses-proxy.py" "$src/omlx_ctl.py" "$HOME/bin/"
cp -R "$src/serafina_runtime" "$HOME/bin/"

old=$(lsof -nP -tiTCP:8002 -sTCP:LISTEN 2>/dev/null || true)
if [[ -n "$old" ]] && ps -p "$old" -o command= | grep -q 'mtplx-responses-proxy.py'; then
  kill -TERM "$old"
fi
for _ in {1..40}; do
  info="$(curl -fsS --max-time 2 http://127.0.0.1:8002/v1/bridge-info 2>/dev/null || true)"
  new=$(lsof -nP -tiTCP:8002 -sTCP:LISTEN 2>/dev/null || true)
  if [[ -n "$info" && "$new" != "$old" ]]; then
    print -r -- "$info" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("gateway", d["revision"], "pid", sys.argv[1])' "$new"
    exit 0
  fi
  sleep 0.5
done
echo "gateway did not come back within 20s" >&2
exit 1
