#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/trendradar.env"
DEFAULT_TRENDRADAR_DIR="$ROOT_DIR/../TrendRadar"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

TRENDRADAR_DIR="${TRENDRADAR_DIR:-$DEFAULT_TRENDRADAR_DIR}"

if [ ! -d "$TRENDRADAR_DIR" ]; then
  echo "[trendradar-once] missing TrendRadar directory: $TRENDRADAR_DIR"
  echo "[trendradar-once] set TRENDRADAR_DIR in config/trendradar.env"
  exit 1
fi

if [ -z "${FEISHU_WEBHOOK_URL:-}" ]; then
  echo "[trendradar-once] FEISHU_WEBHOOK_URL is empty"
  echo "[trendradar-once] fill config/trendradar.env first"
  exit 1
fi

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

if [ -z "${CONFIG_PATH:-}" ]; then
  CONFIG_PATH="$TRENDRADAR_DIR/config/config.yaml"
fi
export CONFIG_PATH

if [ ! -f "$CONFIG_PATH" ]; then
  echo "[trendradar-once] missing config file: $CONFIG_PATH"
  exit 1
fi

# run-trendradar-once should force single-run behavior
export SCHEDULE_ENABLED=false

# keep one-shot flow lightweight unless user explicitly enables AI analysis
if [ -z "${AI_ANALYSIS_ENABLED:-}" ]; then
  export AI_ANALYSIS_ENABLED=false
fi

# default to Feishu-only experience: do not auto-open local HTML in browser
if [ -z "${TRENDRADAR_NO_BROWSER:-}" ]; then
  export TRENDRADAR_NO_BROWSER=true
fi

if [ -x "$TRENDRADAR_DIR/.venv/bin/python" ]; then
  RUNNER=("$TRENDRADAR_DIR/.venv/bin/python" -m trendradar)
elif command -v uv >/dev/null 2>&1; then
  RUNNER=(uv run python -m trendradar)
else
  RUNNER=(python3 -m trendradar)
fi

cd "$TRENDRADAR_DIR"
exec "${RUNNER[@]}" "$@"
