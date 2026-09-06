import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole, PasswordResetToken
from app.schemas.auth import (
    LoginRequest,
    TokenResponse,
    RefreshRequest,
    AccessTokenResponse,
    ForgotPasswordRequest,
    ResetPasswordRequest,
)
from app.schemas.user import UserOut, SelfAccountUpdate
from app.security import (
    verify_password,
    hash_password,
    create_access_token,
    create_refresh_token,
    decode_token,
    get_current_user,
)
from app.services.audit import log_action
from app.services.notifications import notify
from app.core.rate_limit import limiter
from app.config import settings

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=TokenResponse)
@limiter.limit(settings.LOGIN_RATE_LIMIT)
def login(request: Request, payload: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")
    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account is deactivated")
    if user.role == UserRole.STUDENT:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Student accounts cannot log in to this system")

    access_token = create_access_token(user.id, user.role.value)
    refresh_token = create_refresh_token(user.id, user.role.value)
    log_action(db, user.id, "LOGIN", "User", user.id)
    db.commit()

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        role=user.role.value,
        user_id=user.id,
        name=user.name,
    )


@router.post("/refresh", response_model=AccessTokenResponse)
def refresh(payload: RefreshRequest, db: Session = Depends(get_db)):
    token_data = decode_token(payload.refresh_token)
    if token_data.get("type") != "refresh":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token type")
    user = db.query(User).filter(User.id == int(token_data["sub"])).first()
    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found or inactive")
    access_token = create_access_token(user.id, user.role.value)
    return AccessTokenResponse(access_token=access_token)


@router.get("/me", response_model=UserOut)
def get_me(current_user: User = Depends(get_current_user)):
    return current_user


@router.put("/me", response_model=UserOut)
def update_me(payload: SelfAccountUpdate, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not verify_password(payload.current_password, current_user.password_hash):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Current password is incorrect")

    if payload.email and payload.email != current_user.email:
        if db.query(User).filter(User.email == payload.email, User.id != current_user.id).first():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")
        current_user.email = payload.email

    if payload.new_password:
        current_user.password_hash = hash_password(payload.new_password)

    log_action(db, current_user.id, "UPDATE_SELF", "User", current_user.id)
    db.commit()
    db.refresh(current_user)
    return current_user


@router.post("/logout")
def logout(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    log_action(db, current_user.id, "LOGOUT", "User", current_user.id)
    db.commit()
    return {"detail": "Logged out"}


@router.post("/forgot-password")
def forgot_password(payload: ForgotPasswordRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()
    # Always return 200 to avoid leaking which emails are registered.
    if not user:
        return {"detail": "If the email exists, a reset link has been sent"}

    token = secrets.token_urlsafe(32)
    reset_entry = PasswordResetToken(
        user_id=user.id,
        token=token,
        expires_at=datetime.now(timezone.utc) + timedelta(hours=1),
    )
    db.add(reset_entry)
    db.commit()

    if user.phone:
        notify(user.phone, f"Your VIMJ Studio password reset code is: {token[:8]}")

    return {"detail": "If the email exists, a reset link has been sent", "reset_token": token if settings.ENV != "production" else None}


@router.post("/reset-password")
def reset_password(payload: ResetPasswordRequest, db: Session = Depends(get_db)):
    entry = db.query(PasswordResetToken).filter(PasswordResetToken.token == payload.token).first()
    if not entry or entry.used or entry.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired reset token")

    user = db.query(User).filter(User.id == entry.user_id).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired reset token")

    user.password_hash = hash_password(payload.new_password)
    entry.used = True
    log_action(db, user.id, "PASSWORD_RESET", "User", user.id)
    db.commit()
    return {"detail": "Password has been reset successfully"}
