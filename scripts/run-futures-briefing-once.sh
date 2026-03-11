#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/futures.env"

HOST="127.0.0.1"
PORT="8010"
SYMBOL="${FUTURES_BRIEFING_SYMBOL:-a0}"
SEND_NOTIFY=true

usage() {
  cat <<'EOF'
Usage:
  scripts/run-futures-briefing-once.sh [options] [symbol]

Options:
  --symbol <symbol>  Futures symbol (default: FUTURES_BRIEFING_SYMBOL or a0)
  --no-notify        Skip Feishu notification and print briefing text only
  -h, --help         Show this help
EOF
}

POSITIONAL_SYMBOL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --symbol)
      if [[ $# -lt 2 ]]; then
        echo "[futures-briefing] missing value for --symbol" >&2
        exit 1
      fi
      SYMBOL="$2"
      shift 2
      ;;
    --no-notify)
      SEND_NOTIFY=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$POSITIONAL_SYMBOL" ]]; then
        POSITIONAL_SYMBOL="$1"
        shift
      else
        echo "[futures-briefing] unknown argument: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -n "$POSITIONAL_SYMBOL" ]]; then
  SYMBOL="$POSITIONAL_SYMBOL"
fi

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  HOST="${FUTURES_API_HOST:-$HOST}"
  PORT="${FUTURES_API_PORT:-$PORT}"
fi

if [ "$SEND_NOTIFY" = true ] && [ -z "${FEISHU_WEBHOOK_URL:-}" ]; then
  echo "[futures-briefing] FEISHU_WEBHOOK_URL is empty"
  echo "[futures-briefing] fill config/futures.env first"
  exit 1
fi

if [ -x "$ROOT_DIR/external/daily_stock_analysis/.venv/bin/python" ]; then
  PYTHON_BIN="$ROOT_DIR/external/daily_stock_analysis/.venv/bin/python"
else
  PYTHON_BIN="python3"
fi

API_BASE="http://${HOST}:${PORT}/api/futures"

PAYLOAD="$($PYTHON_BIN - "$SYMBOL" <<'PY'
import json
import sys

print(json.dumps({"symbol": sys.argv[1]}, ensure_ascii=False))
PY
)"

RUN_ONCE_TMP="$(mktemp)"
RUN_ONCE_CODE="$(curl -sS -o "$RUN_ONCE_TMP" -w "%{http_code}" -X POST "$API_BASE/run-once" -H "Content-Type: application/json" -d "$PAYLOAD" || true)"

if [ "$RUN_ONCE_CODE" -lt 200 ] || [ "$RUN_ONCE_CODE" -ge 300 ]; then
  ERROR_MSG="$($PYTHON_BIN - "$RUN_ONCE_TMP" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
try:
    data = json.loads(text)
except Exception:
    print(text.strip() or "run-once request failed")
    raise SystemExit(0)
print(data.get("message") or text.strip() or "run-once request failed")
PY
)"
  rm -f "$RUN_ONCE_TMP"
  echo "[futures-briefing] run-once failed ($RUN_ONCE_CODE): $ERROR_MSG"
  exit 1
fi

BRIEFING_MARKET_TMP="$(mktemp)"
BRIEFING_FOCUS_TMP="$(mktemp)"

$PYTHON_BIN - "$RUN_ONCE_TMP" "$BRIEFING_MARKET_TMP" "$BRIEFING_FOCUS_TMP" <<'PY'
import json
import pathlib
import re
import sys

input_path = pathlib.Path(sys.argv[1])
market_path = pathlib.Path(sys.argv[2])
focus_path = pathlib.Path(sys.argv[3])

data = json.loads(input_path.read_text(encoding="utf-8"))


def _to_float(value):
    try:
        if value is None:
            return None
        text = str(value).strip()
        if text == "":
            return None
        return float(text)
    except Exception:
        return None


def _fmt_price(value, digits=2):
    number = _to_float(value)
    if number is None:
        return "N/A"
    return f"{number:.{digits}f}"


def _fmt_ratio_pct(value, digits=2):
    number = _to_float(value)
    if number is None:
        return "N/A"
    return f"{number * 100:.{digits}f}%"


def _fmt_percent_smart(value, digits=2):
    number = _to_float(value)
    if number is None:
        return "N/A"
    if abs(number) <= 1:
        return f"{number * 100:.{digits}f}%"
    return f"{number:.{digits}f}%"


def _label_from_item(item):
    if not isinstance(item, dict):
        return "N/A"
    return str(item.get("symbol_label") or item.get("symbol") or "N/A")


def _symbol_prefix(symbol):
    text = str(symbol or "").strip().lower()
    m = re.match(r"([a-z]+)", text)
    return m.group(1) if m else ""


