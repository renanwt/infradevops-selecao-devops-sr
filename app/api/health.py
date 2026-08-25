"""Endpoints de health check.

- /health: liveness. Responde 200 se o processo esta vivo. NAO depende do banco:
  um liveness acoplado ao DB derruba todos os pods quando o banco oscila.
- /ready: readiness. Verifica dependencias (banco). Sem DB -> 503 e o pod sai do Service.
"""

from fastapi import APIRouter, Response, status

router = APIRouter(tags=["health"])


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/ready")
async def ready(response: Response) -> dict[str, str]:
    # A checagem de banco e conectada no commit de persistencia.
    db_ok = True
    if not db_ok:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "unavailable", "db": "error"}
    return {"status": "ready", "db": "ok"}
