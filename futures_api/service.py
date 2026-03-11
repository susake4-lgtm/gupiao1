import math
import re
from datetime import datetime, timezone
from json import JSONDecodeError
from typing import Any

from .errors import EmptyDataError, InvalidRequestError, UpstreamFetchError
from .storage import (
    load_latest_snapshot,
    normalize_alias,
    normalize_symbol,
    save_latest_snapshot,
    save_report_markdown,
)


# Common aliases for single-futures queries (e.g. "大豆", "黄金")
ALIAS_TO_SYMBOLS: dict[str, list[str]] = {
    "大豆": ["a0"],
    "黄豆": ["a0"],
    "豆一": ["a0"],
    "a": ["a0"],

    "豆2": ["b0"],
    "豆二": ["b0"],
    "b": ["b0"],

    "豆粕": ["m0"],
    "m": ["m0"],

    "豆油": ["y0"],
    "y": ["y0"],

    "玉米": ["c0"],
    "c": ["c0"],

    "螺纹钢": ["rb0"],
    "螺纹": ["rb0"],
    "rb": ["rb0"],

    "铁矿石": ["i0"],
    "铁矿": ["i0"],
    "i": ["i0"],

    "焦煤": ["jm0"],
    "jm": ["jm0"],

    "焦炭": ["j0"],
    "j": ["j0"],

    "pta": ["ta0"],
    "ta": ["ta0"],

    "原油": ["sc0"],
    "沪原油": ["sc0"],
    "sc": ["sc0"],
    "crude": ["sc0"],

    "黄金": ["au0"],
    "沪金": ["au0"],
    "金": ["au0"],
    "au": ["au0"],
    "gold": ["au0"],
    "xau": ["au0"],

    "白银": ["ag0"],
    "沪银": ["ag0"],
    "银": ["ag0"],
    "ag": ["ag0"],
    "silver": ["ag0"],

    "铜": ["cu0"],
    "沪铜": ["cu0"],
    "cu": ["cu0"],
    "copper": ["cu0"],

    "铝": ["al0"],
    "沪铝": ["al0"],
    "al": ["al0"],
    "aluminum": ["al0"],
}


