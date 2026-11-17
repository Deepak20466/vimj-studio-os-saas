# VIMJ Studio OS SaaS Architecture

## Application layers

- **React web:** the Admin dashboard and Coach dashboard are separate protected routes. Admin-only command center data is requested from an Admin-guarded API; coach pages are unchanged and have no revenue-risk or forecast UI.
- **Flutter mobile:** the existing Admin and Coach experiences continue to use the same FastAPI API and role checks.
- **FastAPI:** SQLAlchemy models and PostgreSQL remain the source of truth. Existing attendance, fee, batch, and enrollment models power the new insights without schema migrations.
- **Local MCP:** `mcp_server/server.py` runs as a stdio FastMCP process for Claude Desktop. It reads the same database, resolves `VIMJ_MCP_ADMIN_EMAIL` to an active Admin on each call, and writes attendance/reminder audit records as that Admin. It does not expose a network port.

## Production hosting

The React dashboard and FastAPI API run as separate Cloud Run services in `asia-south1`:

- Web: `https://vimj-frontend-eqwnplgd6q-el.a.run.app`, built into a small Nginx container with SPA route fallback.
- API: `https://vimj-backend-eqwnplgd6q-el.a.run.app`, built from `backend/Dockerfile` on Python 3.12 so the pinned PostgreSQL driver installs from its binary wheel.
- Database: Google Cloud SQL PostgreSQL 17 (`vimj-academy:asia-south1:deepak20`, database `vimj_academy`, private to the project: no authorized networks). The API reaches it through Cloud Run's built-in Cloud SQL socket connector; the connection string is provided through Secret Manager (`vimj-cloudsql-database-url`). The React image embeds the API origin at build time and does not carry database credentials. The database moved here from Supabase on 2026-11-17. Backups: Cloud SQL automated backups + 7-day point-in-time recovery, and a nightly logical dump to an offsite bucket in a separate project.

## Admin AI Command Center

`GET /insights/revenue-risk` (also `/api/v1/insights/revenue-risk`) is protected by `require_admin`; Coaches receive HTTP 403. It returns three deterministic predictions:

1. **Fee default:** sums outstanding balances with due dates more than seven days in the past.
2. **Attendance drop:** compares the latest three marked sessions on each weekday for a batch against the prior three sessions on that same weekday. A drop is flagged when all three latest rates are more than 30% below that prior average.
3. **Revenue forecast:** averages fee collections for the latest three calendar billing months.

The response also includes dashboard KPIs and batch analytics. The batch “estimated profit” is a revenue estimate: fees are attached to activities and the database has no batch expense records, so actual net profit cannot be calculated.

The web dashboard uses one combined chart for the estimated batch revenue/profit proxy and attendance rate. The Coach dashboard does not request this endpoint.

## Reminders and MCP tools

Admin manual reminders at `POST /fees/{fee_id}/remind` (and `/api/v1/fees/{fee_id}/remind`) return `{ "status": "queued" }` for a mock WhatsApp action. They do not send SMS or WhatsApp and require no paid provider. This manual action is independent of the existing coach reminder-draft approve/reject workflow.

The MCP server exposes five Admin-only tools: `get_todays_absentees`, `get_fee_defaulters`, `mark_attendance`, `create_fee_reminder`, and `get_batch_analytics`. MCP attendance writes use the existing `StudentAttendance` model, the `Present`/`Absent`/`Leave` statuses, admin approval, and the audit log. When a date matches multiple scheduled classes for a student, the tool refuses to guess and makes no change.

## Local setup

Install `backend/requirements.txt` for FastAPI and `mcp_server/requirements.txt` in the isolated MCP environment. Configure `backend/.env` with a database connection and active Admin email. Use the root `.mcp.json` with Claude Code, or copy its entry with absolute paths into Claude Desktop's config. Setup details are in [mcp_server/README.md](../mcp_server/README.md).

## Health checks and scheduling

`GET /health` is a lightweight liveness route and intentionally does not depend
on PostgreSQL. `GET /health/ready` reads one existing user row without changing
data and confirms the API can reach Cloud SQL. The former GitHub Actions
Supabase keepalive workflow was removed on 2026-11-17: Cloud SQL does not pause
for inactivity, so no external pinger is needed.

Scheduled work is driven by Cloud Scheduler (`vimj-minute-dispatch`, every
minute) which enqueues jobs into the Cloud Tasks queue `vimj-scheduled-jobs`;
each task calls `POST /internal/scheduler/run` with an OIDC token and is
recorded in the `scheduler_job_executions` ledger (one row per job and
scheduled minute, so retries cannot double-send). The in-process scheduler is
disabled in production, and there must only ever be one active scheduler.

The API defaults to one Gunicorn worker on Cloud Run's 1-vCPU instance and uses
a bounded SQLAlchemy pool (2 connections per worker) over the Cloud SQL socket;
Cloud SQL `deepak20` allows 50 connections. `WEB_CONCURRENCY` can override the
worker count on a larger plan. The Cloud Run service has a zero minimum-instance
setting, so an occasional cold start (about 10–15 s) can make one request time
out; Cloud Tasks retries scheduled requests automatically.

## Mobile push notifications

Android devices register an authenticated Firebase Cloud Messaging token at `/notifications/device-token`. Token registration is scoped to the signed-in Admin or Coach and removed on logout. Existing notification events continue to write the in-app notification row; the backend also sends a best-effort FCM alert using the Cloud Run service account's Application Default Credentials. No service-account key is stored in the repository. Foreground Android alerts use local notification rendering; Android displays FCM notifications when the app is backgrounded or closed. The Google Firebase project and Android app config must be provisioned before release. iOS push requires an Apple APNs key and app configuration and is not enabled by the Android APK release.

The Admin insight payload includes defaulter rows and the last three monthly collection totals so the Admin dashboard can display searchable, descending lists for Most Risk, Most Profit, and Future Forecast. Coach dashboard files and the Admin-only insights authorization remain separate.
