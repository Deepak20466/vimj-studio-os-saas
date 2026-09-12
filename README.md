# VIMJ Studio Attendance Management System

Production-ready attendance system for a coaching studio: geofenced + selfie-verified
attendance with an admin-approval lock, fee receipts/reminders, leave requests, role-based
data isolation, and business analytics — across a FastAPI backend, a React admin/coach
dashboard, and a Flutter mobile app for coaches and admins. Students never get a login (see
CLAUDE.md) — they exist only as records admins and coaches manage.

As of 2026-09-12 both dashboards were deliberately rebuilt to reduced scopes at the client's
request (see CLAUDE.md's "2026-09-12 ADMIN DASHBOARD REBUILD" and "2026-09-12 COACH DASHBOARD
REBUILD" sections for the full story) — Salary, Coach Swapping, Chat, Compliance, and the
standalone Reports/Analytics section are gone system-wide; do not re-add them without an
explicit decision to do so.

## Structure

```
backend/    FastAPI + PostgreSQL API — RBAC enforced server-side
frontend/   React admin dashboard (students, coaches, attendance incl. approve/reject,
            activities incl. batches, fees, leave, settings) plus a coach web dashboard
            (students, classes, attendance incl. photo + approval status, leave, fee
            receipts/reminders, settings)
mobile/     Flutter app mirroring both web dashboards for coaches and admins — see
            mobile/README.md
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

# 3. Mobile (new terminal, requires the Flutter SDK — android/ and ios/ are
#    committed with real customizations, see mobile/README.md; no `flutter
#    create` step needed)
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

## Production deployment

No Docker, per the spec. Currently deployed on Render's free tier:
- Backend: `https://vimj-backend.onrender.com` (cold starts after ~15min idle take 20-40s —
  see `render.yaml` and CLAUDE.md's DEPLOYMENT section)
- Mobile builds ship as sideloaded APKs (`mobile-vX.Y.Z` GitHub releases), not the Play Store

For a non-Render target, see `backend/README.md` for gunicorn + systemd + Nginx, and
`backend/nginx.conf.example` for reverse-proxying the API and serving the built React app.

## Where to look for more detail

- **CLAUDE.md** — the living spec: full requirements, API reference, and a dated history of
  every real bug found and fixed (root cause + what changed), including the two 2026-09-12
  dashboard-rebuild rounds. Read this before touching auth, notifications, photo storage, the
  geofence logic, or the attendance-approval/leave workflow — each has non-obvious history
  worth knowing first. This is also the file to update whenever a fix's root cause or a new
  endpoint is worth leaving a note for the next person working on this repo.
