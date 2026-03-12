#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/acp-bridge.env"
TASK_TYPE="${1:-}"
SOURCE="openclaw-local"
REQUEST_ID=""
SESSION_ID=""
TIMEOUT="600"
URL=""

usage() {
  cat <<'EOF'
Usage:
  scripts/openclaw-acp-bridge-submit.sh <modify|create> [options] <instruction>

Options:
  --source <source>         Request source label (default: openclaw-local)
  --request-id <id>         Explicit request id
  --session <id>            Explicit bridge session id (default: request id)
  --timeout <seconds>       HTTP timeout in seconds (default: 600)
  --url <bridge-url>        Override bridge URL (default from config/acp-bridge.env)
  -h, --help                Show this help

Examples:
  scripts/openclaw-acp-bridge-submit.sh modify "把 futures 的输出模板改一下"
  scripts/openclaw-acp-bridge-submit.sh create --source feishu "新增一个项目内文档"
EOF
}

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

: "${ACP_BRIDGE_HOST:=127.0.0.1}"
: "${ACP_BRIDGE_PORT:=8001}"
: "${ACP_BRIDGE_TOKEN:=}"
: "${ACP_BRIDGE_AGENT:=claude}"
: "${ACP_BRIDGE_WORKDIR:=$ROOT_DIR}"

if [[ -z "$TASK_TYPE" ]] || [[ "$TASK_TYPE" == "-h" ]] || [[ "$TASK_TYPE" == "--help" ]]; then
  usage
  exit 0
fi
shift

case "$TASK_TYPE" in
  modify|create)
    ;;
  *)
    echo "Expected task type modify|create, got: $TASK_TYPE" >&2
    usage >&2
    exit 1
    ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE="$2"
      shift 2
      ;;
    --request-id)
      REQUEST_ID="$2"
      shift 2
      ;;
    --session)
      SESSION_ID="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --url)
      URL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [[ -z "$REQUEST_ID" ]]; then
  if command -v uuidgen >/dev/null 2>&1; then
    REQUEST_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  else
    REQUEST_ID="$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"
  fi
fi

if [[ -z "$SESSION_ID" ]]; then
  if command -v uuidgen >/dev/null 2>&1; then
    SESSION_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  else
    SESSION_ID="$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"
  fi
fi

if [[ -z "$URL" ]]; then
  URL="http://${ACP_BRIDGE_HOST}:${ACP_BRIDGE_PORT}/runs"
fi

if [[ $# -gt 0 ]]; then
  INSTRUCTION="$*"
elif [[ ! -t 0 ]]; then
  INSTRUCTION="$(cat)"
else
  echo "Instruction is required" >&2
  usage >&2
  exit 1
fi

if [[ -z "$INSTRUCTION" ]]; then
  echo "Instruction is required" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl command not found" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq command not found" >&2
  exit 1
fi

PROMPT=$(cat <<EOF
You are executing a $TASK_TYPE request through OpenClaw -> acp-bridge for the gupiao1 repository.

Execution context:
- task_type: $TASK_TYPE
- source: $SOURCE
- request_id: $REQUEST_ID
- workdir: $ACP_BRIDGE_WORKDIR

User instruction:
$INSTRUCTION

Response format request:
- Start with a short execution summary.
- If files changed, list them.
- If verification was run, list it.
- If no changes were needed, say so explicitly.
EOF
)

PAYLOAD=$(jq -n \
  --arg agent "$ACP_BRIDGE_AGENT" \
  --arg session "$SESSION_ID" \
  --arg prompt "$PROMPT" \
  '{agent_name: $agent, session_id: $session, input: [{parts: [{content: $prompt, content_type: "text/plain"}]}]}')

TMP_BODY="$(mktemp)"
cleanup() {
  rm -f "$TMP_BODY"
}
trap cleanup EXIT

HTTP_CODE=$(curl -sS \
  --connect-timeout 10 \
  --max-time "$TIMEOUT" \
  -o "$TMP_BODY" \
  -w "%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACP_BRIDGE_TOKEN" \
  "$URL" \
  -d "$PAYLOAD" || true)

BODY="$(cat "$TMP_BODY")"

extract_summary() {
  python3 -c 'import sys
text=sys.stdin.read().strip()
lines=[line.strip() for line in text.splitlines() if line.strip()]
summary=" ".join(lines[:4]) if lines else "(empty response)"
summary=summary[:280]
print(summary)'
}

extract_tail() {
  python3 -c 'import sys
text=sys.stdin.read()
lines=text.splitlines()
print("\n".join(lines[-40:]))'
}

if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
  SUMMARY="$(printf '%s' "$BODY" | extract_summary)"
  RAW_TAIL="$(printf '%s' "$BODY" | extract_tail)"
  jq -n \
    --arg status "failed" \
    --arg request_id "$REQUEST_ID" \
    --arg task_type "$TASK_TYPE" \
    --arg source "$SOURCE" \
    --arg summary "${SUMMARY:-bridge request failed}" \
    --arg raw_tail "$RAW_TAIL" \
    --arg http_code "$HTTP_CODE" \
    '{status: $status, request_id: $request_id, task_type: $task_type, source: $source, summary: $summary, raw_tail: $raw_tail, http_code: $http_code}'
  exit 1
fi

RUN_STATUS="$(printf '%s' "$BODY" | jq -r '.status // "unknown"')"
OUTPUT_TEXT="$(printf '%s' "$BODY" | jq -r '[.output[]? | .parts[]? | select(.name != "thought" and .content != null and .content != "") | .content] | join("\n")')"
ERROR_TEXT="$(printf '%s' "$BODY" | jq -r 'if .error then ((.error.code // "error") + ": " + (.error.message // "unknown error")) else "" end')"
SESSION_ID_RESP="$(printf '%s' "$BODY" | jq -r '.session_id // empty')"

if [[ "$RUN_STATUS" == "completed" ]]; then
  SUMMARY="$(printf '%s' "$OUTPUT_TEXT" | extract_summary)"
  RAW_TAIL="$(printf '%s' "$OUTPUT_TEXT" | extract_tail)"
  jq -n \
    --arg status "$RUN_STATUS" \
    --arg request_id "$REQUEST_ID" \
    --arg task_type "$TASK_TYPE" \
    --arg source "$SOURCE" \
    --arg summary "$SUMMARY" \
    --arg raw_tail "$RAW_TAIL" \
    --arg session_id "$SESSION_ID_RESP" \
    '{status: $status, request_id: $request_id, task_type: $task_type, source: $source, summary: $summary, raw_tail: $raw_tail, session_id: $session_id}'
  exit 0
fi

FAIL_TEXT="$ERROR_TEXT"
if [[ -z "$FAIL_TEXT" ]]; then
  FAIL_TEXT="$OUTPUT_TEXT"
fi
SUMMARY="$(printf '%s' "$FAIL_TEXT" | extract_summary)"
RAW_TAIL="$(printf '%s' "$FAIL_TEXT" | extract_tail)"
jq -n \
  --arg status "failed" \
  --arg request_id "$REQUEST_ID" \
  --arg task_type "$TASK_TYPE" \
  --arg source "$SOURCE" \
  --arg summary "${SUMMARY:-bridge run failed}" \
  --arg raw_tail "$RAW_TAIL" \
  --arg session_id "$SESSION_ID_RESP" \
  '{status: $status, request_id: $request_id, task_type: $task_type, source: $source, summary: $summary, raw_tail: $raw_tail, session_id: $session_id}'
exit 1
