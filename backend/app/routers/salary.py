from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User, UserRole
from app.models.salary import CoachSalary
from app.schemas.salary import SalaryCreate, SalaryAcknowledge, SalaryOut, SalaryAdminOut, SalaryUpdate
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


@router.put("/{salary_id}", response_model=SalaryOut)
def update_salary(
    salary_id: int,
    payload: SalaryUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    salary = db.query(CoachSalary).filter(CoachSalary.id == salary_id).first()
    if not salary:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Salary record not found")
    if salary.acknowledged_date:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot edit a record the coach already acknowledged")

    updates = payload.model_dump(exclude_unset=True)
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
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Salary record already exists for this period")

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
    if not salary:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Salary record not found")
    if salary.acknowledged_date:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot delete a record the coach already acknowledged")

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

    admins = db.query(User).filter(User.role == UserRole.ADMIN, User.is_active.is_(True)).all()
    for admin in admins:
        notify_and_push(
            db, admin, f"{current_user.name} acknowledged their salary for {salary.month}/{salary.year}.",
            "Salary acknowledged", "SALARY_ACKNOWLEDGED", link="/salary",
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
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to view this coach's salary")
    return (
        db.query(CoachSalary)
        .filter(CoachSalary.coach_id == coach_id)
        .order_by(CoachSalary.year.desc(), CoachSalary.month.desc())
        .all()
    )


@router.get("", response_model=List[SalaryAdminOut])
def list_salaries(
    coach_id: Optional[int] = None,
    month: Optional[int] = None,
    year: Optional[int] = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    query = db.query(CoachSalary)
    if coach_id:
        query = query.filter(CoachSalary.coach_id == coach_id)
    if month:
        query = query.filter(CoachSalary.month == month)
    if year:
        query = query.filter(CoachSalary.year == year)

    salaries = query.order_by(CoachSalary.year.desc(), CoachSalary.month.desc()).limit(500).all()
    coaches = {u.id: u.name for u in db.query(User).filter(User.id.in_([s.coach_id for s in salaries])).all()}
    return [
        SalaryAdminOut(
            id=s.id,
            coach_id=s.coach_id,
            coach_name=coaches.get(s.coach_id, "Unknown"),
            month=s.month,
            year=s.year,
            amount=s.amount,
            notified_at=s.notified_at,
            acknowledged_date=s.acknowledged_date,
            created_at=s.created_at,
        )
        for s in salaries
    ]
