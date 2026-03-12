#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/acp-bridge.env"
BRIDGE_DIR="$ROOT_DIR/external/acp-bridge"
PYTHON_BIN="$BRIDGE_DIR/.venv/bin/python"
DEFAULT_CLAUDE_WRAPPER="$ROOT_DIR/scripts/claude-print-wrapper.sh"
DEFAULT_CLAUDE_COMMAND="$(command -v claude || true)"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

: "${ACP_BRIDGE_HOST:=127.0.0.1}"
: "${ACP_BRIDGE_PORT:=8001}"
: "${ACP_BRIDGE_ALLOWED_IPS:=127.0.0.1}"
: "${ACP_BRIDGE_TOKEN:=local-openclaw-only-token}"
: "${ACP_BRIDGE_SESSION_TTL_HOURS:=24}"
: "${ACP_BRIDGE_SHUTDOWN_TIMEOUT:=30}"
: "${ACP_BRIDGE_MAX_PROCESSES:=4}"
: "${ACP_BRIDGE_MAX_PER_AGENT:=2}"
: "${ACP_BRIDGE_WORKDIR:=$ROOT_DIR}"
: "${ACP_BRIDGE_AGENT:=claude}"
: "${ACP_BRIDGE_AGENT_MODE:=pty}"
: "${CLAUDE_CODE_COMMAND:=${DEFAULT_CLAUDE_WRAPPER}}"
: "${CLAUDE_CODE_REAL_COMMAND:=${DEFAULT_CLAUDE_COMMAND:-claude}}"
: "${CLAUDE_CODE_ARGS:=--permission-mode acceptEdits}"
: "${ACP_BRIDGE_RUNTIME_CONFIG:=/tmp/gupiao1-acp-bridge.config.yaml}"

if [ ! -d "$BRIDGE_DIR" ]; then
  echo "[acp-bridge] bridge directory not found: $BRIDGE_DIR"
  exit 1
fi

if [ ! -x "$PYTHON_BIN" ]; then
  echo "[acp-bridge] python venv not found: $PYTHON_BIN"
  echo "[acp-bridge] install external/acp-bridge first"
  exit 1
fi

if [ "$CLAUDE_CODE_COMMAND" = "$DEFAULT_CLAUDE_WRAPPER" ]; then
  if [ ! -x "$CLAUDE_CODE_COMMAND" ]; then
    echo "[acp-bridge] Claude wrapper not executable: $CLAUDE_CODE_COMMAND"
    exit 1
  fi
elif ! command -v "$CLAUDE_CODE_COMMAND" >/dev/null 2>&1; then
  echo "[acp-bridge] Claude command not found: $CLAUDE_CODE_COMMAND"
  exit 1
fi

if ! command -v "$CLAUDE_CODE_REAL_COMMAND" >/dev/null 2>&1; then
  echo "[acp-bridge] Real Claude command not found: $CLAUDE_CODE_REAL_COMMAND"
  exit 1
fi

if [ "$ACP_BRIDGE_AGENT_MODE" != "pty" ]; then
  echo "[acp-bridge] Step 1 only supports ACP_BRIDGE_AGENT_MODE=pty"
  exit 1
fi

IFS=',' read -r -a ALLOWED_IPS <<< "$ACP_BRIDGE_ALLOWED_IPS"
read -r -a CLAUDE_ARGS <<< "$CLAUDE_CODE_ARGS"

HAS_PRINT_FLAG=false
for arg in "${CLAUDE_ARGS[@]}"; do
  if [ "$arg" = "-p" ] || [ "$arg" = "--print" ]; then
    HAS_PRINT_FLAG=true
    break
  fi
done

if [ "$HAS_PRINT_FLAG" = false ]; then
  CLAUDE_ARGS=("-p" "${CLAUDE_ARGS[@]}")
fi

mkdir -p "$(dirname -- "$ACP_BRIDGE_RUNTIME_CONFIG")"

{
  cat <<EOF
server:
  host: "$ACP_BRIDGE_HOST"
  port: $ACP_BRIDGE_PORT
  session_ttl_hours: $ACP_BRIDGE_SESSION_TTL_HOURS
  shutdown_timeout: $ACP_BRIDGE_SHUTDOWN_TIMEOUT

pool:
  max_processes: $ACP_BRIDGE_MAX_PROCESSES
  max_per_agent: $ACP_BRIDGE_MAX_PER_AGENT

security:
  auth_token: "$ACP_BRIDGE_TOKEN"
  allowed_ips:
EOF

  for ip in "${ALLOWED_IPS[@]}"; do
    printf '    - "%s"\n' "$ip"
  done

  cat <<EOF

env:
  CLAUDE_CODE_REAL_COMMAND: "$CLAUDE_CODE_REAL_COMMAND"

agents:
  $ACP_BRIDGE_AGENT:
    enabled: true
    mode: "$ACP_BRIDGE_AGENT_MODE"
    command: "$CLAUDE_CODE_COMMAND"
    args:
EOF

  for arg in "${CLAUDE_ARGS[@]}"; do
    printf '      - "%s"\n' "$arg"
  done

  cat <<EOF
    working_dir: "$ACP_BRIDGE_WORKDIR"
    description: "Claude Code agent via PTY"
EOF
} > "$ACP_BRIDGE_RUNTIME_CONFIG"

echo "[acp-bridge] config: $ACP_BRIDGE_RUNTIME_CONFIG"
echo "[acp-bridge] host: $ACP_BRIDGE_HOST:$ACP_BRIDGE_PORT"
echo "[acp-bridge] agent: $ACP_BRIDGE_AGENT ($ACP_BRIDGE_AGENT_MODE)"
echo "[acp-bridge] command: $CLAUDE_CODE_COMMAND"
echo "[acp-bridge] workdir: $ACP_BRIDGE_WORKDIR"

exec "$PYTHON_BIN" "$BRIDGE_DIR/main.py" --config "$ACP_BRIDGE_RUNTIME_CONFIG" "$@"
