#!/usr/bin/env bash
set -euo pipefail

REAL_CLAUDE_COMMAND="${CLAUDE_CODE_REAL_COMMAND:-$(command -v claude || true)}"

if [ -z "$REAL_CLAUDE_COMMAND" ]; then
  echo "[claude-wrapper] claude command not found" >&2
  exit 1
fi

if [ "$#" -lt 1 ]; then
  echo "[claude-wrapper] prompt argument is required" >&2
  exit 1
fi

PROMPT="${!#}"
if [ "$#" -gt 1 ]; then
  PASSTHROUGH=("${@:1:$#-1}")
else
  PASSTHROUGH=()
fi

FILTERED_ARGS=()
for arg in "${PASSTHROUGH[@]}"; do
  if [ "$arg" = "-p" ] || [ "$arg" = "--print" ]; then
    continue
  fi
  FILTERED_ARGS+=("$arg")
done

exec "$REAL_CLAUDE_COMMAND" -p "${FILTERED_ARGS[@]}" "$PROMPT"