def _dominant_chain(top_gainers):
    counts = {}
    for item in top_gainers[:5]:
        if not isinstance(item, dict):
            continue
        prefix = _symbol_prefix(item.get("symbol"))
        if not prefix:
            continue
        counts[prefix] = counts.get(prefix, 0) + 1
    if not counts:
        return ""
    prefix, count = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)[0]
    if count >= 2:
        return prefix.upper()
    return ""


summary = data.get("summary") if isinstance(data.get("summary"), dict) else {}
market = data.get("market_overview") if isinstance(data.get("market_overview"), dict) else {}
realtime = data.get("realtime") if isinstance(data.get("realtime"), dict) else {}
news_tail = data.get("news_tail") if isinstance(data.get("news_tail"), list) else []

ts = str(data.get("ts") or "")
date_text = ts[:10] if len(ts) >= 10 else "N/A"

breadth = market.get("breadth") if isinstance(market.get("breadth"), dict) else {}
contracts = int(_to_float(market.get("contracts")) or 0)
market_tone = str(market.get("market_tone") or "N/A")
avg_change = _fmt_ratio_pct(market.get("average_change_percent"))
sample_scope = str(market.get("sample_scope") or "本次抓取样本（非全市场全量）")

top_gainers = market.get("top_gainers") if isinstance(market.get("top_gainers"), list) else []
top_losers = market.get("top_losers") if isinstance(market.get("top_losers"), list) else []
dominant_chain = _dominant_chain(top_gainers)

if dominant_chain:
    market_conclusion = f"今日样本盘面整体{market_tone}，强势主要集中在{dominant_chain}链条，扩散性仍待确认。"
else:
    market_conclusion = f"今日样本盘面整体{market_tone}，但强弱分化与扩散节奏仍需持续跟踪。"

market_lines = [
    f"【期货市场简报｜{date_text}】",
    "",
    "一、执行结论",
    f"- {market_conclusion}",
    "",
    "二、关键证据",
    f"- 样本合约：{contracts}（上涨{int(_to_float(breadth.get('up')) or 0)} / 下跌{int(_to_float(breadth.get('down')) or 0)} / 持平{int(_to_float(breadth.get('flat')) or 0)}）",
    f"- 样本平均涨跌幅：{avg_change}",
]

if top_gainers:
    gainers = "、".join(
        f"{_label_from_item(item)} {_fmt_ratio_pct(item.get('change_percent'))}"
        for item in top_gainers[:3]
    )
    market_lines.append(f"- 领涨：{gainers}")
else:
    market_lines.append("- 领涨：暂无可用数据")

if top_losers:
    losers = "、".join(
        f"{_label_from_item(item)} {_fmt_ratio_pct(item.get('change_percent'))}"
        for item in top_losers[:3]
    )
    market_lines.append(f"- 领跌（相对弱势）：{losers}")
else:
    market_lines.append("- 领跌（相对弱势）：暂无可用数据")

market_lines.extend(
    [
        "",
        "三、风险提示",
        f"- 当前统计基于实时样本，非全市场全量（{sample_scope}）。",
        "- 若强势仍集中在单一链条，持续性与外溢强度需谨慎验证。",
        "",
        "四、下一步观察",
        "- 观察强势是否从单一链条扩散至更多品种。",
        "- 跟踪夜盘宏观与能源信息对次日风险偏好的影响。",
    ]
)

symbol = str(data.get("symbol") or "").strip().lower()
focus_label = str(
    realtime.get("symbol_label")
    or realtime.get("name")
    or summary.get("symbol_label")
    or (symbol if symbol else "N/A")
)

daily = summary.get("daily") if isinstance(summary.get("daily"), dict) else {}
minute = summary.get("minute_30m") if isinstance(summary.get("minute_30m"), dict) else {}

latest_daily_close = _fmt_price(daily.get("latest_close"))
daily_change = _fmt_percent_smart(daily.get("change_pct_vs_prev"), 4)
latest_30m = _fmt_price(minute.get("latest_close"))
min_30m = _fmt_price(minute.get("min_close_5"))
max_30m = _fmt_price(minute.get("max_close_5"))

latest_30m_value = _to_float(minute.get("latest_close"))
min_30m_value = _to_float(minute.get("min_close_5"))
max_30m_value = _to_float(minute.get("max_close_5"))

focus_conclusion = "日线修复，30m高位震荡，方向选择临近。"
if latest_30m_value is not None and min_30m_value is not None and max_30m_value is not None and max_30m_value > min_30m_value:
    band = max_30m_value - min_30m_value
    if latest_30m_value >= max_30m_value - band * 0.2:
        focus_conclusion = "日线修复，30m运行在区间上沿附近，短线偏强但需防冲高回落。"
    elif latest_30m_value <= min_30m_value + band * 0.2:
        focus_conclusion = "日线修复力度一般，30m贴近区间下沿，短线承接仍需确认。"

