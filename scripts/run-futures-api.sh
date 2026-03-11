#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/futures.env"

HOST="127.0.0.1"
PORT="8010"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  HOST="${FUTURES_API_HOST:-$HOST}"
  PORT="${FUTURES_API_PORT:-$PORT}"
fi

if [ -x "$ROOT_DIR/external/daily_stock_analysis/.venv/bin/python" ]; then
  PYTHON_BIN="$ROOT_DIR/external/daily_stock_analysis/.venv/bin/python"
else
  PYTHON_BIN="python3"
fi

exec "$PYTHON_BIN" -m uvicorn futures_api.app:app --app-dir "$ROOT_DIR" --host "$HOST" --port "$PORT" "$@"
