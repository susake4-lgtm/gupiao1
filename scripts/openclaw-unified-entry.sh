#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_ROOT="${UNIFIED_REPORT_ROOT:-$ROOT_DIR/output/unified}"

usage() {
  cat <<'EOF'
Usage:
  scripts/openclaw-unified-entry.sh <query|trigger|explain> <subcommand> [options]

Query:
  query today               Show today's unified reports
  query yesterday           Show yesterday's unified reports
  query recent              Show latest 3 unified reports

Trigger:
  trigger stock            Run stock once (no notify)
  trigger futures [symbol] Run futures once (no notify)
  trigger news             Run TrendRadar once
  trigger unified [symbol] Run unified once flow

Explain:
  explain latest           Explain latest unified report in natural language
  explain <path>           Explain specific unified markdown report
EOF
}

latest_report_path() {
  if [[ ! -d "$REPORT_ROOT" ]]; then
    return 1
  fi
  local latest
  latest="$(ls -1dt "$REPORT_ROOT"/* 2>/dev/null | head -n 1 || true)"
  if [[ -z "$latest" || ! -f "$latest/unified-briefing.md" ]]; then
    return 1
  fi
  printf '%s' "$latest/unified-briefing.md"
}

yesterday_prefix() {
  if date -v-1d '+%Y%m%d' >/dev/null 2>&1; then
    date -v-1d '+%Y%m%d'
  else
    date -d 'yesterday' '+%Y%m%d'
  fi
}

list_reports_by_prefix() {
  local prefix="$1"
  if [[ ! -d "$REPORT_ROOT" ]]; then
    echo "[openclaw-unified] no report directory: $REPORT_ROOT"
    return 0
  fi
  local found=false
  for dir in "$REPORT_ROOT"/${prefix}*; do
    if [[ -d "$dir" && -f "$dir/unified-briefing.md" ]]; then
      found=true
      echo "$dir/unified-briefing.md"
    fi
  done
  if [[ "$found" == false ]]; then
    echo "[openclaw-unified] no reports for prefix $prefix"
  fi
}

query_reports() {
  local mode="$1"
  case "$mode" in
    today)
      list_reports_by_prefix "$(date '+%Y%m%d')"
      ;;
    yesterday)
      list_reports_by_prefix "$(yesterday_prefix)"
      ;;
    recent)
      if [[ ! -d "$REPORT_ROOT" ]]; then
        echo "[openclaw-unified] no report directory: $REPORT_ROOT"
        return 0
      fi
      ls -1dt "$REPORT_ROOT"/* 2>/dev/null | head -n 3 | while IFS= read -r dir; do
        if [[ -f "$dir/unified-briefing.md" ]]; then
          echo "$dir/unified-briefing.md"
        fi
      done
      ;;
    *)
      echo "[openclaw-unified] unknown query mode: $mode" >&2
      usage >&2
      exit 1
      ;;
  esac
}

trigger_flow() {
  local target="$1"
  local symbol="${2:-${FUTURES_BRIEFING_SYMBOL:-a0}}"
  case "$target" in
    stock)
      "$ROOT_DIR/scripts/run-dsa-once.sh"
      ;;
    futures)
      "$ROOT_DIR/scripts/run-futures-briefing-once.sh" --no-notify --symbol "$symbol"
      ;;
    news)
      "$ROOT_DIR/scripts/run-trendradar-once.sh"
      ;;
    unified)
      "$ROOT_DIR/scripts/run-unified-briefing-once.sh" --futures-symbol "$symbol"
      ;;
    *)
      echo "[openclaw-unified] unknown trigger target: $target" >&2
      usage >&2
      exit 1
      ;;
  esac
}

explain_report() {
  local report_path="$1"
  if [[ ! -f "$report_path" ]]; then
    echo "[openclaw-unified] report not found: $report_path" >&2
    exit 1
  fi

  local run_id
  run_id="$(awk -F': ' '/^- run_id:/ {print $2; exit}' "$report_path")"
  local status
  status="$(awk -F': ' '/^- overall_status:/ {print $2; exit}' "$report_path")"

  echo "统一报告解读："
  echo "- run_id：${run_id:-unknown}"
  echo "- 总状态：${status:-unknown}"

  echo "- 核心结论："
  awk '
    /^## 强化$/ {flag=1; next}
    /^## / && flag==1 {flag=0}
    flag==1 && /^- / {print "  " $0}
  ' "$report_path"

  echo "- 风险提示："
  awk '
    /^## 证伪$/ {flag=1; next}
    /^## / && flag==1 {flag=0}
    flag==1 && /^- / {print "  " $0}
  ' "$report_path"

  echo "- 下一步："
  awk '
    /^## 下一观察点$/ {flag=1; next}
    /^## / && flag==1 {flag=0}
    flag==1 && /^- / {print "  " $0}
  ' "$report_path"
}

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 1
fi

action="$1"
subcommand="$2"
shift 2

case "$action" in
  query)
    query_reports "$subcommand"
    ;;
  trigger)
    symbol_arg="${1:-}"
    trigger_flow "$subcommand" "$symbol_arg"
    ;;
  explain)
    if [[ "$subcommand" == "latest" ]]; then
      latest="$(latest_report_path || true)"
      if [[ -z "$latest" ]]; then
        echo "[openclaw-unified] no latest report found under $REPORT_ROOT" >&2
        exit 1
      fi
      explain_report "$latest"
    else
      explain_report "$subcommand"
    fi
    ;;
  *)
    echo "[openclaw-unified] unknown action: $action" >&2
    usage >&2
    exit 1
    ;;
esac
