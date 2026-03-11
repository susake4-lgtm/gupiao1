#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/dsa.env"

HOST="127.0.0.1"
PORT="8000"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  HOST="${DSA_API_HOST:-$HOST}"
  PORT="${DSA_API_PORT:-$PORT}"
fi

exec "$ROOT_DIR/scripts/run-dsa-once.sh" --serve-only --host "$HOST" --port "$PORT" "$@"
