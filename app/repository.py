"""Acesso a dados de comentarios."""

from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Comment
from app.schemas import CommentCreate


async def create_comment(session: AsyncSession, data: CommentCreate) -> Comment:
    comment = Comment(email=data.email, comment=data.comment, content_id=data.content_id)
    session.add(comment)
    await session.commit()
    await session.refresh(comment)
    return comment


async def list_comments(
    session: AsyncSession, content_id: str, *, limit: int, offset: int
) -> Sequence[Comment]:
    stmt = (
        select(Comment)
        .where(Comment.content_id == content_id)
        .order_by(Comment.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    return (await session.execute(stmt)).scalars().all()
