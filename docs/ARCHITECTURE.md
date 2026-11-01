# VIMJ Studio OS Architecture

## Application layers

- **React web:** the Admin dashboard and Coach dashboard are separate protected routes. Admin-only command center data is requested from an Admin-guarded API; coach pages are unchanged and have no revenue-risk or forecast UI.
- **Flutter mobile:** the existing Admin and Coach experiences continue to use the same FastAPI API and role checks.
- **FastAPI:** SQLAlchemy models and PostgreSQL remain the source of truth. Existing attendance, fee, batch, and enrollment models power the new insights without schema migrations.
- **Local MCP:** `mcp_server/server.py` runs as a stdio FastMCP process for Claude Desktop. It reads the same database, resolves `VIMJ_MCP_ADMIN_EMAIL` to an active Admin on each call, and writes attendance/reminder audit records as that Admin. It does not expose a network port.

## Production hosting

The React dashboard and FastAPI API run as separate Cloud Run services in `asia-south1`:

- Web: `https://vimj-frontend-eqwnplgd6q-el.a.run.app`, built into a small Nginx container with SPA route fallback.
- API: `https://vimj-backend-eqwnplgd6q-el.a.run.app`, built from `backend/Dockerfile` on Python 3.12 so the pinned PostgreSQL driver installs from its binary wheel.
- Database: Supabase PostgreSQL, provided to the API through Secret Manager. The React image embeds the API origin at build time and does not carry database credentials.

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

Install `backend/requirements.txt` for FastAPI and `mcp_server/requirements.txt` in the isolated MCP environment. Configure `backend/.env` with a database connection and active Admin email, then add the MCP entry from the root `.mcp.json` to Claude Desktop's config. Setup details are in [mcp_server/README.md](../mcp_server/README.md).

## Free-tier health checks

`GET /health` is a lightweight liveness route and intentionally does not depend
on PostgreSQL. `GET /health/ready` runs a read-only `SELECT 1` and is used by
the scheduled [Supabase activity workflow](../.github/workflows/supabase-keepalive.yml)
every ten minutes. Its readiness probe reads an existing application user row,
so it produces database activity without modifying studio data. This is a
best-effort keepalive for Supabase Free, not a guarantee: Supabase's inactivity
policy can still pause Free projects, and only a paid Supabase plan guarantees
no inactivity pauses. A paused project must first be restored by its owner in
the Supabase dashboard.

The API defaults to one Gunicorn worker on Cloud Run's 1-vCPU instance. This
reduces memory pressure and ensures the in-process scheduler is not started
four times. `WEB_CONCURRENCY` can override the worker count on a larger plan.
The Cloud Run service still has a zero minimum-instance setting. Periodic
requests are a no-cost best effort to keep it warm; scale-to-zero can still
occur during maintenance or delayed workflow runs.
