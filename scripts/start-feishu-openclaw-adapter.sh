#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/dsa.env"

HOST="127.0.0.1"
PORT="18989"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  HOST="${FEISHU_OPENCLAW_HOST:-$HOST}"
  PORT="${FEISHU_OPENCLAW_PORT:-$PORT}"
fi

if [ -x "$ROOT_DIR/external/daily_stock_analysis/.venv/bin/python" ]; then
  PYTHON_BIN="$ROOT_DIR/external/daily_stock_analysis/.venv/bin/python"
else
  PYTHON_BIN="python3"
fi

export FEISHU_OPENCLAW_HOST="${FEISHU_OPENCLAW_HOST:-$HOST}"
export FEISHU_OPENCLAW_PORT="${FEISHU_OPENCLAW_PORT:-$PORT}"

exec "$PYTHON_BIN" -m feishu_openclaw_adapter.app "$@"
