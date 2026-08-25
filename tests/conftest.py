from collections.abc import AsyncIterator

import pytest
from httpx import ASGITransport, AsyncClient

from app.core import db
from app.main import app


@pytest.fixture(autouse=True)
async def _dispose_engine() -> AsyncIterator[None]:
    """pytest-asyncio cria um event loop por teste; conexoes do pool nao podem
    sobreviver entre loops. Descarta o engine ao final de cada teste."""
    yield
    await db.dispose_engine()


@pytest.fixture
async def client() -> AsyncIterator[AsyncClient]:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c
