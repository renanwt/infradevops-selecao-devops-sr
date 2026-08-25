"""Schemas Pydantic (contrato HTTP)."""

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class CommentCreate(BaseModel):
    email: EmailStr
    comment: str = Field(min_length=1, max_length=2000)
    content_id: str = Field(min_length=1, max_length=128)


class CommentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: EmailStr
    comment: str
    content_id: str
    created_at: datetime


class CommentList(BaseModel):
    content_id: str
    count: int
    items: list[CommentOut]
