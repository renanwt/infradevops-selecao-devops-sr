"""Instrumentacao Prometheus.

Cardinalidade controlada: o label `route` usa o *template* da rota
(ex.: /api/comment/list/{content_id}), nunca o path real.
"""

import time
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

from app import __version__

LATENCY_BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.3, 0.5, 1.0, 2.5, 5.0)

# --- HTTP -------------------------------------------------------------------
HTTP_REQUESTS = Counter(
    "http_requests_total", "Total de requisicoes HTTP", ["method", "route", "status_class"]
)
HTTP_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Latencia das requisicoes HTTP",
    ["method", "route"],
    buckets=LATENCY_BUCKETS,
)
HTTP_IN_PROGRESS = Gauge("http_requests_in_progress", "Requisicoes em andamento")

# --- Negocio ----------------------------------------------------------------
COMMENTS_CREATED = Counter("comments_created_total", "Comentarios criados")

# --- Banco ------------------------------------------------------------------
DB_QUERY_LATENCY = Histogram(
    "db_query_duration_seconds", "Latencia de operacoes no banco", ["operation"]
)
DB_ERRORS = Counter("db_errors_total", "Erros em operacoes no banco", ["operation"])
DB_POOL = Gauge("db_pool_connections", "Conexoes do pool SQLAlchemy", ["state"])

# --- App --------------------------------------------------------------------
APP_INFO = Gauge("app_info", "Metadados da aplicacao", ["version"])
APP_INFO.labels(version=__version__).set(1)

_UNMATCHED = "unmatched"
_EXCLUDED = {"/metrics"}


def _route_template(request: Request) -> str:
    """Template da rota resolvida pelo router (disponivel apos o roteamento)."""
    route = request.scope.get("route")
    return str(getattr(route, "path_format", None) or getattr(route, "path", None) or _UNMATCHED)


@asynccontextmanager
async def track_db(operation: str) -> AsyncIterator[None]:
    """Mede latencia e conta erros de uma operacao de banco."""
    start = time.perf_counter()
    try:
        yield
    except Exception:
        DB_ERRORS.labels(operation=operation).inc()
        raise
    finally:
        DB_QUERY_LATENCY.labels(operation=operation).observe(time.perf_counter() - start)


def register_pool_gauges(get_pool: Callable[[], object | None]) -> None:
    """Expoe checkedout/checkedin do pool SQLAlchemy como gauges."""

    def _read(attr: str) -> float:
        pool = get_pool()
        fn = getattr(pool, attr, None)
        return float(fn()) if callable(fn) else 0.0

    DB_POOL.labels(state="in_use").set_function(lambda: _read("checkedout"))
    DB_POOL.labels(state="idle").set_function(lambda: _read("checkedin"))


def setup_metrics(app: FastAPI) -> None:
    @app.middleware("http")
    async def _metrics_middleware(
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        if request.url.path in _EXCLUDED:
            return await call_next(request)

        method = request.method
        HTTP_IN_PROGRESS.inc()
        start = time.perf_counter()
        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
            return response
        finally:
            route = _route_template(request)
            HTTP_LATENCY.labels(method=method, route=route).observe(time.perf_counter() - start)
            HTTP_REQUESTS.labels(
                method=method, route=route, status_class=f"{status // 100}xx"
            ).inc()
            HTTP_IN_PROGRESS.dec()

    @app.get("/metrics", include_in_schema=False)
    async def metrics() -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
