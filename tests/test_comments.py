"""Testes dos endpoints de comentarios.

- Validacao (422): nao toca no banco.
- Integracao: usam o Postgres do docker-compose (marker `integration`).
"""

import pytest
from httpx import AsyncClient
from sqlalchemy import text

from app.core import db

VALID = {"email": "ana@example.com", "comment": "Otimo artigo!", "content_id": "post-1"}


@pytest.mark.parametrize(
    "payload",
    [
        {**VALID, "email": "nao-e-email"},
        {**VALID, "comment": ""},
        {**VALID, "comment": "x" * 2001},
        {**VALID, "content_id": ""},
        {k: v for k, v in VALID.items() if k != "email"},
    ],
)
async def test_create_invalid_422(client: AsyncClient, payload: dict[str, str]) -> None:
    r = await client.post("/api/comment/new", json=payload)
    assert r.status_code == 422


async def test_list_invalid_limit_422(client: AsyncClient) -> None:
    r = await client.get("/api/comment/list/post-1", params={"limit": 0})
    assert r.status_code == 422


@pytest.fixture
async def clean_db() -> None:
    async with db.init_engine().begin() as conn:
        await conn.execute(text("TRUNCATE comments"))


@pytest.mark.integration
async def test_create_and_list(client: AsyncClient, clean_db: None) -> None:
    r = await client.post("/api/comment/new", json=VALID)
    assert r.status_code == 201
    body = r.json()
    assert body["email"] == VALID["email"]
    assert body["content_id"] == "post-1"
    assert "id" in body and "created_at" in body

    r = await client.get("/api/comment/list/post-1")
    assert r.status_code == 200
    data = r.json()
    assert data["count"] == 1
    assert data["items"][0]["id"] == body["id"]


@pytest.mark.integration
async def test_list_empty_returns_200(client: AsyncClient, clean_db: None) -> None:
    r = await client.get("/api/comment/list/inexistente")
    assert r.status_code == 200
    assert r.json() == {"content_id": "inexistente", "count": 0, "items": []}


@pytest.mark.integration
async def test_list_pagination_and_order(client: AsyncClient, clean_db: None) -> None:
    for i in range(5):
        await client.post("/api/comment/new", json={**VALID, "comment": f"c{i}"})
    await client.post("/api/comment/new", json={**VALID, "content_id": "outro"})

    r = await client.get("/api/comment/list/post-1", params={"limit": 2, "offset": 0})
    page1 = r.json()
    assert page1["count"] == 2
    assert page1["items"][0]["comment"] == "c4"  # mais recente primeiro

    r = await client.get("/api/comment/list/post-1", params={"limit": 2, "offset": 4})
    assert r.json()["count"] == 1
