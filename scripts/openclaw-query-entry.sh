#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UNIFIED_ENTRY="$ROOT_DIR/scripts/openclaw-unified-entry.sh"
HEALTH_SCRIPT="$ROOT_DIR/scripts/check-four-modules-health.sh"
UNIFIED_REPORT_ROOT="${UNIFIED_REPORT_ROOT:-$ROOT_DIR/output/unified}"
FUTURES_DATA_ROOT="${FUTURES_DATA_ROOT:-$ROOT_DIR/data/futures}"
FUTURES_API_BASE="${FUTURES_API_BASE:-http://127.0.0.1:8010/api/futures}"
DEFAULT_FUTURES_SYMBOL="${FUTURES_BRIEFING_SYMBOL:-a0}"

validate_futures_symbol() {
  local symbol="$1"

  if [[ ! "$symbol" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "[openclaw-query] invalid futures symbol: $symbol" >&2
    exit 1
  fi
}

canonical_existing_path() {
  local path="$1"

  python3 - "$path" <<'PY'
import pathlib
import sys

try:
    print(pathlib.Path(sys.argv[1]).resolve(strict=True))
except FileNotFoundError:
    sys.exit(1)
PY
}

is_allowed_unified_report_path() {
  local root_path="$1"
  local candidate_path="$2"

  python3 - "$root_path" "$candidate_path" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
candidate = pathlib.Path(sys.argv[2])
ok = candidate.name == "unified-briefing.md" and candidate.parent.parent == root
sys.exit(0 if ok else 1)
PY
}

is_allowed_run_artifact_path() {
  local run_dir="$1"
  local candidate_path="$2"
  local expected_name="$3"

  python3 - "$run_dir" "$candidate_path" "$expected_name" <<'PY'
import pathlib
import sys

run_dir = pathlib.Path(sys.argv[1])
candidate = pathlib.Path(sys.argv[2])
expected_name = sys.argv[3]
ok = candidate.parent == run_dir and candidate.name == expected_name
sys.exit(0 if ok else 1)
PY
}

is_allowed_futures_artifact_path() {
  local root_path="$1"
  local candidate_path="$2"
  local expected_name="$3"

  python3 - "$root_path" "$candidate_path" "$expected_name" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
candidate = pathlib.Path(sys.argv[2])
expected_name = sys.argv[3]
ok = candidate.parent == root and candidate.name == expected_name
sys.exit(0 if ok else 1)
PY
}

resolve_allowed_unified_report_path() {
  local value="$1"
  local canonical_root canonical_path

  if [[ ! -d "$UNIFIED_REPORT_ROOT" ]]; then
    echo "[openclaw-query] unified report root not found: $UNIFIED_REPORT_ROOT" >&2
    exit 1
  fi

  canonical_root="$(canonical_existing_path "$UNIFIED_REPORT_ROOT" || true)"
  canonical_path="$(canonical_existing_path "$value" || true)"

  if [[ -z "$canonical_root" || -z "$canonical_path" ]]; then
    echo "[openclaw-query] unified report not found: $value" >&2
    exit 1
  fi

  if ! is_allowed_unified_report_path "$canonical_root" "$canonical_path"; then
    echo "[openclaw-query] unified report escapes artifact root: $value" >&2
    exit 1
  fi

  printf '%s' "$canonical_path"
}

resolve_unified_report_for_mode() {
  local mode="${1:-latest}"
  local report_path

  report_path="$(latest_unified_report_for_mode "$mode" || true)"
  if [[ -z "$report_path" ]]; then
    return 1
  fi

  resolve_allowed_unified_report_path "$report_path"
}

resolve_allowed_run_artifact_path() {
  local run_dir="$1"
  local artifact_name="$2"
  local artifact_path canonical_artifact_path

  artifact_path="$run_dir/$artifact_name"
  if [[ ! -f "$artifact_path" ]]; then
    return 1
  fi

  canonical_artifact_path="$(canonical_existing_path "$artifact_path" || true)"
  if [[ -z "$canonical_artifact_path" ]]; then
    return 1
  fi

  if ! is_allowed_run_artifact_path "$run_dir" "$canonical_artifact_path" "$artifact_name"; then
    echo "[openclaw-query] unified artifact escapes run directory: $artifact_path" >&2
    exit 1
  fi

  printf '%s' "$canonical_artifact_path"
}

resolve_allowed_futures_artifact_path() {
  local artifact_name="$1"
  local root_path canonical_root artifact_path canonical_artifact_path

  if [[ ! -d "$FUTURES_DATA_ROOT" ]]; then
    return 1
  fi

  root_path="$FUTURES_DATA_ROOT"
  artifact_path="$root_path/$artifact_name"
  if [[ ! -f "$artifact_path" ]]; then
    return 1
  fi

  canonical_root="$(canonical_existing_path "$root_path" || true)"
  canonical_artifact_path="$(canonical_existing_path "$artifact_path" || true)"
  if [[ -z "$canonical_root" || -z "$canonical_artifact_path" ]]; then
    return 1
  fi

  if ! is_allowed_futures_artifact_path "$canonical_root" "$canonical_artifact_path" "$artifact_name"; then
    echo "[openclaw-query] futures artifact escapes data root: $artifact_path" >&2
    exit 1
  fi

  printf '%s' "$canonical_artifact_path"
}

resolve_unified_explain_value() {
  local value="$1"
  local report_path

  case "$value" in
    latest|today|yesterday|recent)
      report_path="$(resolve_unified_report_for_mode "$value" || true)"
      if [[ -z "$report_path" ]]; then
        echo "[openclaw-query] no unified report found for mode: $value" >&2
        exit 1
      fi
      printf '%s' "$report_path"
      ;;
    /*)
      resolve_allowed_unified_report_path "$value"
      ;;
    *)
      echo "[openclaw-query] explain unified only supports latest, today, yesterday, recent, or a report under $UNIFIED_REPORT_ROOT" >&2
      exit 1
      ;;
  esac
}

usage() {
  cat <<'EOF'
Usage:
  scripts/openclaw-query-entry.sh query <unified|health|futures|stock|news> [value]
  scripts/openclaw-query-entry.sh explain <unified|health|futures|stock|news> [value]

Preferred examples:
  scripts/openclaw-query-entry.sh query unified recent
  scripts/openclaw-query-entry.sh query health today
  scripts/openclaw-query-entry.sh query futures a0
  scripts/openclaw-query-entry.sh query stock today
  scripts/openclaw-query-entry.sh query news latest
  scripts/openclaw-query-entry.sh explain unified latest
  scripts/openclaw-query-entry.sh explain futures a0

Compatibility:
  scripts/openclaw-query-entry.sh query recent
  scripts/openclaw-query-entry.sh explain latest
EOF
}

latest_unified_report_path() {
  if [[ ! -d "$UNIFIED_REPORT_ROOT" ]]; then
    return 1
  fi

  local latest_dir
  latest_dir="$(ls -1dt "$UNIFIED_REPORT_ROOT"/* 2>/dev/null | head -n 1 || true)"
  if [[ -z "$latest_dir" || ! -f "$latest_dir/unified-briefing.md" ]]; then
    return 1
  fi

  printf '%s' "$latest_dir/unified-briefing.md"
}

latest_unified_report_for_mode() {
  local mode="${1:-latest}"

  case "$mode" in
    latest|recent)
      latest_unified_report_path
      ;;
    today|yesterday)
      if [[ ! -d "$UNIFIED_REPORT_ROOT" ]]; then
        return 1
      fi
      local prefix latest_dir
      if [[ "$mode" == "today" ]]; then
        prefix="$(date '+%Y%m%d')"
      else
        prefix="$(date -v-1d '+%Y%m%d')"
      fi
      latest_dir="$(ls -1dt "$UNIFIED_REPORT_ROOT"/${prefix}* 2>/dev/null | head -n 1 || true)"
      if [[ -z "$latest_dir" || ! -f "$latest_dir/unified-briefing.md" ]]; then
        return 1
      fi
      printf '%s' "$latest_dir/unified-briefing.md"
      ;;
    *)
      latest_unified_report_path
      ;;
  esac
}

latest_run_dir_for_mode() {
  local mode="${1:-latest}"
  local report_path
  report_path="$(resolve_unified_report_for_mode "$mode" || true)"
  if [[ -z "$report_path" ]]; then
    return 1
  fi
  dirname "$report_path"
}

extract_unified_section() {
  local report_path="$1"
  local section_name="$2"

  awk -v section_name="$section_name" '
    index($0, "### " section_name "（") == 1 {
      flag = 1
    }
    /^### / && flag == 1 && index($0, "### " section_name "（") != 1 {
      exit
    }
    flag == 1 {
      print
    }
  ' "$report_path"
}

extract_unified_section_status() {
  local report_path="$1"
  local section_name="$2"

  awk -v section_name="$section_name" '
    index($0, "### " section_name "（") == 1 {
      line = $0
      sub(/^.*（/, "", line)
      sub(/）.*$/, "", line)
      print line
      exit
    }
  ' "$report_path"
}

preview_section_lines() {
  local max_lines="${1:-5}"

  awk -v max_lines="$max_lines" '
    /^```/ { next }
    /^### / { next }
    NF {
      print "  - " $0
      count++
      if (count >= max_lines) {
        exit
      }
    }
  '
}

render_log_tail() {
  local log_path="$1"
  local lines="${2:-40}"

  echo "[openclaw-query] source: $log_path"
  tail -n "$lines" "$log_path"
}

futures_report_path() {
  local symbol="$1"
  printf '%s' "$FUTURES_DATA_ROOT/report_${symbol}.md"
}

futures_json_path() {
  local symbol="$1"
  printf '%s' "$FUTURES_DATA_ROOT/latest_${symbol}.json"
}

fetch_futures_api_json() {
  local symbol="$1"
  local tmp_file
  tmp_file="$(mktemp)"

  if curl -fsS --max-time 5 --get --data-urlencode "symbol=$symbol" "$FUTURES_API_BASE/latest" >"$tmp_file" 2>/dev/null && [[ -s "$tmp_file" ]]; then
    printf '%s' "$tmp_file"
    return 0
  fi

  rm -f "$tmp_file"
  return 1
}

render_futures_summary_from_json() {
  local json_path="$1"
  local symbol="$2"
  local source_label="$3"

  python3 - "$json_path" "$symbol" "$source_label" <<'PY'
import json
import pathlib
import sys

json_path = pathlib.Path(sys.argv[1])
requested_symbol = sys.argv[2]
source_label = sys.argv[3]
data = json.loads(json_path.read_text(encoding="utf-8"))
summary = data.get("summary") if isinstance(data.get("summary"), dict) else {}
daily = summary.get("daily") if isinstance(summary.get("daily"), dict) else {}
minute = summary.get("minute_30m") if isinstance(summary.get("minute_30m"), dict) else {}
breadth = summary.get("market_breadth") if isinstance(summary.get("market_breadth"), dict) else {}
realtime = data.get("realtime") if isinstance(data.get("realtime"), dict) else {}
key_points = summary.get("key_points") if isinstance(summary.get("key_points"), list) else []
news_tail = data.get("news_tail") if isinstance(data.get("news_tail"), list) else []

symbol_label = (
    realtime.get("symbol_label")
    or summary.get("symbol_label")
    or data.get("symbol")
    or requested_symbol
)

print(f"[openclaw-query] source: {source_label}")
print(f"期货查询结果：{symbol_label}")
print(f"- generated_at: {data.get('ts') or 'unknown'}")
if daily:
    print(
        f"- 日线：{daily.get('latest_date') or 'unknown'} 收盘 {daily.get('latest_close') or 'N/A'}，较前日 {daily.get('change_pct_vs_prev') or 'N/A'}%"
    )
if minute:
    print(
        f"- 30m：最新 {minute.get('latest_close') or 'N/A'}，近5根区间 {minute.get('min_close_5') or 'N/A'} ~ {minute.get('max_close_5') or 'N/A'}"
    )
if breadth:
    print(
        f"- 市场宽度：{breadth.get('contracts') or 'N/A'} 个样本，上涨 {breadth.get('up') or 0} / 下跌 {breadth.get('down') or 0} / 平 {breadth.get('flat') or 0}，情绪 {breadth.get('market_tone') or 'N/A'}"
    )
if key_points:
    print("- 关键结论：")
    for item in key_points[:4]:
      if item:
        print(f"  - {item}")
if news_tail:
    latest_news = news_tail[-1] if isinstance(news_tail[-1], dict) else {}
    title = latest_news.get("title")
    if title:
        print(f"- 最新资讯：{title}")
PY
}

render_futures_explain_from_markdown() {
  local report_path="$1"

  echo "期货结果解读："
  echo "- 来源：$report_path"
  awk '
    /^- Requested:/ {print "- 标的：" $3}
    /^- Generated at:/ {print "- 生成时间：" $4}
    /^## 关键结论$/ {flag=1; next}
    /^## / && flag==1 {flag=0}
    flag==1 && /^- / {print "  " $0}
  ' "$report_path"
}

render_futures_explain_from_json() {
  local json_path="$1"
  local symbol="$2"
  local source_label="$3"

  python3 - "$json_path" "$symbol" "$source_label" <<'PY'
import json
import pathlib
import sys

json_path = pathlib.Path(sys.argv[1])
requested_symbol = sys.argv[2]
source_label = sys.argv[3]
data = json.loads(json_path.read_text(encoding="utf-8"))
summary = data.get("summary") if isinstance(data.get("summary"), dict) else {}
daily = summary.get("daily") if isinstance(summary.get("daily"), dict) else {}
minute = summary.get("minute_30m") if isinstance(summary.get("minute_30m"), dict) else {}
key_points = summary.get("key_points") if isinstance(summary.get("key_points"), list) else []
news_tail = data.get("news_tail") if isinstance(data.get("news_tail"), list) else []

print("期货结果解读：")
print(f"- 来源：{source_label}")
print(f"- 标的：{data.get('symbol') or requested_symbol}")
print(f"- 生成时间：{data.get('ts') or 'unknown'}")
if daily and minute:
    print(
        f"- 判断：日线最新收盘 {daily.get('latest_close') or 'N/A'}，30m 最新 {minute.get('latest_close') or 'N/A'}，可作为当前短线观察锚点。"
    )
if key_points:
    print("- 核心结论：")
    for item in key_points[:3]:
        if item:
            print(f"  - {item}")
if news_tail:
    latest_news = news_tail[-1] if isinstance(news_tail[-1], dict) else {}
    title = latest_news.get("title")
    if title:
        print(f"- 观察变量：最新资讯为“{title}”")
PY
}

query_unified() {
  local mode="${1:-recent}"
  bash "$UNIFIED_ENTRY" query "$mode"
}

explain_unified() {
  local value="${1:-latest}"
  local resolved_value

  resolved_value="$(resolve_unified_explain_value "$value")"
  bash "$UNIFIED_ENTRY" explain "$resolved_value"
}

query_health() {
  local value="${1:-latest}"

  case "$value" in
    today|latest|now)
      bash "$HEALTH_SCRIPT"
      ;;
    *)
      echo "[openclaw-query] unsupported health query value: $value" >&2
      usage >&2
      exit 1
      ;;
  esac
}

explain_health() {
  local value="${1:-latest}"

  case "$value" in
    today|latest|now)
      echo "四模块健康状态解读："
      echo "- 说明：以下结果直接复用 scripts/check-four-modules-health.sh 的实时检查输出。"
      bash "$HEALTH_SCRIPT"
      ;;
    *)
      echo "[openclaw-query] unsupported health explain value: $value" >&2
      usage >&2
      exit 1
      ;;
  esac
}

query_futures() {
  local symbol="${1:-$DEFAULT_FUTURES_SYMBOL}"
  local report_path json_path api_json api_source_label

  validate_futures_symbol "$symbol"
  report_path="$(resolve_allowed_futures_artifact_path "report_${symbol}.md" || true)"
  json_path="$(resolve_allowed_futures_artifact_path "latest_${symbol}.json" || true)"
  api_source_label="$FUTURES_API_BASE/latest?symbol=$symbol"

  if [[ -n "$report_path" ]]; then
    echo "[openclaw-query] source: $report_path"
    cat "$report_path"
    return 0
  fi

  if [[ -n "$json_path" ]]; then
    render_futures_summary_from_json "$json_path" "$symbol" "$json_path"
    return 0
  fi

  api_json="$(fetch_futures_api_json "$symbol" || true)"
  if [[ -n "$api_json" ]]; then
    trap 'rm -f "$api_json"' RETURN
    render_futures_summary_from_json "$api_json" "$symbol" "$api_source_label"
    return 0
  fi

  echo "[openclaw-query] no futures output found for symbol: $symbol"
  echo "[openclaw-query] checked: $report_path"
  echo "[openclaw-query] checked: $json_path"
  echo "[openclaw-query] checked: $api_source_label"
  echo "[openclaw-query] no new run was triggered."
}

explain_futures() {
  local symbol="${1:-$DEFAULT_FUTURES_SYMBOL}"
  local report_path json_path api_json api_source_label

  validate_futures_symbol "$symbol"
  report_path="$(resolve_allowed_futures_artifact_path "report_${symbol}.md" || true)"
  json_path="$(resolve_allowed_futures_artifact_path "latest_${symbol}.json" || true)"
  api_source_label="$FUTURES_API_BASE/latest?symbol=$symbol"

  if [[ -n "$report_path" ]]; then
    render_futures_explain_from_markdown "$report_path"
    return 0
  fi

  if [[ -n "$json_path" ]]; then
    render_futures_explain_from_json "$json_path" "$symbol" "$json_path"
    return 0
  fi

  api_json="$(fetch_futures_api_json "$symbol" || true)"
  if [[ -n "$api_json" ]]; then
    trap 'rm -f "$api_json"' RETURN
    render_futures_explain_from_json "$api_json" "$symbol" "$api_source_label"
    return 0
  fi

  echo "[openclaw-query] no futures explainable output found for symbol: $symbol"
  echo "[openclaw-query] no new run was triggered."
}

query_module_from_unified() {
  local module_key="$1"
  local section_name="$2"
  local mode="${3:-latest}"
  local report_path section run_dir log_path tail_lines

  tail_lines=40
  if [[ "$module_key" == "news" ]]; then
    tail_lines=15
  fi

  report_path="$(resolve_unified_report_for_mode "$mode" || true)"
  if [[ -n "$report_path" ]]; then
    section="$(extract_unified_section "$report_path" "$section_name")"
    if [[ -n "$section" ]]; then
      echo "[openclaw-query] source: $report_path"
      printf '%s\n' "$section"
      return 0
    fi
  fi

  run_dir="$(latest_run_dir_for_mode "$mode" || true)"
  if [[ -n "$run_dir" ]]; then
    log_path="$(resolve_allowed_run_artifact_path "$run_dir" "${module_key}.log" || true)"
    if [[ -n "$log_path" ]]; then
      render_log_tail "$log_path" "$tail_lines"
      return 0
    fi
  fi

  echo "[openclaw-query] no ${module_key} output found in latest unified artifacts."
  if [[ -n "$report_path" ]]; then
    echo "[openclaw-query] checked report: $report_path"
  fi
  if [[ -n "$run_dir" ]]; then
    echo "[openclaw-query] checked log: $run_dir/${module_key}.log"
  fi
  echo "[openclaw-query] no new run was triggered."
}

explain_module_from_unified() {
  local module_key="$1"
  local section_name="$2"
  local label="$3"
  local mode="${4:-latest}"
  local report_path section status run_dir log_path preview_lines

  preview_lines=5
  if [[ "$module_key" == "news" ]]; then
    preview_lines=3
  fi

  report_path="$(resolve_unified_report_for_mode "$mode" || true)"
  if [[ -n "$report_path" ]]; then
    section="$(extract_unified_section "$report_path" "$section_name")"
    status="$(extract_unified_section_status "$report_path" "$section_name")"
    if [[ -n "$section" ]]; then
      echo "${label}结果解读："
      echo "- 来源：$report_path"
      echo "- 状态：${status:-unknown}"
      if [[ "${status:-unknown}" == "success" ]]; then
        echo "- 判断：最近一次 unified 运行中，${label}链路成功产出，可优先复用现有结果。"
      else
        echo "- 判断：最近一次 unified 运行中，${label}链路状态为 ${status:-unknown}，需结合原日志继续判断。"
      fi
      echo "- 证据："
      printf '%s\n' "$section" | preview_section_lines "$preview_lines"
      return 0
    fi
  fi

  run_dir="$(latest_run_dir_for_mode "$mode" || true)"
  if [[ -n "$run_dir" ]]; then
    log_path="$(resolve_allowed_run_artifact_path "$run_dir" "${module_key}.log" || true)"
    if [[ -n "$log_path" ]]; then
      echo "${label}结果解读："
      echo "- 来源：$log_path"
      echo "- 状态：unknown"
      echo "- 判断：未从 unified 报告提取到结构化段落，以下复用最近日志尾部作为线索。"
      echo "- 证据："
      tail -n 5 "$log_path" | awk 'NF {print "  - " $0}'
      return 0
    fi
  fi

  echo "[openclaw-query] no ${label} output found to explain."
  echo "[openclaw-query] no new run was triggered."
}

handle_query() {
  local target="${1:-}"
  local value="${2:-}"

  case "$target" in
    unified)
      query_unified "${value:-recent}"
      ;;
    health)
      query_health "${value:-latest}"
      ;;
    futures)
      query_futures "${value:-$DEFAULT_FUTURES_SYMBOL}"
      ;;
    stock)
      query_module_from_unified "stock" "股票" "${value:-latest}"
      ;;
    news)
      query_module_from_unified "news" "新闻" "${value:-latest}"
      ;;
    today|yesterday|recent)
      query_unified "$target"
      ;;
    *)
      echo "[openclaw-query] unknown query target: $target" >&2
      usage >&2
      exit 1
      ;;
  esac
}

handle_explain() {
  local target="${1:-}"
  local value="${2:-}"

  case "$target" in
    unified)
      explain_unified "${value:-latest}"
      ;;
    health)
      explain_health "${value:-latest}"
      ;;
    futures)
      explain_futures "${value:-$DEFAULT_FUTURES_SYMBOL}"
      ;;
    stock)
      explain_module_from_unified "stock" "股票" "股票" "${value:-latest}"
      ;;
    news)
      explain_module_from_unified "news" "新闻" "新闻" "${value:-latest}"
      ;;
    latest)
      explain_unified "$target"
      ;;
    today|yesterday|recent)
      explain_unified "$target"
      ;;
    /*)
      explain_unified "$target"
      ;;
    *)
      echo "[openclaw-query] unknown explain target: $target" >&2
      usage >&2
      exit 1
      ;;
  esac
}

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 1
fi

action="$1"
shift

case "$action" in
  query)
    handle_query "$@"
    ;;
  explain)
    handle_explain "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "[openclaw-query] unknown action: $action" >&2
    usage >&2
    exit 1
    ;;
 esac
