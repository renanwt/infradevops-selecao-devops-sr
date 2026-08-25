"""Configuracao da aplicacao via variaveis de ambiente (12-factor)."""

from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "comments-api"
    app_env: Literal["local", "dev", "prod"] = "local"
    log_level: str = "INFO"

    database_url: str = Field(
        default="postgresql+asyncpg://comments:comments@localhost:5432/comments",
        description="URL SQLAlchemy async. Em cluster vem do Secret gerado pelo External Secrets.",
    )
    db_pool_size: int = 5
    db_max_overflow: int = 5


@lru_cache
def get_settings() -> Settings:
    return Settings()
