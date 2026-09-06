from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.academy import AcademySettings
from app.models.user import User
from app.schemas.academy import AcademyOut, AcademyUpdate
from app.security import get_current_user, require_admin
from app.services.audit import log_action

router = APIRouter(prefix="/academy", tags=["academy"])


def _get_or_create(db: Session) -> AcademySettings:
    row = db.query(AcademySettings).filter(AcademySettings.id == 1).first()
    if not row:
        row = AcademySettings(id=1, name="VIMJ Studio")
        db.add(row)
        db.commit()
        db.refresh(row)
    return row


@router.get("", response_model=AcademyOut)
def get_academy(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    """Any authenticated user (admin or coach) can view the academy's About details."""
    return _get_or_create(db)


@router.put("", response_model=AcademyOut)
def update_academy(
    payload: AcademyUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    row = _get_or_create(db)
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(row, field, value)
    log_action(db, current_user.id, "UPDATE", "AcademySettings", row.id)
    db.commit()
    db.refresh(row)
    return row
