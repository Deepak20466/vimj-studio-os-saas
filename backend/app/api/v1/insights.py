from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.routers.fees import send_reminder
from app.security import require_admin
from app.services.insights import revenue_risk_insights

router = APIRouter(prefix="/insights", tags=["insights"])


@router.get("/revenue-risk")
def get_revenue_risk_insights(
    period: str | None = None,
    selected_date: date | None = None,
    month: int | None = None,
    year: int | None = None,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    """Return rule-based insights, optionally filtered to a dashboard period."""
    if period is None:
        return revenue_risk_insights(db)
    if period not in {"day", "month", "year", "overall"}:
        raise HTTPException(status_code=400, detail="Period must be day, month, year, or overall")
    if month is not None and not 1 <= month <= 12:
        raise HTTPException(status_code=400, detail="Month must be between 1 and 12")
    if year is not None and not 2000 <= year <= 2100:
        raise HTTPException(status_code=400, detail="Year must be between 2000 and 2100")
    anchor = selected_date or date.today()
    return revenue_risk_insights(
        db,
        period=period,
        selected_date=anchor,
        selected_month=month or anchor.month,
        selected_year=year or anchor.year,
    )


# Keep the existing unversioned routes used by web and mobile clients, while
# also exposing the requested /api/v1 paths for integrations.
versioned_router = APIRouter(prefix="/api/v1", tags=["api-v1"])
versioned_router.include_router(router)
versioned_router.add_api_route(
    "/fees/{fee_id}/remind",
    send_reminder,
    methods=["POST"],
    name="queue_fee_reminder_v1",
)
