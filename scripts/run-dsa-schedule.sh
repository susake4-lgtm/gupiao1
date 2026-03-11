#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/dsa.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "[schedule] missing $ENV_FILE"
  echo "[schedule] create it from config/dsa.env.example first"
  exit 1
fi

exec "$ROOT_DIR/scripts/run-dsa-once.sh" --schedule "$@"
