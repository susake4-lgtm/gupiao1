#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EXTERNAL_DIR="$ROOT_DIR/external/daily_stock_analysis"
ENV_FILE="$ROOT_DIR/config/dsa.env"
STOCK_FILE="$ROOT_DIR/config/stocks.md"

if [ ! -d "$EXTERNAL_DIR" ]; then
  echo "[run-once] missing $EXTERNAL_DIR"
  echo "[run-once] run ./scripts/bootstrap-dsa.sh first"
  exit 1
fi

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

if [ -f "$STOCK_FILE" ]; then
  STOCK_LIST_FROM_FILE="$(awk '/^[[:space:]]*($|#)/ {next} {print $1}' "$STOCK_FILE" | paste -sd, -)"
  if [ -n "$STOCK_LIST_FROM_FILE" ]; then
    export STOCK_LIST="$STOCK_LIST_FROM_FILE"
  fi
fi

if [ -x "$EXTERNAL_DIR/.venv/bin/python" ]; then
  PYTHON_BIN="$EXTERNAL_DIR/.venv/bin/python"
else
  PYTHON_BIN="python3"
fi

ADD_NO_NOTIFY=true
IS_SCHEDULE=false
for arg in "$@"; do
  case "$arg" in
    --schedule)
      IS_SCHEDULE=true
      ADD_NO_NOTIFY=false
      ;;
    --single-notify|--serve|--serve-only|--webui|--webui-only|--market-review)
      ADD_NO_NOTIFY=false
      ;;
    --no-notify)
      ADD_NO_NOTIFY=false
      ;;
  esac
done

# run-dsa-once should stay single-run even if dsa.env has SCHEDULE_ENABLED=true
if [ "$IS_SCHEDULE" = false ]; then
  export SCHEDULE_ENABLED=false
fi

if [ "$ADD_NO_NOTIFY" = true ]; then
  set -- "$@" "--no-notify"
fi

cd "$EXTERNAL_DIR"
exec "$PYTHON_BIN" main.py "$@"
