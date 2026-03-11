from datetime import datetime, timezone

from fastapi import FastAPI, Query

from .errors import register_exception_handlers
from .schemas import ErrorResponse, FuturesSnapshot, HealthResponse, RunOnceRequest
from .service import get_latest, run_once


app = FastAPI(
    title="Futures API",
    description="Independent futures API service for AkShare run-once and latest snapshot retrieval.",
    version="0.1.0",
)

register_exception_handlers(app)


@app.get(
    "/api/futures/health",
    response_model=HealthResponse,
    tags=["Health"],
    summary="Health check",
)
async def health_check() -> HealthResponse:
    return HealthResponse(status="ok", timestamp=datetime.now(timezone.utc).isoformat())


@app.post(
    "/api/futures/run-once",
    response_model=FuturesSnapshot,
    responses={400: {"model": ErrorResponse}, 404: {"model": ErrorResponse}, 502: {"model": ErrorResponse}},
    tags=["Futures"],
    summary="Fetch futures data once and persist to local JSON",
)
async def run_once_endpoint(request: RunOnceRequest) -> FuturesSnapshot:
    snapshot = run_once(request.symbol)
    return FuturesSnapshot.model_validate(snapshot)


@app.get(
    "/api/futures/latest",
    response_model=FuturesSnapshot,
    responses={400: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
    tags=["Futures"],
    summary="Read latest local futures snapshot",
)
async def latest_endpoint(symbol: str = Query(..., min_length=1, max_length=32)) -> FuturesSnapshot:
    normalized_symbol = RunOnceRequest(symbol=symbol).symbol
    snapshot = get_latest(normalized_symbol)
    return FuturesSnapshot.model_validate(snapshot)
