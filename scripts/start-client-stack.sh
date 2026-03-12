#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/logs/client-stack"
PID_DIR="$LOG_DIR/pids"

mkdir -p "$LOG_DIR" "$PID_DIR"

start_service() {
  local name="$1"
  shift
  local log_file="$LOG_DIR/${name}.log"
  local pid_file="$PID_DIR/${name}.pid"

  if [[ -f "$pid_file" ]]; then
    local old_pid
    old_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      echo "[client-stack] $name already running (pid=$old_pid)"
      return 0
    fi
  fi

  nohup "$@" >"$log_file" 2>&1 &
  local pid=$!
  echo "$pid" >"$pid_file"
  echo "[client-stack] started $name (pid=$pid, log=$log_file)"
}

usage() {
  cat <<'EOF'
Usage:
  scripts/start-client-stack.sh [--with-bridge] [--with-dsa-api]

Default services:
  - Volcengine compatibility proxy
  - OpenClaw gateway

Optional:
  --with-bridge   Start ACP Bridge for modify/create
  --with-dsa-api  Start DSA API (8000)
EOF
}

WITH_BRIDGE=false
WITH_DSA_API=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-bridge)
      WITH_BRIDGE=true
      shift
      ;;
    --with-dsa-api)
      WITH_DSA_API=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[client-stack] unknown arg: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

start_service "volcengine-compat-proxy" bash "$ROOT_DIR/scripts/start-volcengine-compat-proxy.sh"
start_service "openclaw" bash "$ROOT_DIR/scripts/start-openclaw.sh"

if [[ "$WITH_BRIDGE" == true ]]; then
  start_service "acp-bridge" bash "$ROOT_DIR/scripts/start-acp-bridge.sh"
fi

if [[ "$WITH_DSA_API" == true ]]; then
  start_service "dsa-api" bash "$ROOT_DIR/scripts/run-dsa-api.sh"
fi
