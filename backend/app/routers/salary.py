from datetime import datetime
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.models.salary import CoachSalary
from app.schemas.salary import SalaryCreate, SalaryAcknowledge, SalaryOut
from app.security import require_admin, require_coach
from app.services.audit import log_action

router = APIRouter(prefix="/salary", tags=["salary"])


@router.post("", response_model=SalaryOut, status_code=status.HTTP_201_CREATED)
def create_salary(
    payload: SalaryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    existing = (
        db.query(CoachSalary)
        .filter(
            CoachSalary.coach_id == payload.coach_id,
            CoachSalary.month == payload.month,
            CoachSalary.year == payload.year,
        )
        .first()
    )
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Salary record already exists for this period")

    salary = CoachSalary(**payload.model_dump())
    db.add(salary)
    db.flush()
    log_action(db, current_user.id, "CREATE", "CoachSalary", salary.id)
    db.commit()
    db.refresh(salary)
    return salary


@router.post("/acknowledge", response_model=SalaryOut)
def acknowledge_salary(
    payload: SalaryAcknowledge,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    salary = db.query(CoachSalary).filter(CoachSalary.id == payload.salary_id).first()
    if not salary:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Salary record not found")
    if salary.coach_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to acknowledge this record")
    if salary.acknowledged_date:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Salary already acknowledged")

    salary.acknowledged_date = datetime.utcnow()
    log_action(db, current_user.id, "ACKNOWLEDGE_SALARY", "CoachSalary", salary.id)
    db.commit()
    db.refresh(salary)
    return salary


@router.get("/coach/{coach_id}", response_model=List[SalaryOut])
def coach_salary_history(
    coach_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    if current_user.id != coach_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to view this coach's salary")
    return (
        db.query(CoachSalary)
        .filter(CoachSalary.coach_id == coach_id)
        .order_by(CoachSalary.year.desc(), CoachSalary.month.desc())
        .all()
    )