DEFAULT_MARKET_FOCUS_SYMBOLS: list[str] = [
    "rb0",
    "i0",
    "j0",
    "jm0",
    "a0",
    "m0",
    "y0",
    "c0",
    "ta0",
    "sc0",
    "au0",
    "ag0",
    "cu0",
    "al0",
]


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _to_jsonable(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, (str, int, bool)):
        return value
    if isinstance(value, float):
        if math.isnan(value) or math.isinf(value):
            return None
        return value
    if isinstance(value, dict):
        return {str(k): _to_jsonable(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_to_jsonable(item) for item in value]

    if hasattr(value, "item"):
        try:
            return _to_jsonable(value.item())
        except Exception:
            pass

    if hasattr(value, "isoformat"):
        try:
            return value.isoformat()
        except Exception:
            pass

    return str(value)


def _format_exception_diagnostic(exc: Exception) -> str:
    exc_type = type(exc).__name__
    details = str(exc).strip() or "no error details"
    return f"{exc_type}: {details}"


def _get_akshare_module():
    try:
        import akshare as ak  # type: ignore
    except Exception as exc:
        diagnostic = _format_exception_diagnostic(exc)
        raise UpstreamFetchError(f"上游行情源异常：AkShare 模块不可用（诊断：{diagnostic}）") from exc
    return ak


def _describe_upstream_exception(exc: Exception) -> str:
    diagnostic = _format_exception_diagnostic(exc)

    if isinstance(exc, JSONDecodeError):
        return f"AkShare 返回空响应或非预期响应（诊断：{diagnostic}）"

    return f"上游返回非预期响应（诊断：{diagnostic}）"


def _fetch_realtime_dataframe() -> Any:
    ak = _get_akshare_module()
    try:
        realtime_df = ak.futures_zh_realtime()
    except Exception as exc:
        diagnostic = _describe_upstream_exception(exc)
        raise UpstreamFetchError(f"上游行情源异常：{diagnostic}") from exc

    if realtime_df is None or getattr(realtime_df, "empty", True):
        raise EmptyDataError("AkShare 返回空数据：futures_zh_realtime 数据集为空")
    return realtime_df


def _records_from_dataframe(df: Any, dataset_name: str = "AkShare 数据集", tail_size: int = 5) -> list[dict[str, Any]]:
    if df is None or getattr(df, "empty", True):
        raise EmptyDataError(f"AkShare 返回空数据：{dataset_name}")

    records = df.tail(tail_size).to_dict(orient="records")
    normalized_records = [_to_jsonable(record) for record in records]
    if not normalized_records:
        raise EmptyDataError(f"AkShare 返回空数据：{dataset_name}")
    return normalized_records


def _extract_symbol_from_record(record: dict[str, Any]) -> str | None:
    lowered_keys = {str(k).lower(): k for k in record.keys()}
    for candidate in ["symbol", "合约", "代码", "contract"]:
        actual_key = lowered_keys.get(candidate)
        if actual_key is None:
            continue
        value = str(record.get(actual_key, "")).strip()
        if not value:
            continue
        try:
            return normalize_symbol(value)
        except InvalidRequestError:
            continue
    return None


def _symbol_name_hint(symbol: str) -> str | None:
    normalized = symbol.strip().lower()
    if not normalized:
        return None

    match = re.match(r"^([a-z]+)(\d+|0)$", normalized)
    if not match:
        return None

    code = match.group(1)
    maturity = match.group(2)

    base_name = {
        "ta": "精对苯二甲酸(PTA)",
        "a": "黄大豆1号(豆一)",
        "b": "黄大豆2号(豆二)",
        "m": "豆粕",
        "y": "豆油",
        "c": "玉米",
        "rb": "螺纹钢",
        "i": "铁矿石",
        "jm": "焦煤",
        "j": "焦炭",
        "sc": "原油",
        "au": "沪金",
        "ag": "沪银",
        "cu": "沪铜",
        "al": "沪铝",
    }.get(code)

    if not base_name:
        return None

    if maturity == "0":
        return f"{base_name}连续"
    if len(maturity) == 4:
        return f"{base_name}{maturity}合约"
    return base_name


def _display_symbol_label(symbol: str, record_name: Any | None = None) -> str:
    hint = _symbol_name_hint(symbol)
    if hint:
        return f"{symbol}（{hint}）"

    if isinstance(record_name, str):
        name = record_name.strip()
        if name:
            return f"{symbol}（{name}）"

    return symbol


def _match_realtime_symbol(df: Any, symbol: str) -> dict[str, Any]:
    if df is None or getattr(df, "empty", True):
        raise EmptyDataError("AkShare 返回空数据：futures_zh_realtime 数据集为空")

    records = df.to_dict(orient="records")
    if not records:
        raise EmptyDataError("AkShare 返回空数据：futures_zh_realtime 数据集为空")

    normalized_symbol = symbol.strip().lower()
    candidate_keys = ["symbol", "合约", "代码", "品种", "contract", "name"]

    for record in records:
        lowered_keys = {str(k).lower(): k for k in record.keys()}
        for candidate in candidate_keys:
            actual_key = lowered_keys.get(candidate)
            if actual_key is None:
                continue
            value = str(record.get(actual_key, "")).strip().lower()
            if value == normalized_symbol:
                return _to_jsonable(record)

    for record in records:
        for value in record.values():
            if isinstance(value, str) and value.strip().lower() == normalized_symbol:
                return _to_jsonable(record)

    raise EmptyDataError(f"symbol '{symbol}' not found in AkShare realtime data")


def _discover_symbol_from_realtime_alias(df: Any, alias: str) -> str | None:
    records = df.to_dict(orient="records")
    lowered_alias = alias.strip().lower()
    if not lowered_alias:
        return None

    candidate_keys = ["name", "品种", "合约", "symbol", "代码", "contract"]
    for record in records:
        lowered_keys = {str(k).lower(): k for k in record.keys()}
        for candidate in candidate_keys:
            actual_key = lowered_keys.get(candidate)
            if actual_key is None:
                continue
            value = str(record.get(actual_key, "")).strip().lower()
            if lowered_alias in value:
                symbol = _extract_symbol_from_record(record)
                if symbol:
                    return symbol
    return None


def _candidate_symbols_from_alias(alias: str) -> list[str]:
    return ALIAS_TO_SYMBOLS.get(alias, [])


def _aliases_for_symbol(symbol: str) -> list[str]:
    aliases = [symbol]
    for alias, candidates in ALIAS_TO_SYMBOLS.items():
        if symbol in candidates and alias not in aliases:
            aliases.append(alias)
    return aliases


def _merge_aliases(requested: str, resolved_symbol: str) -> list[str]:
    aliases = _aliases_for_symbol(resolved_symbol)
    normalized_requested = requested.strip().lower()
    if normalized_requested and normalized_requested not in aliases:
        aliases.insert(0, normalized_requested)
    return aliases


def _resolve_requested_symbol(requested: str, realtime_df: Any) -> tuple[str, str, list[str], bool]:
    requested_text = requested.strip()
    if not requested_text:
        raise InvalidRequestError("symbol is required")

    try:
        symbol = normalize_symbol(requested_text)
        return symbol, requested_text, _merge_aliases(requested_text, symbol), False
    except InvalidRequestError:
        pass

    alias = normalize_alias(requested_text)
    candidates = _candidate_symbols_from_alias(alias)
    if candidates:
        symbol = candidates[0]
        return symbol, requested_text, _merge_aliases(requested_text, symbol), False

    discovered_symbol = _discover_symbol_from_realtime_alias(realtime_df, alias)
    if discovered_symbol:
        return discovered_symbol, requested_text, _merge_aliases(requested_text, discovered_symbol), False

    raise EmptyDataError(f"symbol alias '{requested_text}' not found in AkShare realtime data")


def _resolve_symbol_for_latest(requested: str) -> tuple[str, str, list[str]]:
    requested_text = requested.strip()
    if not requested_text:
        raise InvalidRequestError("symbol is required")

    try:
        symbol = normalize_symbol(requested_text)
        return symbol, requested_text, _merge_aliases(requested_text, symbol)
    except InvalidRequestError:
        pass

    alias = normalize_alias(requested_text)
    candidates = _candidate_symbols_from_alias(alias)
    if not candidates:
        raise InvalidRequestError(f"symbol alias '{requested_text}' is not configured")

    symbol = candidates[0]
    return symbol, requested_text, _merge_aliases(requested_text, symbol)


def _fetch_daily_tail(symbol: str) -> list[dict[str, Any]]:
    ak = _get_akshare_module()
    try:
        daily_df = ak.futures_zh_daily_sina(symbol=symbol)
    except Exception as exc:
        diagnostic = _describe_upstream_exception(exc)
        raise UpstreamFetchError(f"上游行情源异常：AkShare futures_zh_daily_sina 获取失败（{symbol}）；{diagnostic}") from exc
    return _records_from_dataframe(daily_df, f"futures_zh_daily_sina('{symbol}') 返回空数据")


def _fetch_minute_tail(symbol: str) -> list[dict[str, Any]]:
    ak = _get_akshare_module()
    try:
        minute_df = ak.futures_zh_minute_sina(symbol=symbol, period="30")
    except Exception as exc:
        diagnostic = _describe_upstream_exception(exc)
        raise UpstreamFetchError(f"上游行情源异常：AkShare futures_zh_minute_sina 获取失败（{symbol}）；{diagnostic}") from exc
    return _records_from_dataframe(minute_df, f"futures_zh_minute_sina('{symbol}', period='30') 返回空数据")


def _pick_value(record: dict[str, Any], keys: list[str]) -> Any:
    lowered = {str(k).lower(): k for k in record.keys()}
    for key in keys:
        actual_key = lowered.get(key.lower())
        if actual_key is not None:
            return record.get(actual_key)
    return None


def _to_float(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        number = float(value)
        if math.isnan(number) or math.isinf(number):
            return None
        return number
    if isinstance(value, str):
        text = value.strip().replace(",", "")
        if not text:
            return None
        try:
            number = float(text)
        except ValueError:
            return None
        if math.isnan(number) or math.isinf(number):
            return None
        return number
    return None


def _safe_pct(current: float | None, previous: float | None) -> float | None:
    if current is None or previous in (None, 0):
        return None
    return round((current - previous) / previous * 100, 4)


def _normalize_realtime_records(df: Any) -> list[dict[str, Any]]:
    records = df.to_dict(orient="records")
    normalized: list[dict[str, Any]] = []

    for row in records:
        symbol = _extract_symbol_from_record(row)
        if not symbol:
            continue

        record_name = _pick_value(row, ["name", "品种", "合约名称"])

        normalized.append(
            {
                "symbol": symbol,
                "symbol_label": _display_symbol_label(symbol, record_name),
                "symbol_note": _symbol_name_hint(symbol),
                "name": record_name,
                "exchange": _pick_value(row, ["exchange", "交易所"]),
                "last_price": _to_float(_pick_value(row, ["trade", "最新价", "close", "现价"])),
                "change_percent": _to_float(_pick_value(row, ["changepercent", "涨跌幅"])),
                "volume": _to_float(_pick_value(row, ["volume", "成交量"])),
                "position": _to_float(_pick_value(row, ["position", "持仓量"])),
            }
        )

    return [_to_jsonable(item) for item in normalized]


def _build_market_overview(df: Any, focus_symbol: str) -> dict[str, Any]:
    normalized = _normalize_realtime_records(df)
    if not normalized:
        return {
            "contracts": 0,
            "sample_scope": "本次 futures_zh_realtime 返回并可解析的合约样本（非全市场全量）",
            "breadth": {"up": 0, "down": 0, "flat": 0},
            "average_change_percent": None,
            "market_tone": "数据不足",
            "top_gainers": [],
            "top_losers": [],
            "active_by_volume": [],
            "focus_quotes": [],
        }

    changes = [item["change_percent"] for item in normalized if item.get("change_percent") is not None]
    up = len([value for value in changes if isinstance(value, (int, float)) and value > 0])
    down = len([value for value in changes if isinstance(value, (int, float)) and value < 0])
    flat = len(changes) - up - down

    average_change = None
    if changes:
        average_change = round(sum(float(value) for value in changes) / len(changes), 4)

    if up > down * 1.2:
        market_tone = "偏强"
    elif down > up * 1.2:
        market_tone = "偏弱"
    else:
        market_tone = "分化"

    with_change = [item for item in normalized if item.get("change_percent") is not None]
    top_gainers = sorted(with_change, key=lambda item: float(item["change_percent"]), reverse=True)[:5]
    top_losers = sorted(with_change, key=lambda item: float(item["change_percent"]))[:5]

    with_volume = [item for item in normalized if item.get("volume") is not None]
    active_by_volume = sorted(with_volume, key=lambda item: float(item["volume"]), reverse=True)[:5]

    focus_set = {focus_symbol, *DEFAULT_MARKET_FOCUS_SYMBOLS}
    quote_by_symbol = {item["symbol"]: item for item in normalized if isinstance(item.get("symbol"), str)}
    focus_quotes = [quote_by_symbol[symbol] for symbol in focus_set if symbol in quote_by_symbol]
    focus_quotes = sorted(
        focus_quotes,
        key=lambda item: (
            0 if item.get("symbol") == focus_symbol else 1,
            str(item.get("symbol", "")),
        ),
    )

    return {
        "contracts": len(normalized),
        "sample_scope": "本次 futures_zh_realtime 返回并可解析的合约样本（非全市场全量）",
        "breadth": {"up": up, "down": down, "flat": flat},
        "average_change_percent": average_change,
        "market_tone": market_tone,
        "top_gainers": top_gainers,
        "top_losers": top_losers,
        "active_by_volume": active_by_volume,
        "focus_quotes": focus_quotes,
    }


def _fetch_news_tail(limit: int = 8) -> list[dict[str, Any]]:
    ak = _get_akshare_module()
    try:
        news_df = ak.futures_news_shmet(symbol="全部")
    except Exception:
        return []

    if news_df is None or getattr(news_df, "empty", True):
        return []

    records = news_df.tail(limit).to_dict(orient="records")
    normalized_news: list[dict[str, Any]] = []

    for row in records:
        normalized_news.append(
            {
                "time": _pick_value(row, ["发布时间", "时间", "datetime", "日期"]),
                "title": _pick_value(row, ["标题", "title", "内容", "摘要"]),
                "source": _pick_value(row, ["来源", "source"]),
                "url": _pick_value(row, ["链接", "url", "网址"]),
            }
        )

    return [_to_jsonable(item) for item in normalized_news]


def _build_summary(
    symbol: str,
    realtime: dict[str, Any],
    daily_tail: list[dict[str, Any]],
    minute_tail: list[dict[str, Any]],
    market_overview: dict[str, Any],
    news_tail: list[dict[str, Any]],
) -> dict[str, Any]:
    latest_daily = daily_tail[-1] if daily_tail else {}
    prev_daily = daily_tail[-2] if len(daily_tail) >= 2 else {}

    latest_daily_close = _to_float(_pick_value(latest_daily, ["close", "收盘", "收盘价"]))
    prev_daily_close = _to_float(_pick_value(prev_daily, ["close", "收盘", "收盘价"]))

    latest_minute = minute_tail[-1] if minute_tail else {}
    minute_closes = [
        close
        for close in (_to_float(_pick_value(row, ["close", "收盘", "收盘价"])) for row in minute_tail)
        if close is not None
    ]

    latest_30m_close = _to_float(_pick_value(latest_minute, ["close", "收盘", "收盘价"]))
    min_close_5 = min(minute_closes) if minute_closes else None
    max_close_5 = max(minute_closes) if minute_closes else None

    breadth = market_overview.get("breadth", {}) if isinstance(market_overview, dict) else {}
    up_count = int(breadth.get("up", 0)) if isinstance(breadth, dict) else 0
    down_count = int(breadth.get("down", 0)) if isinstance(breadth, dict) else 0

    key_points: list[str] = []
    symbol_label = _display_symbol_label(symbol, _pick_value(realtime, ["name", "品种", "合约名称"]))
    key_points.append(
        f"{symbol_label}日线最新收盘 {latest_daily_close if latest_daily_close is not None else 'N/A'}，较前一日变化 {(_safe_pct(latest_daily_close, prev_daily_close) if latest_daily_close is not None else None) if _safe_pct(latest_daily_close, prev_daily_close) is not None else 'N/A'}%。"
    )

    if latest_30m_close is not None and min_close_5 is not None and max_close_5 is not None:
        key_points.append(f"30分钟近5根区间 {min_close_5} ~ {max_close_5}，最新 {latest_30m_close}。")

    if isinstance(market_overview, dict) and market_overview:
        sample_scope = market_overview.get("sample_scope") or "本次抓取样本（非全市场全量）"
        key_points.append(
            f"{sample_scope}：{market_overview.get('contracts', 0)} 个合约，上涨 {up_count}、下跌 {down_count}，市场情绪 {market_overview.get('market_tone', 'N/A')}。"
        )

    if news_tail:
        latest_news = news_tail[-1]
        key_points.append(f"最新行业资讯：{latest_news.get('title') or 'N/A'}。")

    return {
        "symbol": symbol,
        "realtime": {
            "name": _pick_value(realtime, ["name", "品种", "合约名称"]),
            "exchange": _pick_value(realtime, ["exchange", "交易所"]),
            "last_price": _to_float(_pick_value(realtime, ["trade", "最新价", "close", "现价"])),
            "change_percent": _to_float(_pick_value(realtime, ["changepercent", "涨跌幅"])),
            "volume": _to_float(_pick_value(realtime, ["volume", "成交量"])),
            "position": _to_float(_pick_value(realtime, ["position", "持仓量"])),
            "tick_time": _pick_value(realtime, ["ticktime", "时间"]),
            "trade_date": _pick_value(realtime, ["tradedate", "日期", "交易日期"]),
        },
        "daily": {
            "bars": len(daily_tail),
            "latest_date": _pick_value(latest_daily, ["date", "日期", "交易日期"]),
            "latest_close": latest_daily_close,
            "change_pct_vs_prev": _safe_pct(latest_daily_close, prev_daily_close),
            "latest_high": _to_float(_pick_value(latest_daily, ["high", "最高", "最高价"])),
            "latest_low": _to_float(_pick_value(latest_daily, ["low", "最低", "最低价"])),
        },
        "minute_30m": {
            "bars": len(minute_tail),
            "latest_time": _pick_value(latest_minute, ["datetime", "time", "时间", "日期"]),
            "latest_close": latest_30m_close,
            "max_close_5": max_close_5,
            "min_close_5": min_close_5,
        },
        "market_breadth": {
            "contracts": market_overview.get("contracts") if isinstance(market_overview, dict) else None,
            "up": up_count,
            "down": down_count,
            "flat": int(breadth.get("flat", 0)) if isinstance(breadth, dict) else 0,
            "average_change_percent": market_overview.get("average_change_percent")
            if isinstance(market_overview, dict)
            else None,
            "market_tone": market_overview.get("market_tone") if isinstance(market_overview, dict) else None,
        },
        "news_count": len(news_tail),
        "key_points": key_points,
    }


def _records_to_markdown_table(records: list[dict[str, Any]]) -> str:
    if not records:
        return "_No data_"

    columns = list(records[0].keys())
    header = "| " + " | ".join(columns) + " |"
    separator = "| " + " | ".join(["---"] * len(columns)) + " |"

    lines = [header, separator]
    for row in records:
        cells = []
        for column in columns:
            text = str(row.get(column, "")).replace("\n", " ").replace("|", "\\|")
            cells.append(text)
        lines.append("| " + " | ".join(cells) + " |")

    return "\n".join(lines)


def _render_pct_from_ratio(value: Any) -> str:
    number = _to_float(value)
    if number is None:
        return "N/A"
    return f"{number * 100:.2f}%"


def _render_pct(value: Any, digits: int = 4) -> str:
    number = _to_float(value)
    if number is None:
        return "N/A"
    return f"{number:.{digits}f}%"


def _render_decimal(value: Any, digits: int = 2) -> str:
    number = _to_float(value)
    if number is None:
        return "N/A"
    return f"{number:.{digits}f}"


def _build_briefing(snapshot: dict[str, Any]) -> dict[str, Any]:
    summary = snapshot.get("summary", {}) if isinstance(snapshot.get("summary"), dict) else {}
    market = snapshot.get("market_overview", {}) if isinstance(snapshot.get("market_overview"), dict) else {}
    news_tail = snapshot.get("news_tail", []) if isinstance(snapshot.get("news_tail"), list) else []

    sample_scope = market.get("sample_scope") or "本次抓取样本（非全市场全量）"
    breadth = market.get("breadth", {}) if isinstance(market.get("breadth"), dict) else {}

    top_gainers = market.get("top_gainers", []) if isinstance(market.get("top_gainers"), list) else []
    top_losers = market.get("top_losers", []) if isinstance(market.get("top_losers"), list) else []

    symbol = str(snapshot.get("symbol", "")).strip().lower()
    realtime = snapshot.get("realtime", {}) if isinstance(snapshot.get("realtime"), dict) else {}
    focus_label = _display_symbol_label(symbol, _pick_value(realtime, ["name", "品种", "合约名称"])) if symbol else "N/A"

    key_points = summary.get("key_points", []) if isinstance(summary.get("key_points"), list) else []
    daily = summary.get("daily", {}) if isinstance(summary.get("daily"), dict) else {}
    minute = summary.get("minute_30m", {}) if isinstance(summary.get("minute_30m"), dict) else {}

    market_lines = [
        "【今日期货大盘汇报】",
        f"- 市场情绪：{market.get('market_tone', 'N/A')}（样本 {market.get('contracts', 0)} 个）",
        f"- 市场宽度：上涨 {breadth.get('up', 0)} / 下跌 {breadth.get('down', 0)} / 平 {breadth.get('flat', 0)}",
        f"- 样本范围：{sample_scope}",
        f"- 样本平均涨跌幅：{_render_pct_from_ratio(market.get('average_change_percent'))}",
        "- 领涨Top3：",
    ]

    if top_gainers:
        for idx, item in enumerate(top_gainers[:3], start=1):
            market_lines.append(
                f"  {idx}) {item.get('symbol_label') or item.get('symbol', 'N/A')} {_render_pct_from_ratio(item.get('change_percent'))}"
            )
    else:
        market_lines.append("  1) 暂无可用数据")

    market_lines.append("- 领跌Top3：")
    if top_losers:
        for idx, item in enumerate(top_losers[:3], start=1):
            market_lines.append(
                f"  {idx}) {item.get('symbol_label') or item.get('symbol', 'N/A')} {_render_pct_from_ratio(item.get('change_percent'))}"
            )
    else:
        market_lines.append("  1) 暂无可用数据")

    focus_lines = [
        "【关注品种汇报】",
        f"- 关注标的：{focus_label}",
        f"- 日线：最新收盘 {_render_decimal(daily.get('latest_close'))}，较前日 {_render_pct(daily.get('change_pct_vs_prev'))}",
        f"- 30m：最新 {_render_decimal(minute.get('latest_close'))}，近5根区间 {_render_decimal(minute.get('min_close_5'))} ~ {_render_decimal(minute.get('max_close_5'))}",
    ]

    if key_points:
        focus_lines.append(f"- 当前结论：{key_points[0]}")
    if len(key_points) > 1:
        focus_lines.append(f"- 结构补充：{key_points[1]}")
    if news_tail:
        latest_news = news_tail[-1]
        focus_lines.append(f"- 最新资讯：{latest_news.get('title') or 'N/A'}")

    observation_lines = [
        "【下一步观察点】",
        "- 观察领涨是否从单一链条扩散到更多品种，若扩散则情绪更稳。",
        "- 关注标的30m若跌破近5根区间下沿，短线强度可能回落。",
        "- 跟踪晚间宏观/能源新闻是否改变次日开盘风险偏好。",
    ]

    text = "\n".join(market_lines + [""] + focus_lines + [""] + observation_lines)

    return {
        "version": "v1",
        "sections": {
            "market_daily": market_lines,
            "focus_symbol": focus_lines,
            "next_watch": observation_lines,
        },
        "text": text,
    }


def _render_report(snapshot: dict[str, Any]) -> str:
    realtime = snapshot.get("realtime", {})
    daily_tail = snapshot.get("daily_tail", [])
    minute_tail = snapshot.get("minute_tail", [])
    summary = snapshot.get("summary", {}) if isinstance(snapshot.get("summary"), dict) else {}
    market_overview = snapshot.get("market_overview", {}) if isinstance(snapshot.get("market_overview"), dict) else {}
    news_tail = snapshot.get("news_tail", []) if isinstance(snapshot.get("news_tail"), list) else []
    briefing = snapshot.get("briefing", {}) if isinstance(snapshot.get("briefing"), dict) else {}

    breadth = market_overview.get("breadth", {}) if isinstance(market_overview.get("breadth"), dict) else {}

    lines = [
        f"# Futures Report - {snapshot.get('symbol', '')}",
        "",
        f"- Requested: {snapshot.get('requested', '')}",
        f"- Generated at: {snapshot.get('ts', '')}",
        "",
        "## 关键结论",
    ]

    key_points = summary.get("key_points", []) if isinstance(summary, dict) else []
    if isinstance(key_points, list) and key_points:
        for point in key_points:
            lines.append(f"- {point}")
    else:
        lines.append("- 暂无关键结论")

    briefing_text = str(briefing.get("text", "")).strip()
    if briefing_text:
        lines.extend(
            [
                "",
                "## 标准汇报（分析师视角）",
                "",
                briefing_text,
            ]
        )

    lines.extend(
        [
            "",
            "## Realtime Summary",
        ]
    )

    if isinstance(realtime, dict) and realtime:
        for key, value in realtime.items():
            lines.append(f"- {key}: {value}")
    else:
        lines.append("- No realtime data")

    lines.extend(
        [
            "",
            "## Market Overview",
            f"- sample_scope: {market_overview.get('sample_scope', '本次抓取样本（非全市场全量）')}",
            f"- contracts: {market_overview.get('contracts', 0)}",
            f"- breadth(up/down/flat): {breadth.get('up', 0)}/{breadth.get('down', 0)}/{breadth.get('flat', 0)}",
            f"- average_change_percent: {market_overview.get('average_change_percent')}",
            f"- market_tone: {market_overview.get('market_tone')}",
            "",
            "### Top Gainers",
            _records_to_markdown_table(market_overview.get("top_gainers", []) if isinstance(market_overview, dict) else []),
            "",
            "### Top Losers",
            _records_to_markdown_table(market_overview.get("top_losers", []) if isinstance(market_overview, dict) else []),
            "",
            "### Active By Volume",
            _records_to_markdown_table(market_overview.get("active_by_volume", []) if isinstance(market_overview, dict) else []),
            "",
            "### Focus Quotes",
            _records_to_markdown_table(market_overview.get("focus_quotes", []) if isinstance(market_overview, dict) else []),
            "",
            "## Futures News Tail",
            _records_to_markdown_table(news_tail),
            "",
            "## Daily Tail",
            _records_to_markdown_table(daily_tail if isinstance(daily_tail, list) else []),
            "",
            "## Minute Tail (30m)",
            _records_to_markdown_table(minute_tail if isinstance(minute_tail, list) else []),
            "",
        ]
    )

    return "\n".join(lines)


def run_once(symbol: str) -> dict[str, Any]:
    realtime_df = _fetch_realtime_dataframe()
    normalized_symbol, requested_text, aliases, strict_realtime = _resolve_requested_symbol(symbol, realtime_df)

    try:
        realtime = _match_realtime_symbol(realtime_df, normalized_symbol)
    except EmptyDataError:
        if strict_realtime:
            raise
        realtime = {
            "symbol": normalized_symbol,
            "message": f"symbol '{normalized_symbol}' not found in realtime feed, used daily/minute data",
        }

    daily_tail = _fetch_daily_tail(normalized_symbol)
    minute_tail = _fetch_minute_tail(normalized_symbol)
    market_overview = _build_market_overview(realtime_df, normalized_symbol)
    news_tail = _fetch_news_tail()

    snapshot = {
        "symbol": normalized_symbol,
        "requested": requested_text,
        "aliases": aliases,
        "ts": _now_iso(),
        "realtime": realtime,
        "daily_tail": daily_tail,
        "minute_tail": minute_tail,
        "market_overview": market_overview,
        "news_tail": news_tail,
    }

    snapshot["summary"] = _build_summary(
        normalized_symbol,
        realtime if isinstance(realtime, dict) else {},
        daily_tail,
        minute_tail,
        market_overview,
        news_tail,
    )
    snapshot["briefing"] = _build_briefing(snapshot)

    snapshot["saved_path"] = save_latest_snapshot(normalized_symbol, snapshot)
    report_content = _render_report(snapshot)
    snapshot["report_path"] = save_report_markdown(normalized_symbol, report_content)
    snapshot["saved_path"] = save_latest_snapshot(normalized_symbol, snapshot)
    return snapshot


def get_latest(symbol: str) -> dict[str, Any]:
    normalized_symbol, requested_text, aliases = _resolve_symbol_for_latest(symbol)
    snapshot = load_latest_snapshot(normalized_symbol)

    if not isinstance(snapshot.get("requested"), str):
        snapshot["requested"] = requested_text
    if not isinstance(snapshot.get("aliases"), list) or not snapshot.get("aliases"):
        snapshot["aliases"] = aliases
    if not isinstance(snapshot.get("market_overview"), dict):
        snapshot["market_overview"] = {}
    if not isinstance(snapshot.get("news_tail"), list):
        snapshot["news_tail"] = []

    if not isinstance(snapshot.get("summary"), dict) or not snapshot.get("summary"):
        snapshot["summary"] = _build_summary(
            normalized_symbol,
            snapshot.get("realtime", {}) if isinstance(snapshot.get("realtime"), dict) else {},
            snapshot.get("daily_tail", []) if isinstance(snapshot.get("daily_tail"), list) else [],
            snapshot.get("minute_tail", []) if isinstance(snapshot.get("minute_tail"), list) else [],
            snapshot.get("market_overview", {}) if isinstance(snapshot.get("market_overview"), dict) else {},
            snapshot.get("news_tail", []) if isinstance(snapshot.get("news_tail"), list) else [],
        )

    if not isinstance(snapshot.get("briefing"), dict) or not snapshot.get("briefing"):
        snapshot["briefing"] = _build_briefing(snapshot)

    return snapshot
