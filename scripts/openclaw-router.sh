#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LEGACY_QUERY_ENTRY="$ROOT_DIR/scripts/openclaw-unified-entry.sh"
NEXT_QUERY_ENTRY="$ROOT_DIR/scripts/openclaw-query-entry.sh"
BRIDGE_SUBMIT_SCRIPT="$ROOT_DIR/scripts/openclaw-acp-bridge-submit.sh"

usage() {
  cat <<'EOF'
Usage:
  scripts/openclaw-router.sh <query|explain|trigger|modify|create> [args...]

Routes:
  query ...    Query existing project outputs (prefers openclaw-query-entry.sh when available)
  explain ...  Explain existing project outputs (prefers openclaw-query-entry.sh when available)
  trigger ...  Trigger existing project scripts via openclaw-unified-entry.sh
  modify ...   Submit a modify request through acp-bridge
  create ...   Submit a create request through acp-bridge

Examples:
  scripts/openclaw-router.sh query recent
  scripts/openclaw-router.sh explain latest
  scripts/openclaw-router.sh trigger futures a0
  scripts/openclaw-router.sh modify "把 futures 的输出模板改一下"
  scripts/openclaw-router.sh create --source feishu "新增一个项目内文档"
EOF
}

run_script() {
  local script="$1"
  shift

  if [[ ! -f "$script" ]]; then
    echo "[openclaw-router] script not found: $script" >&2
    exit 1
  fi

  exec bash "$script" "$@"
}

resolve_query_entry() {
  if [[ -f "$NEXT_QUERY_ENTRY" ]]; then
    printf '%s' "$NEXT_QUERY_ENTRY"
    return 0
  fi

  printf '%s' "$LEGACY_QUERY_ENTRY"
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

action="$1"
shift

case "$action" in
  query|explain)
    run_script "$(resolve_query_entry)" "$action" "$@"
    ;;
  trigger)
    run_script "$LEGACY_QUERY_ENTRY" "$action" "$@"
    ;;
  modify|create)
    run_script "$BRIDGE_SUBMIT_SCRIPT" "$action" "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "[openclaw-router] unknown action: $action" >&2
    usage >&2
    exit 1
    ;;
esac
