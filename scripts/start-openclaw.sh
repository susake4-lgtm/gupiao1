#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/dsa.env"
BIND_MODE="loopback"
PORT="18789"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  BIND_MODE="${OPENCLAW_BIND:-$BIND_MODE}"
  PORT="${OPENCLAW_PORT:-$PORT}"
fi

if ! command -v openclaw >/dev/null 2>&1; then
  echo "[openclaw] openclaw command not found"
  echo "[openclaw] install it first, then rerun this script"
  exit 1
fi

exec openclaw gateway --bind "$BIND_MODE" --port "$PORT" --verbose "$@"
