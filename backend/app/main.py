import logging
import time
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.config import settings
from app.core.rate_limit import limiter
from app.database import get_db
from app.models.user import User
from app.services.scheduler import start_scheduler, shutdown_scheduler
from app.routers import (
    auth,
    students,
    coaches,
    activities,
    attendance,
    fees,
    dashboard,
    batches,
    receipts,
    academy,
    fee_reminders,
    notifications,
    reset,
    leave,
)
from app.api.v1 import insights

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("vimj.main")


@asynccontextmanager
async def lifespan(app: FastAPI):
    if settings.ENV != "test":
        start_scheduler()
    yield
    shutdown_scheduler()


app = FastAPI(title="VIMJ Studio Attendance System", version="1.0.0", lifespan=lifespan)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.FRONTEND_ORIGIN, settings.MOBILE_WEB_ORIGIN],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def response_time_header(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    elapsed_ms = (time.time() - start) * 1000
    response.headers["X-Response-Time-ms"] = f"{elapsed_ms:.1f}"
    if elapsed_ms > 2000:
        logger.warning("Slow response: %s %s took %.1fms", request.method, request.url.path, elapsed_ms)
    return response


app.include_router(auth.router)
app.include_router(students.router)
app.include_router(coaches.router)
app.include_router(activities.router)
app.include_router(attendance.router)
app.include_router(fees.router)
app.include_router(dashboard.router)
app.include_router(batches.router)
app.include_router(receipts.router)
app.include_router(academy.router)
app.include_router(fee_reminders.router)
app.include_router(notifications.router)
app.include_router(reset.router)
app.include_router(leave.router)
app.include_router(insights.router)
app.include_router(insights.versioned_router)


@app.get("/health")
def health_check():
    return {"status": "ok", "service": "VIMJ Studio Attendance System"}


@app.get("/health/ready")
def database_readiness_check(db: Session = Depends(get_db)):
    """Exercise a real application-table read for monitoring without changing data.

    Reading an existing user row also records useful database activity for the
    configured Supabase project; a bare SELECT 1 can be too weak as a keepalive.
    """
    try:
        db.query(User.id).order_by(User.id).limit(1).first()
    except SQLAlchemyError as exc:
        logger.warning("Database readiness check failed: %s", type(exc).__name__)
        raise HTTPException(status_code=503, detail="database_unavailable") from None
    return {"status": "ok", "database": "ok"}

from app.routers import reports
app.include_router(reports.router)
