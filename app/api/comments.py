"""Endpoints de comentarios."""

from typing import Annotated

from fastapi import APIRouter, Depends, Path, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app import repository
from app.core.db import get_session
from app.schemas import CommentCreate, CommentList, CommentOut

router = APIRouter(prefix="/api/comment", tags=["comments"])

Session = Annotated[AsyncSession, Depends(get_session)]


@router.post("/new", status_code=status.HTTP_201_CREATED, response_model=CommentOut)
async def create(data: CommentCreate, session: Session) -> CommentOut:
    comment = await repository.create_comment(session, data)
    return CommentOut.model_validate(comment)


@router.get("/list/{content_id}", response_model=CommentList)
async def list_by_content(
    session: Session,
    content_id: Annotated[str, Path(min_length=1, max_length=128)],
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> CommentList:
    rows = await repository.list_comments(session, content_id, limit=limit, offset=offset)
    items = [CommentOut.model_validate(r) for r in rows]
    return CommentList(content_id=content_id, count=len(items), items=items)
