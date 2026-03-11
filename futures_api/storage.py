import json
import os
import re
from pathlib import Path
from typing import Any

from .errors import DataNotFoundError, InvalidRequestError, StorageError


ROOT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_DATA_DIR = ROOT_DIR / "data" / "futures"
SYMBOL_PATTERN = re.compile(r"^[a-zA-Z0-9_-]+$")
ALIAS_PATTERN = re.compile(r"^[a-zA-Z0-9_\-\u4e00-\u9fff]+$")


def normalize_symbol(symbol: str) -> str:
    normalized = symbol.strip().lower()
    if not normalized:
        raise InvalidRequestError("symbol is required")
    if not SYMBOL_PATTERN.fullmatch(normalized):
        raise InvalidRequestError("symbol contains invalid characters")
    return normalized


def normalize_alias(alias: str) -> str:
    normalized = alias.strip().lower()
    if not normalized:
        raise InvalidRequestError("alias is required")
    if not ALIAS_PATTERN.fullmatch(normalized):
        raise InvalidRequestError("alias contains invalid characters")
    return normalized


def _resolve_data_dir() -> Path:
    configured = os.getenv("FUTURES_DATA_DIR", "").strip()
    if configured:
        path = Path(configured).expanduser()
        if not path.is_absolute():
            path = ROOT_DIR / path
    else:
        path = DEFAULT_DATA_DIR

    path.mkdir(parents=True, exist_ok=True)
    return path


def _relative_to_repo(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT_DIR))
    except ValueError:
        return str(path)


def latest_file_path(symbol: str) -> Path:
    return _resolve_data_dir() / f"latest_{normalize_symbol(symbol)}.json"


def report_file_path(symbol: str) -> Path:
    return _resolve_data_dir() / f"report_{normalize_symbol(symbol)}.md"


def save_latest_snapshot(symbol: str, payload: dict[str, Any]) -> str:
    path = latest_file_path(symbol)
    temp_path = path.with_suffix(".json.tmp")
    try:
        temp_path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        temp_path.replace(path)
    except Exception as exc:
        raise StorageError(f"failed to persist latest snapshot: {exc}") from exc
    return _relative_to_repo(path)


def load_latest_snapshot(symbol: str) -> dict[str, Any]:
    path = latest_file_path(symbol)
    if not path.exists():
        raise DataNotFoundError(f"latest snapshot not found for symbol '{normalize_symbol(symbol)}'")

    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise StorageError(f"failed to read latest snapshot: {exc}") from exc


def save_report_markdown(symbol: str, content: str) -> str:
    path = report_file_path(symbol)
    try:
        path.write_text(content, encoding="utf-8")
    except Exception as exc:
        raise StorageError(f"failed to persist markdown report: {exc}") from exc
    return _relative_to_repo(path)
