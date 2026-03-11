from fastapi import FastAPI
from fastapi.responses import JSONResponse


class FuturesAPIError(Exception):
    """Base exception with explicit HTTP status mapping."""

    status_code = 500

    def __init__(self, message: str, status_code: int | None = None) -> None:
        self.message = message
        if status_code is not None:
            self.status_code = status_code
        super().__init__(message)


class InvalidRequestError(FuturesAPIError):
    status_code = 400


class DataNotFoundError(FuturesAPIError):
    status_code = 404


class EmptyDataError(FuturesAPIError):
    status_code = 404


class UpstreamFetchError(FuturesAPIError):
    status_code = 502


class StorageError(FuturesAPIError):
    status_code = 500


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(FuturesAPIError)
    async def handle_futures_api_error(_, exc: FuturesAPIError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={"message": exc.message},
        )

    @app.exception_handler(Exception)
    async def handle_unexpected_error(_, __: Exception) -> JSONResponse:
        return JSONResponse(
            status_code=500,
            content={"message": "unexpected server error"},
        )