latest_news_title = "N/A"
if news_tail:
    latest_news = news_tail[-1] if isinstance(news_tail[-1], dict) else {}
    latest_news_title = str(latest_news.get("title") or "N/A")

risk_line = "- 若30m有效跌破区间下沿，短线强度可能回落。"
if min_30m_value is not None:
    risk_line = f"- 若30m有效跌破{min_30m_value:.0f}，短线强度可能回落。"

upside_line = "- 若30m放量站稳区间上沿，关注是否形成新一轮上攻结构。"
if max_30m_value is not None:
    upside_line = f"- 若30m放量站稳{max_30m_value:.0f}，关注是否形成新一轮上攻结构。"

focus_lines = [
    f"【重点品种跟踪｜{focus_label}】",
    "",
    "一、执行结论",
    f"- {focus_conclusion}",
    "",
    "二、关键证据",
    f"- 日线收盘：{latest_daily_close}，较前一日 {daily_change}",
    f"- 30m最新：{latest_30m}",
    f"- 近5根30m区间：{min_30m} ~ {max_30m}",
    f"- 最新资讯：{latest_news_title}",
    "",
    "三、风险与触发",
    risk_line,
    upside_line,
    "",
    "四、下一步观察",
    "- 关注夜盘持仓与成交是否同步放大。",
    "- 关注相关品种是否出现联动强化或背离。",
]

market_path.write_text("\n".join(market_lines).strip(), encoding="utf-8")
focus_path.write_text("\n".join(focus_lines).strip(), encoding="utf-8")
PY

rm -f "$RUN_ONCE_TMP"

BRIEFING_MARKET_TEXT="$(cat "$BRIEFING_MARKET_TMP")"
BRIEFING_FOCUS_TEXT="$(cat "$BRIEFING_FOCUS_TMP")"

rm -f "$BRIEFING_MARKET_TMP" "$BRIEFING_FOCUS_TMP"

if [ -z "$BRIEFING_MARKET_TEXT" ] || [ -z "$BRIEFING_FOCUS_TEXT" ]; then
  echo "[futures-briefing] empty split briefing text for symbol '$SYMBOL'"
  exit 1
fi

if [ "$SEND_NOTIFY" = false ]; then
  echo "[futures-briefing] notify=off"
  echo "[futures-briefing] symbol=$SYMBOL"
  echo ""
  printf '%s\n\n%s\n' "$BRIEFING_MARKET_TEXT" "$BRIEFING_FOCUS_TEXT"
  exit 0
fi

send_feishu_text() {
  local label="$1"
  local text="$2"

  local body
  body="$($PYTHON_BIN - "$text" <<'PY'
import json
import sys

print(json.dumps({"msg_type": "text", "content": {"text": sys.argv[1]}}, ensure_ascii=False))
PY
)"

  local feishu_tmp
  feishu_tmp="$(mktemp)"
  local feishu_code
  feishu_code="$(curl -sS -o "$feishu_tmp" -w "%{http_code}" -X POST "$FEISHU_WEBHOOK_URL" -H "Content-Type: application/json" -d "$body" || true)"

  if [ "$feishu_code" -lt 200 ] || [ "$feishu_code" -ge 300 ]; then
    local feishu_resp
    feishu_resp="$(cat "$feishu_tmp")"
    rm -f "$feishu_tmp"
    echo "[futures-briefing] feishu push failed ($label, $feishu_code): $feishu_resp" >&2
    return 1
  fi

  local feishu_result
  feishu_result="$($PYTHON_BIN - "$feishu_tmp" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
try:
    data = json.loads(text)
except Exception:
    print(text.strip() or "unknown response")
    raise SystemExit(0)
code = data.get("code")
if code not in (0, "0", None):
    print(f"code={code}, msg={data.get('msg')}")
    raise SystemExit(2)
print(f"code={code}, msg={data.get('msg', 'ok')}")
PY
)" || {
    rm -f "$feishu_tmp"
    echo "[futures-briefing] feishu push rejected ($label): $feishu_result" >&2
    return 1
  }

  rm -f "$feishu_tmp"
  printf '%s' "$feishu_result"
}

FEISHU_RESULT_MARKET="$(send_feishu_text "market" "$BRIEFING_MARKET_TEXT")" || exit 1
FEISHU_RESULT_FOCUS="$(send_feishu_text "focus" "$BRIEFING_FOCUS_TEXT")" || exit 1

echo "[futures-briefing] symbol=$SYMBOL"
echo "[futures-briefing] feishu_market=$FEISHU_RESULT_MARKET"
echo "[futures-briefing] feishu_focus=$FEISHU_RESULT_FOCUS"
echo ""
printf '%s\n\n%s\n' "$BRIEFING_MARKET_TEXT" "$BRIEFING_FOCUS_TEXT"
