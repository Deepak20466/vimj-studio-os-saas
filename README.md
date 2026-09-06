# VIMJ Studio Attendance Management System

Production-ready attendance system for a coaching studio: geofenced + selfie-verified
attendance, fee/salary reminders, leave & swap workflows, role-based data isolation, and
business analytics — across a FastAPI backend, a React admin/coach dashboard, and a
Flutter mobile app for coaches. Students never get a login (see CLAUDE.md) — they exist
only as records admins and coaches manage.

## Structure

```
backend/    FastAPI + PostgreSQL API — all 15 core requirements, RBAC enforced server-side
frontend/   React admin dashboard (students, coaches, activities, batches, attendance,
            compliance, leave, fees, salary, reports, about) plus a coach web dashboard
mobile/     Flutter app for coaches only (mark attendance, leave, swaps, salary,
            receipts, fee reminders) — see mobile/README.md
```

Each has its own README with setup steps: [backend/README.md](backend/README.md),
[frontend/README.md](frontend/README.md), [mobile/README.md](mobile/README.md).

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

# 3. Mobile (new terminal, requires the Flutter SDK — see mobile/README.md for
#    one-time native project setup, since android/ and ios/ aren't checked in)
cd mobile
flutter create --org com.vimjstudio --project-name vimj_attendance .
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

## What's been verified in this environment

This environment has no Python, Node, or Flutter SDK installed, so nothing below has been
executed — every change is a manual, careful read-through against the existing code and
conventions. Before trusting this in production, actually run:

- **Backend**: `alembic upgrade head` against a real Postgres DB, then `uvicorn app.main:app --reload`
  and exercise the endpoints via `/docs`.
- **Frontend**: `npm install && npm run dev`, then click through every admin and coach page
  with real admin/coach accounts.
- **Mobile**: generate the native projects per `mobile/README.md` and run on a device/emulator.

## Production deployment

No Docker, per the spec. See `backend/README.md` for gunicorn + systemd + Nginx, and
`backend/nginx.conf.example` for reverse-proxying the API and serving the built React app.
