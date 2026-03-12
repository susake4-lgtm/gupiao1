#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_BASE_DEFAULT="$ROOT_DIR/output/unified"

FUTURES_SYMBOL="${FUTURES_BRIEFING_SYMBOL:-a0}"
OUTPUT_BASE="$OUTPUT_BASE_DEFAULT"
RUN_NEWS=true
RUN_STOCK=true

usage() {
  cat <<'EOF'
Usage:
  scripts/run-unified-briefing-once.sh [options]

Options:
  --futures-symbol <symbol>  Futures symbol passed to run-futures-briefing-once.sh (default: a0)
  --output-dir <path>        Unified report output base directory (default: output/unified)
  --skip-stock               Skip stock run (not recommended; keeps dependency-risk marker)
  --skip-news                Skip TrendRadar run
  -h, --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --futures-symbol)
      if [[ $# -lt 2 ]]; then
        echo "[unified-once] missing value for --futures-symbol" >&2
        exit 1
      fi
      FUTURES_SYMBOL="$2"
      shift 2
      ;;
    --output-dir)
      if [[ $# -lt 2 ]]; then
        echo "[unified-once] missing value for --output-dir" >&2
        exit 1
      fi
      OUTPUT_BASE="$2"
      shift 2
      ;;
    --skip-stock)
      RUN_STOCK=false
      shift
      ;;
    --skip-news)
      RUN_NEWS=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[unified-once] unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

timestamp_iso() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

safe_excerpt() {
  local file_path="$1"
  local max_lines="${2:-12}"
  if [[ ! -s "$file_path" ]]; then
    echo "(no output captured)"
    return
  fi
  awk 'NF {print; c += 1; if (c >= max) exit}' max="$max_lines" "$file_path"
}

RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RUN_DIR="$OUTPUT_BASE/$RUN_ID"
mkdir -p "$RUN_DIR"

REPORT_FILE="$RUN_DIR/unified-briefing.md"
ALERT_FILE="$RUN_DIR/alerts.log"
STOCK_LOG="$RUN_DIR/stock.log"
FUTURES_LOG="$RUN_DIR/futures.log"
NEWS_LOG="$RUN_DIR/news.log"

: > "$ALERT_FILE"

append_alert() {
  local msg="$1"
  printf '[%s] %s\n' "$(timestamp_iso)" "$msg" | tee -a "$ALERT_FILE" >&2
}

stock_ts="$(timestamp_iso)"
stock_source="scripts/run-dsa-once.sh"
stock_module="stock"
stock_confidence="high"
stock_status="success"
stock_note="股票前置链路成功"
stock_failed=false

if [[ "$RUN_STOCK" == true ]]; then
  if "$ROOT_DIR/scripts/run-dsa-once.sh" --single-notify >"$STOCK_LOG" 2>&1; then
    :
  else
    stock_status="failed"
    stock_confidence="low"
    stock_note="股票前置链路失败，期货需标记依赖风险"
    stock_failed=true
    append_alert "[degrade] stock failed; mark futures dependency risk"
  fi
else
  stock_status="skipped"
  stock_confidence="low"
  stock_note="手动跳过股票步骤，期货自动标记依赖风险"
  stock_failed=true
  printf '[%s] %s\n' "$(timestamp_iso)" "[degrade] stock skipped; futures dependency risk" >> "$ALERT_FILE"
fi

futures_ts="$(timestamp_iso)"
futures_source="scripts/run-futures-briefing-once.sh"
futures_module="futures"
futures_confidence="high"
futures_status="success"
futures_note="期货主链路成功"
futures_failed=false

if "$ROOT_DIR/scripts/run-futures-briefing-once.sh" --symbol "$FUTURES_SYMBOL" >"$FUTURES_LOG" 2>&1; then
  if [[ "$stock_failed" == true ]]; then
    futures_confidence="medium"
    futures_note="期货执行成功，但股票前置失败（依赖风险）"
    append_alert "[degrade] futures succeeded with stock dependency risk"
  fi
else
  futures_status="failed"
  futures_confidence="low"
  futures_note="期货主链路失败，本次统一任务判定失败"
  futures_failed=true
  append_alert "[critical] futures failed; unified run marked failed"
fi

news_ts="$(timestamp_iso)"
news_source="scripts/run-trendradar-once.sh"
news_module="news"
news_confidence="medium"
news_status="success"
news_note="新闻补充链路成功"
news_failed=false

if [[ "$RUN_NEWS" == true ]]; then
  if "$ROOT_DIR/scripts/run-trendradar-once.sh" >"$NEWS_LOG" 2>&1; then
    :
  else
    news_status="failed"
    news_confidence="low"
    news_note="新闻链路失败，不阻断交付，已记录降级"
    news_failed=true
    append_alert "[degrade] trendradar failed; delivery continues"
  fi
else
  news_status="skipped"
  news_confidence="low"
  news_note="手动跳过新闻步骤（不阻断）"
  printf '[%s] %s\n' "$(timestamp_iso)" "[degrade] trendradar skipped by flag" >> "$ALERT_FILE"
fi

overall_status="success"
if [[ "$futures_failed" == true ]]; then
  overall_status="failed"
elif [[ "$stock_failed" == true || "$news_failed" == true ]]; then
  overall_status="degraded"
fi

{
  echo "# 四模块统一简报（once）"
  echo
  echo "- run_id: $RUN_ID"
  echo "- generated_at: $(timestamp_iso)"
  echo "- execution_order: 股票 -> 期货 -> 新闻"
  echo "- delivery_priority: 期货 > 股票 > 新闻"
  echo "- overall_status: $overall_status"
  echo "- output_dir: $RUN_DIR"
  echo
  echo "## 执行契约映射（ts / source / module / confidence）"
  echo
  echo "| ts | source | module | confidence | status | note |"
  echo "|---|---|---|---|---|---|"
  echo "| $stock_ts | $stock_source | $stock_module | $stock_confidence | $stock_status | $stock_note |"
  echo "| $futures_ts | $futures_source | $futures_module | $futures_confidence | $futures_status | $futures_note |"
  echo "| $news_ts | $news_source | $news_module | $news_confidence | $news_status | $news_note |"
  echo
  echo "## 新增"
  echo
  echo "### 股票（${stock_status}）"
  echo '```text'
  safe_excerpt "$STOCK_LOG" 10
  echo '```'
  echo
  echo "### 期货（${futures_status}）"
  echo '```text'
  safe_excerpt "$FUTURES_LOG" 12
  echo '```'
  echo
  echo "### 新闻（${news_status}）"
  echo '```text'
  safe_excerpt "$NEWS_LOG" 5
  echo '```'
  echo
  echo "## 强化"
  if [[ "$futures_status" == "success" ]]; then
    echo "- 期货主链路成功，满足本轮优先交付目标。"
  fi
  if [[ "$stock_status" == "success" ]]; then
    echo "- 股票前置链路成功，期货依赖关系完整。"
  fi
  if [[ "$news_status" == "success" ]]; then
    echo "- 新闻补充链路成功，增强统一简报上下文。"
  fi
  if [[ "$futures_status" != "success" && "$stock_status" != "success" && "$news_status" != "success" ]]; then
    echo "- 无可强化项。"
  fi
  echo
  echo "## 证伪"
  if [[ "$futures_failed" == true ]]; then
    echo "- 期货链路失败：主目标未达成，本次任务标记失败并需优先告警。"
  fi
  if [[ "$stock_failed" == true ]]; then
    echo "- 股票链路失败：期货已标记依赖风险。"
  fi
  if [[ "$news_failed" == true ]]; then
    echo "- 新闻链路失败：按降级策略不阻断交付。"
  fi
  if [[ "$futures_failed" != true && "$stock_failed" != true && "$news_failed" != true ]]; then
    echo "- 当前无证伪项。"
  fi
  echo
  echo "## 下一观察点"
  echo "- 运行 scripts/check-four-modules-health.sh 复核 8000 / 8010 / 18789 / 3334。"
  echo "- 复核日志中是否出现关键字：正在打开HTML报告（不应出现）。"
  echo "- 如需对外查询/触发/解释，可通过 scripts/openclaw-unified-entry.sh 做 OpenClaw 命令映射。"
  echo "- 本次原始日志：stock.log / futures.log / news.log。"
  if [[ -s "$ALERT_FILE" ]]; then
    echo
    echo "## 降级与告警记录"
    echo
    echo '```text'
    cat "$ALERT_FILE"
    echo '```'
  fi
} > "$REPORT_FILE"

if [[ ! -s "$ALERT_FILE" ]]; then
  rm -f "$ALERT_FILE"
fi

echo "[unified-once] overall_status=$overall_status"
echo "[unified-once] report=$REPORT_FILE"

if [[ "$futures_failed" == true ]]; then
  exit 1
fi
