#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DSA_ENV="$ROOT_DIR/config/dsa.env"
BRIDGE_ENV="$ROOT_DIR/config/acp-bridge.env"

HOST="127.0.0.1"
PORT="19090"
UPSTREAM_BASE="https://ark.cn-beijing.volces.com"
TIMEOUT="120"
API_KEY=""

for env_file in "$DSA_ENV" "$BRIDGE_ENV"; do
  if [ -f "$env_file" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi
done

HOST="${VOLCENGINE_PROXY_HOST:-$HOST}"
PORT="${VOLCENGINE_PROXY_PORT:-$PORT}"
UPSTREAM_BASE="${VOLCENGINE_PROXY_UPSTREAM_BASE:-$UPSTREAM_BASE}"
TIMEOUT="${VOLCENGINE_PROXY_TIMEOUT_SECONDS:-$TIMEOUT}"
API_KEY="${VOLCENGINE_PROXY_API_KEY:-${VOLCENGINE_CODING_API_KEY:-${OPENAI_API_KEY:-}}}"

if [ -x "$ROOT_DIR/external/daily_stock_analysis/.venv/bin/python" ]; then
  PYTHON_BIN="$ROOT_DIR/external/daily_stock_analysis/.venv/bin/python"
else
  PYTHON_BIN="python3"
fi

export VOLCENGINE_PROXY_HOST="$HOST"
export VOLCENGINE_PROXY_PORT="$PORT"
export VOLCENGINE_PROXY_UPSTREAM_BASE="$UPSTREAM_BASE"
export VOLCENGINE_PROXY_TIMEOUT_SECONDS="$TIMEOUT"
export VOLCENGINE_PROXY_API_KEY="$API_KEY"

exec "$PYTHON_BIN" -m volcengine_compat_proxy.app "$@"
