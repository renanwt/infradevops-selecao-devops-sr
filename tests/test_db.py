"""Testes da camada de banco (engine, readiness real e migracoes)."""

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text

from app.core import db


@pytest.mark.integration
async def test_check_db_true_com_banco() -> None:
    assert await db.check_db() is True


async def test_check_db_false_sem_banco(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(db.get_settings(), "database_url", "postgresql+asyncpg://x:x@127.0.0.1:1/x")
    await db.dispose_engine()
    assert await db.check_db() is False


async def test_dispose_engine_idempotente() -> None:
    db.init_engine()
    await db.dispose_engine()
    await db.dispose_engine()
    assert db._engine is None


@pytest.mark.integration
async def test_get_session_executa_query() -> None:
    gen = db.get_session()
    session = await anext(gen)
    assert (await session.execute(text("SELECT 1"))).scalar() == 1
    with pytest.raises(StopAsyncIteration):
        await anext(gen)


@pytest.mark.integration
def test_migracao_upgrade_downgrade() -> None:
    # Sincrono: o env.py do Alembic abre seu proprio event loop (asyncio.run).
    cfg = Config("app/alembic.ini")
    command.downgrade(cfg, "base")
    command.upgrade(cfg, "head")

    sync_url = db.get_settings().database_url.replace("+asyncpg", "+psycopg")
    engine = create_engine(sync_url)
    try:
        insp = inspect(engine)
        assert "comments" in insp.get_table_names()
        assert any(
            i["name"] == "ix_comments_content_id_created" for i in insp.get_indexes("comments")
        )
    finally:
        engine.dispose()
