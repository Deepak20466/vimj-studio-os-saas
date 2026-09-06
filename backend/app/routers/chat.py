from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.chat import ChatMessage
from app.models.user import User, UserRole
from app.schemas.chat import ChatMessageCreate, ChatMessageOut, ChatThreadOut, ChatUnreadCountOut
from app.security import require_admin_or_coach
from app.services.notifications import notify_and_push

router = APIRouter(prefix="/chat", tags=["chat"])


def _resolve_coach(db: Session, current_user: User, coach_id: Optional[int]) -> User:
    """A coach may only ever act on their own thread; an admin must name one."""
    if current_user.role == UserRole.COACH:
        return current_user
    if not coach_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="coach_id is required")
    coach = db.query(User).filter(User.id == coach_id, User.role == UserRole.COACH).first()
    if not coach:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Coach not found")
    return coach


def _to_out(m: ChatMessage) -> ChatMessageOut:
    return ChatMessageOut(
        id=m.id,
        coach_id=m.coach_id,
        sender_id=m.sender_id,
        sender_role=m.sender_role,
        sender_name=m.sender.name if m.sender else "Unknown",
        message=m.message,
        is_read=m.is_read,
        created_at=m.created_at,
    )


@router.get("/threads", response_model=List[ChatThreadOut])
def list_threads(db: Session = Depends(get_db), current_user: User = Depends(require_admin_or_coach)):
    """Admin: one row per active coach (so a new conversation can be started), most recently
    active thread first. Not used by coaches (single thread)."""
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin only")

    coaches = db.query(User).filter(User.role == UserRole.COACH, User.is_active.is_(True)).order_by(User.name).all()
    threads = []
    for coach in coaches:
        coach_id = coach.id
        last = (
            db.query(ChatMessage)
            .filter(ChatMessage.coach_id == coach_id)
            .order_by(ChatMessage.created_at.desc(), ChatMessage.id.desc())
            .first()
        )
        unread = (
            db.query(ChatMessage)
            .filter(
                ChatMessage.coach_id == coach_id,
                ChatMessage.sender_role == UserRole.COACH.value,
                ChatMessage.is_read.is_(False),
            )
            .count()
        )
        threads.append(
            ChatThreadOut(
                coach_id=coach_id,
                coach_name=coach.name,
                last_message=last.message if last else None,
                last_message_at=last.created_at if last else None,
                unread_count=unread,
            )
        )
    threads.sort(key=lambda t: t.last_message_at.timestamp() if t.last_message_at else 0, reverse=True)
    return threads


@router.get("/messages", response_model=List[ChatMessageOut])
def list_messages(
    coach_id: Optional[int] = Query(None),
    since_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_coach),
):
    coach = _resolve_coach(db, current_user, coach_id)
    query = db.query(ChatMessage).filter(ChatMessage.coach_id == coach.id)
    if since_id:
        query = query.filter(ChatMessage.id > since_id)
    messages = query.order_by(ChatMessage.created_at.asc(), ChatMessage.id.asc()).limit(200).all()
    return [_to_out(m) for m in messages]


@router.post("/messages", response_model=ChatMessageOut, status_code=status.HTTP_201_CREATED)
def send_message(
    payload: ChatMessageCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_coach),
):
    coach = _resolve_coach(db, current_user, payload.coach_id)

    message = ChatMessage(
        coach_id=coach.id,
        sender_id=current_user.id,
        sender_role=current_user.role.value,
        message=payload.message.strip(),
    )
    db.add(message)
    db.flush()

    if current_user.role == UserRole.COACH:
        for admin in db.query(User).filter(User.role == UserRole.ADMIN, User.is_active.is_(True)).all():
            notify_and_push(
                db,
                admin,
                message.message,
                title=f"Message from {current_user.name}",
                type="CHAT",
                link="/chat",
            )
    else:
        notify_and_push(
            db,
            coach,
            message.message,
            title=f"Message from {current_user.name} (Admin)",
            type="CHAT",
            link="/coach/chat",
        )

    db.commit()
    db.refresh(message)
    return _to_out(message)


@router.put("/read")
def mark_read(
    coach_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin_or_coach),
):
    coach = _resolve_coach(db, current_user, coach_id)
    other_role = UserRole.ADMIN.value if current_user.role == UserRole.COACH else UserRole.COACH.value
    db.query(ChatMessage).filter(
        ChatMessage.coach_id == coach.id,
        ChatMessage.sender_role == other_role,
        ChatMessage.is_read.is_(False),
    ).update({ChatMessage.is_read: True})
    db.commit()
    return {"detail": "Messages marked read"}


@router.get("/unread-count", response_model=ChatUnreadCountOut)
def unread_count(db: Session = Depends(get_db), current_user: User = Depends(require_admin_or_coach)):
    if current_user.role == UserRole.COACH:
        count = (
            db.query(ChatMessage)
            .filter(
                ChatMessage.coach_id == current_user.id,
                ChatMessage.sender_role == UserRole.ADMIN.value,
                ChatMessage.is_read.is_(False),
            )
            .count()
        )
    else:
        count = (
            db.query(ChatMessage)
            .filter(ChatMessage.sender_role == UserRole.COACH.value, ChatMessage.is_read.is_(False))
            .count()
        )
    return ChatUnreadCountOut(unread_count=count)
