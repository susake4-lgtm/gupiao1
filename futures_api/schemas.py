from typing import Any

from pydantic import BaseModel, Field, field_validator


class HealthResponse(BaseModel):
    status: str
    timestamp: str


class RunOnceRequest(BaseModel):
    symbol: str = Field(min_length=1, max_length=32)

    @field_validator("symbol")
    @classmethod
    def normalize_symbol(cls, value: str) -> str:
        symbol = value.strip().lower()
        if not symbol:
            raise ValueError("symbol is required")
        return symbol


class FuturesSnapshot(BaseModel):
    symbol: str
    requested: str | None = None
    aliases: list[str] = Field(default_factory=list)
    ts: str
    realtime: dict[str, Any]
    daily_tail: list[dict[str, Any]]
    minute_tail: list[dict[str, Any]]
    market_overview: dict[str, Any] = Field(default_factory=dict)
    news_tail: list[dict[str, Any]] = Field(default_factory=list)
    summary: dict[str, Any] = Field(default_factory=dict)
    briefing: dict[str, Any] = Field(default_factory=dict)
    saved_path: str
    report_path: str


class ErrorResponse(BaseModel):
    message: str
