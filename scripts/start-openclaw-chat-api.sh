#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/dsa.env"

HOST="127.0.0.1"
PORT="18889"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  HOST="${OPENCLAW_CHAT_API_HOST:-$HOST}"
  PORT="${OPENCLAW_CHAT_API_PORT:-$PORT}"
fi

if [ -x "$ROOT_DIR/external/daily_stock_analysis/.venv/bin/python" ]; then
  PYTHON_BIN="$ROOT_DIR/external/daily_stock_analysis/.venv/bin/python"
else
  PYTHON_BIN="python3"
fi

export OPENCLAW_CHAT_API_HOST="${OPENCLAW_CHAT_API_HOST:-$HOST}"
export OPENCLAW_CHAT_API_PORT="${OPENCLAW_CHAT_API_PORT:-$PORT}"

exec "$PYTHON_BIN" -m openclaw_chat_api.app "$@"
