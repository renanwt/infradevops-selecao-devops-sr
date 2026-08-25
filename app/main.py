"""Ponto de entrada da Comments API."""

import time
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager

import structlog
from fastapi import FastAPI, Request, Response

from app import __version__
from app.api import comments, health
from app.core import db
from app.core.config import get_settings
from app.core.logging import configure_logging
from app.metrics import register_pool_gauges, setup_metrics

settings = get_settings()
configure_logging(settings.log_level)
log = structlog.get_logger()


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    log.info("startup", app=settings.app_name, env=settings.app_env, version=__version__)
    db.init_engine()
    yield
    await db.dispose_engine()
    log.info("shutdown")


app = FastAPI(
    title="Comments API",
    version=__version__,
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url=None,
)


@app.middleware("http")
async def request_logging(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    request_id = request.headers.get("x-request-id", str(uuid.uuid4()))
    structlog.contextvars.clear_contextvars()
    structlog.contextvars.bind_contextvars(request_id=request_id)
    start = time.perf_counter()
    response = await call_next(request)
    latency_ms = round((time.perf_counter() - start) * 1000, 2)
    response.headers["x-request-id"] = request_id
    if request.url.path not in ("/health", "/ready", "/metrics"):
        log.info(
            "request",
            method=request.method,
            path=request.url.path,
            status=response.status_code,
            latency_ms=latency_ms,
        )
    return response


setup_metrics(app)
register_pool_gauges(lambda: db._engine.pool if db._engine is not None else None)

app.include_router(health.router)
app.include_router(comments.router)
