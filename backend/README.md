# VIMJ Studio Attendance System — Backend

FastAPI + PostgreSQL backend implementing all 15 core requirements: attendance tracking,
geofenced + selfie-verified check-ins, fee/salary reminders, leave & swap workflows,
RBAC-enforced data isolation, and business analytics/reporting.

## Setup

```bash
python -m venv venv
venv\Scripts\activate          # Windows
# source venv/bin/activate     # Linux/macOS
pip install -r requirements.txt

copy .env.example .env         # then edit DATABASE_URL, JWT_SECRET_KEY, etc.

# Create the database in PostgreSQL first, e.g.:
#   CREATE DATABASE vimj_attendance;
#   CREATE USER vimj_user WITH PASSWORD 'changeme';
#   GRANT ALL PRIVILEGES ON DATABASE vimj_attendance TO vimj_user;

alembic upgrade head
python scripts/seed_admin.py --email admin@vimj.com --password "ChangeMe123!" --name "Admin"
```

## Run (development)

```bash
uvicorn app.main:app --reload
```

## Run (production, no Docker)

```bash
gunicorn -c gunicorn_conf.py app.main:app
```

Install `vimj-attendance.service` as a systemd unit (see the file) for auto-restart on boot,
and put `nginx.conf.example` in front of it as a reverse proxy + static file server for the
built React app. Selfies are stored under `UPLOAD_DIR` (default `uploads/selfies/`) and are
never served as static files — only through the authenticated `/attendance/selfie/{id}` endpoint.

## Notifications

SMS/WhatsApp reminders run through Twilio. Set `NOTIFICATIONS_ENABLED=true` and the `TWILIO_*`
env vars to send for real; otherwise messages are logged (dry-run) so the system is usable
without a Twilio account during development.

## Scheduled jobs (APScheduler, started in-process with the app)

- Fee reminders: 10th of each month, 09:00
- Salary acknowledgment notifications: 10th of each month, 09:05
- Mark unpaid fees overdue: daily at 00:30
- Coach attendance reminder: every minute, fires 15 min after a class ends if unmarked
- End-of-day missing-attendance report to admins: daily at 21:00

## Tests

No test suite is checked in yet; `python -c "from app.main import app"` and a manual run
against a local Postgres/SQLite instance are the fastest way to validate changes.

## API docs

Once running: `http://localhost:8000/docs` (Swagger) or `/redoc`.
