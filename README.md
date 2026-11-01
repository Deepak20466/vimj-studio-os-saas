# VIMJ Studio OS - Multi-Tenant Coaching Studio SaaS with MCP (100% Free, Local)

![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi)
![React](https://img.shields.io/badge/React-18-61DAFB?logo=react)
![Flutter](https://img.shields.io/badge/Flutter-Mobile-02569B?logo=flutter)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Database-4169E1?logo=postgresql)
![MCP Ready](https://img.shields.io/badge/MCP-Ready-7C3AED)
![Live](https://img.shields.io/badge/Live-Demo-success)
![Admin AI Command Center](https://img.shields.io/badge/Admin-AI%20Command%20Center-EA580C)

**Built and maintained by K Deepak.** Licensed under the [MIT License](LICENSE).

VIMJ Studio OS is a coaching-studio operations platform built with FastAPI, React, Flutter, and PostgreSQL. It provides manual attendance (Present/Absent/Leave/Not Confirm), fee ledgers and receipts, leave requests, role-based data isolation, and studio analytics. Students remain records managed by admins and coaches; they do not receive logins.

The Admin dashboard now includes a local, rule-based AI Command Center. The separate Coach dashboard keeps its student and attendance workflow and does not show revenue risk, forecasts, or profitability insights. MCP tools are restricted to an active Admin account.

Salary, GPS, Chat, and Compliance remain out of scope and are not reintroduced. No OpenAI or Gemini API is used; the predictions and MCP tools run against existing backend data.

## Live Demo

- **Backend:** https://vimj-backend-eqwnplgd6q-el.a.run.app
- **Web dashboard:** https://vimj-frontend-eqwnplgd6q-el.a.run.app
- **Demo admin:** `admin@vimj.com` / `Demo@123`
- **Video:** [Demo video placeholder](#video-demo-placeholder)

## Problem / Solution

Coaching centers lose money on manual registers and fee followups. VIMJ Studio OS replaces those scattered workflows with attendance records, fee tracking, reminders, and admin insights. This OS saves **8 hrs/week** on routine studio administration.

### Video demo placeholder

Add a product walkthrough video here when one is available.

## Structure

```
backend/    FastAPI + PostgreSQL API — RBAC enforced server-side
frontend/   React admin dashboard (students, coaches, attendance incl. approve/reject,
            activities incl. batches, fees, leave, settings) plus a coach web dashboard
            (students, classes, attendance incl. approval status, leave, fee
            receipts/reminders, settings)
mobile/     Flutter app mirroring both web dashboards for coaches and admins — see
            mobile/README.md
```

Each has its own README with setup steps: [backend/README.md](backend/README.md),
[frontend/README.md](frontend/README.md), [mobile/README.md](mobile/README.md).

## 🤖 Works with Claude Desktop via MCP

The local FastMCP server exposes these tools to Claude Desktop. **All five tools are Admin-only** and resolve an active Admin account from `VIMJ_MCP_ADMIN_EMAIL` before reading or changing data.

- `get_todays_absentees()` — list students marked absent today.
- `get_fee_defaulters(days_overdue=7)` — list overdue balances and total pending.
- `mark_attendance(student_id, status, date)` — mark Present, Absent, or Leave for one unambiguous scheduled class.
- `create_fee_reminder(student_id)` — queue a free mock WhatsApp reminder; no message is sent.
- `get_batch_analytics()` — estimated batch profitability, attendance drops, and revenue at risk.

The insights are deterministic local rules. No OpenAI, Gemini, or paid AI API is required. See [mcp_server/README.md](mcp_server/README.md) for setup and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for data flow.

## Quick start (development)

```bash
# 1. Backend
cd backend
python -m venv venv && venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env   # edit DATABASE_URL etc.
alembic upgrade head
python scripts/seed_admin.py --email admin@vimj.com --password "ChangeMe123!" --name "Admin"
uvicorn app.main:app --reload

# 2. Frontend (new terminal)
cd frontend
npm install
npm run dev   # http://localhost:5173, proxies /api to the backend

# 3. Mobile (new terminal, requires the Flutter SDK — android/ and ios/ are
#    committed with real customizations, see mobile/README.md; no `flutter
#    create` step needed)
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

## Production deployment

The API and React app run on Google Cloud Run in `asia-south1`; PostgreSQL is
hosted by Supabase. The API uses the Cloud Run URL above. Cloud Run currently
scales to zero when idle, so a cold request may take longer than a warm one.
The mobile app defaults to the same API URL; local builds can override it with
`API_BASE_URL`.

Mobile builds ship as sideloaded APKs (`mobile-vX.Y.Z` GitHub releases), not
the Play Store. See [mobile/README.md](mobile/README.md) for release steps.

## Where to look for more detail

- **CLAUDE.md** — the living spec: full requirements, API reference, and a dated history of
  every real bug found and fixed (root cause + what changed), including the 2026-09-12/13
  dashboard-rebuild rounds and the subsequent Activities/Batches restoration. Read this before
  touching auth, notifications, photo storage, or the attendance-approval/leave workflow — each
  has non-obvious history worth knowing first. This is also the file to update whenever a fix's
  root cause or a new endpoint is worth leaving a note for the next person working on this repo.
