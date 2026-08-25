import pytest
from httpx import AsyncClient

from app.core import db


async def test_health(client: AsyncClient) -> None:
    r = await client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}
    assert "x-request-id" in r.headers


async def test_ready_ok(client: AsyncClient, monkeypatch: pytest.MonkeyPatch) -> None:
    async def fake_check() -> bool:
        return True

    monkeypatch.setattr(db, "check_db", fake_check)
    r = await client.get("/ready")
    assert r.status_code == 200
    assert r.json() == {"status": "ready", "db": "ok"}


async def test_ready_db_down(client: AsyncClient, monkeypatch: pytest.MonkeyPatch) -> None:
    async def fake_check() -> bool:
        return False

    monkeypatch.setattr(db, "check_db", fake_check)
    r = await client.get("/ready")
    assert r.status_code == 503
    assert r.json()["db"] == "error"


async def test_request_id_propagado(client: AsyncClient) -> None:
    r = await client.get("/health", headers={"x-request-id": "abc-123"})
    assert r.headers["x-request-id"] == "abc-123"
