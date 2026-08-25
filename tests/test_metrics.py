"""Testes do endpoint /metrics e da instrumentacao."""

import pytest
from httpx import AsyncClient
from prometheus_client.parser import text_string_to_metric_families

from app import __version__


def _sample(text: str, name: str, **labels: str) -> float | None:
    for family in text_string_to_metric_families(text):
        for s in family.samples:
            if s.name == name and all(s.labels.get(k) == v for k, v in labels.items()):
                return float(s.value)
    return None


async def test_metrics_expoe_formato_prometheus(client: AsyncClient) -> None:
    r = await client.get("/metrics")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/plain")
    assert _sample(r.text, "app_info", version=__version__) == 1.0


async def test_metrics_conta_requests_por_rota_template(client: AsyncClient) -> None:
    before = await client.get("/metrics")
    b = _sample(before.text, "http_requests_total", route="/health", status_class="2xx") or 0

    await client.get("/health")
    await client.get("/health")

    after = await client.get("/metrics")
    assert _sample(after.text, "http_requests_total", route="/health", status_class="2xx") == b + 2
    # latencia observada na mesma rota
    assert (_sample(after.text, "http_request_duration_seconds_count", route="/health") or 0) >= 2


async def test_metrics_classifica_4xx_e_usa_template_da_rota(client: AsyncClient) -> None:
    await client.post("/api/comment/new", json={"email": "x"})
    r = await client.get("/metrics")
    assert (
        _sample(r.text, "http_requests_total", route="/api/comment/new", status_class="4xx") or 0
    ) >= 1
    # path real nao vaza como label
    assert "/api/comment/list/abc" not in r.text


async def test_metrics_rota_inexistente_vai_para_unmatched(client: AsyncClient) -> None:
    await client.get("/nao-existe-123")
    r = await client.get("/metrics")
    assert (_sample(r.text, "http_requests_total", route="unmatched", status_class="4xx") or 0) >= 1
    assert "/nao-existe-123" not in r.text


async def test_metrics_nao_conta_a_si_mesmo(client: AsyncClient) -> None:
    r = await client.get("/metrics")
    assert _sample(r.text, "http_requests_total", route="/metrics") is None


@pytest.mark.integration
async def test_metrics_db_e_negocio(client: AsyncClient) -> None:
    before = await client.get("/metrics")
    created_b = _sample(before.text, "comments_created_total") or 0

    await client.post(
        "/api/comment/new",
        json={"email": "m@example.com", "comment": "ok", "content_id": "metrics"},
    )
    await client.get("/api/comment/list/metrics")

    r = await client.get("/metrics")
    assert _sample(r.text, "comments_created_total") == created_b + 1
    assert (_sample(r.text, "db_query_duration_seconds_count", operation="insert") or 0) >= 1
    assert (_sample(r.text, "db_query_duration_seconds_count", operation="select") or 0) >= 1
    assert _sample(r.text, "db_pool_connections", state="idle") is not None
