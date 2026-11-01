from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.routers.fees import send_reminder
from app.security import require_admin
from app.services.insights import revenue_risk_insights

router = APIRouter(prefix="/insights", tags=["insights"])


@router.get("/revenue-risk")
def get_revenue_risk_insights(
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    """Return three local, rule-based revenue and attendance predictions."""
    return revenue_risk_insights(db)


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
