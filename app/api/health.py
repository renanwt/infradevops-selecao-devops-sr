"""Endpoints de health check.

- /health: liveness. Responde 200 se o processo esta vivo. NAO depende do banco:
  um liveness acoplado ao DB derruba todos os pods quando o banco oscila.
- /ready: readiness. Verifica dependencias (banco). Sem DB -> 503 e o pod sai do Service.
"""

from fastapi import APIRouter, Response, status

from app.core import db

router = APIRouter(tags=["health"])


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/ready")
async def ready(response: Response) -> dict[str, str]:
    if not await db.check_db():
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "unavailable", "db": "error"}
    return {"status": "ready", "db": "ok"}
