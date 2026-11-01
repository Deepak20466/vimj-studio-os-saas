# VIMJ Studio OS SaaS — Backend

FastAPI + PostgreSQL backend for attendance, fees, receipts, leave and swap workflows,
role-enforced data access, studio reporting, and the Admin-only AI insights API.
The local MCP server shares the same SQLAlchemy models and applies the configured
Admin identity to every tool call.

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
python scripts/seed_admin.py --email admin@example.com --password "ChangeMe123!" --name "Admin"
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

The Admin dashboard and MCP fee-reminder actions return a queued mock status and do not
send a WhatsApp/SMS message. They require no paid messaging provider.

## Scheduled jobs (APScheduler, started in-process with the app)

- Fee reminders: 10th of each month, 09:00
- Mark unpaid fees overdue: daily at 00:30
- Coach attendance reminder: every minute, fires 15 min after a class ends if unmarked
- Missed-attendance admin alert: every minute, fires 10 min after a class ends if attendance still isn't submitted (see FEATURES_ADDED.md 1.8/1.9)
- End-of-day missing-attendance report to admins: daily at 21:00

## Tests

Run the focused Admin AI prediction and Coach RBAC tests from this directory with
`python -m pytest tests/test_insights.py -q`.

## API docs

Once running: `http://localhost:8000/docs` (Swagger) or `/redoc`.
