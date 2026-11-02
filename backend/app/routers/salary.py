from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.salary import CoachSalary
from app.models.user import User, UserRole
from app.schemas.salary import (
    SalaryAcknowledge,
    SalaryAdminOut,
    SalaryCreate,
    SalaryOut,
    SalaryUpdate,
)
from app.security import require_admin, require_coach
from app.services.audit import log_action
from app.services.notifications import notify_and_push

router = APIRouter(prefix="/salary", tags=["salary"])


@router.post("", response_model=SalaryOut, status_code=status.HTTP_201_CREATED)
def create_salary(
    payload: SalaryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    coach = (
        db.query(User)
        .filter(User.id == payload.coach_id, User.role == UserRole.COACH)
        .first()
    )
    if coach is None:
        raise HTTPException(status_code=404, detail="Coach not found")

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
        raise HTTPException(
            status_code=400,
            detail="Salary record already exists for this period",
        )

    salary = CoachSalary(**payload.model_dump())
    db.add(salary)
    db.flush()
    log_action(db, current_user.id, "CREATE", "CoachSalary", salary.id)
    db.commit()
    db.refresh(salary)
    return salary


@router.put("/{salary_id}", response_model=SalaryOut)
def update_salary(
    salary_id: int,
    payload: SalaryUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    salary = db.query(CoachSalary).filter(CoachSalary.id == salary_id).first()
    if salary is None:
        raise HTTPException(status_code=404, detail="Salary record not found")
    if salary.acknowledged_date:
        raise HTTPException(
            status_code=400,
            detail="Cannot edit a record the coach already acknowledged",
        )

    updates = payload.model_dump(exclude_unset=True, exclude_none=True)
    new_month = updates.get("month", salary.month)
    new_year = updates.get("year", salary.year)
    if (new_month, new_year) != (salary.month, salary.year):
        clash = (
            db.query(CoachSalary)
            .filter(
                CoachSalary.coach_id == salary.coach_id,
                CoachSalary.month == new_month,
                CoachSalary.year == new_year,
                CoachSalary.id != salary.id,
            )
            .first()
        )
        if clash:
            raise HTTPException(
                status_code=400,
                detail="Salary record already exists for this period",
            )

    for field, value in updates.items():
        setattr(salary, field, value)

    log_action(db, current_user.id, "UPDATE", "CoachSalary", salary.id)
    db.commit()
    db.refresh(salary)
    return salary


@router.delete("/{salary_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_salary(
    salary_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    salary = db.query(CoachSalary).filter(CoachSalary.id == salary_id).first()
    if salary is None:
        raise HTTPException(status_code=404, detail="Salary record not found")
    if salary.acknowledged_date:
        raise HTTPException(
            status_code=400,
            detail="Cannot delete a record the coach already acknowledged",
        )

    log_action(db, current_user.id, "DELETE", "CoachSalary", salary.id)
    db.delete(salary)
    db.commit()


@router.post("/acknowledge", response_model=SalaryOut)
def acknowledge_salary(
    payload: SalaryAcknowledge,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    salary = db.query(CoachSalary).filter(CoachSalary.id == payload.salary_id).first()
    if salary is None:
        raise HTTPException(status_code=404, detail="Salary record not found")
    if salary.coach_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized to acknowledge this record")
    if salary.acknowledged_date:
        raise HTTPException(status_code=400, detail="Salary already acknowledged")

    salary.acknowledged_date = datetime.now(timezone.utc)
    log_action(db, current_user.id, "ACKNOWLEDGE_SALARY", "CoachSalary", salary.id)
    db.commit()
    db.refresh(salary)

    admins = (
        db.query(User)
        .filter(User.role == UserRole.ADMIN, User.is_active.is_(True))
        .all()
    )
    for admin in admins:
        notify_and_push(
            db,
            admin,
            f"{current_user.name} acknowledged their salary for {salary.month}/{salary.year}.",
            "Salary acknowledged",
            "SALARY_ACKNOWLEDGED",
            link="/salary",
        )
    db.commit()
    return salary


@router.get("/coach/{coach_id}", response_model=List[SalaryOut])
def coach_salary_history(
    coach_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_coach),
):
    if current_user.id != coach_id:
        raise HTTPException(
            status_code=403,
            detail="Not authorized to view this coach's salary",
        )
    return (
        db.query(CoachSalary)
        .filter(CoachSalary.coach_id == coach_id)
        .order_by(CoachSalary.year.desc(), CoachSalary.month.desc())
        .all()
    )


@router.get("", response_model=List[SalaryAdminOut])
def list_salaries(
    coach_id: Optional[int] = Query(default=None, gt=0),
    month: Optional[int] = Query(default=None, ge=1, le=12),
    year: Optional[int] = Query(default=None, ge=2000, le=2200),
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    query = db.query(CoachSalary)
    if coach_id is not None:
        query = query.filter(CoachSalary.coach_id == coach_id)
    if month is not None:
        query = query.filter(CoachSalary.month == month)
    if year is not None:
        query = query.filter(CoachSalary.year == year)

    salaries = query.order_by(CoachSalary.year.desc(), CoachSalary.month.desc()).all()
    coach_ids = {salary.coach_id for salary in salaries}
    coaches = (
        {
            user.id: user.name
            for user in db.query(User).filter(User.id.in_(coach_ids)).all()
        }
        if coach_ids
        else {}
    )
    return [
        SalaryAdminOut(
            id=salary.id,
            coach_id=salary.coach_id,
            coach_name=coaches.get(salary.coach_id, "Unknown"),
            month=salary.month,
            year=salary.year,
            amount=salary.amount,
            notified_at=salary.notified_at,
            acknowledged_date=salary.acknowledged_date,
            created_at=salary.created_at,
        )
        for salary in salaries
    ]
