from httpx import AsyncClient


async def test_health(client: AsyncClient) -> None:
    r = await client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}
    assert "x-request-id" in r.headers


async def test_ready(client: AsyncClient) -> None:
    r = await client.get("/ready")
    assert r.status_code == 200
    assert r.json()["status"] == "ready"


async def test_request_id_propagado(client: AsyncClient) -> None:
    r = await client.get("/health", headers={"x-request-id": "abc-123"})
    assert r.headers["x-request-id"] == "abc-123"
