import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.config import settings
from app.core.rate_limit import limiter
from app.services.scheduler import start_scheduler, shutdown_scheduler
from app.routers import (
    auth,
    students,
    coaches,
    activities,
    attendance,
    leave,
    fees,
    salary,
    swap,
    reports,
)

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
    allow_origins=[settings.FRONTEND_ORIGIN],
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
app.include_router(leave.router)
app.include_router(fees.router)
app.include_router(salary.router)
app.include_router(swap.router)
app.include_router(reports.router)


@app.get("/health")
def health_check():
    return {"status": "ok", "service": "VIMJ Studio Attendance System"}
