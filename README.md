# VIMJ Studio Attendance Management System

**Built and maintained by K Deepak.** Licensed under the [MIT License](LICENSE).

Production-ready attendance system for a coaching studio: manually-entered attendance
(Present/Absent/Leave/Not Confirm) with an admin-approval lock, fee receipts/reminders,
leave requests, role-based data isolation, and business analytics — across a FastAPI
backend, a React admin/coach dashboard, and a Flutter mobile app for coaches and admins.
Students never get a login (see CLAUDE.md) — they exist only as records admins and coaches
manage.

Both dashboards were deliberately rebuilt to reduced scopes at the client's request across
several 2026-09-12/13 rounds (see CLAUDE.md's "ADMIN DASHBOARD REBUILD", "COACH DASHBOARD
REBUILD", and "2026-09-13 CLIENT FEEDBACK" sections for the full story) — Salary, Coach
Swapping, Chat, Compliance, the standalone Reports/Analytics section, and GPS/selfie-verified
attendance are gone system-wide; do not re-add any of them without an explicit decision to do
so. The admin Activities/Batches UI, cut in one of those rounds, was restored afterward at the
same client's request — see CLAUDE.md's "ACTIVITIES/BATCHES RESTORED" section.

A 2026-09-14 round (see CLAUDE.md's "2026-09-14 CLIENT FEEDBACK" section) added search boxes to
the admin Fees list and the Activities roster views, a paid/unpaid fee tag on the admin Students
list (web and mobile, full parity per an explicit client instruction), fixed three real bugs
found while testing Activities/Batches end-to-end (a backend schema bug that broke editing a
class's date, an admin Dashboard crash on a failed data fetch, and a mobile Batches "Coverage"
panel going stale after edits), and removed a mobile-only biometric-unlock gate that was forcing
re-authentication on every app open even with a valid session — sessions now persist until the
user explicitly logs out, on both platforms.

A same-day follow-up round (see CLAUDE.md's "2026-09-14 CLIENT FEEDBACK — round 2" section) added
a search field to the Activities "Enroll Student" picker (web and mobile — the roster search
above only covered the already-enrolled list, not this one), and a per-row Delete/dismiss action
on the "Coaches Missing Attendance Today" report wherever it appears (Dashboard and Attendance,
web and mobile) — that list has no backing database row to actually delete, so "delete" hides the
row locally (`localStorage`/`SharedPreferences`), matching the notification bell's
read-or-ignore-then-delete pattern.

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
  every real bug found and fixed (root cause + what changed), including the 2026-09-12/13
  dashboard-rebuild rounds and the subsequent Activities/Batches restoration. Read this before
  touching auth, notifications, photo storage, or the attendance-approval/leave workflow — each
  has non-obvious history worth knowing first. This is also the file to update whenever a fix's
  root cause or a new endpoint is worth leaving a note for the next person working on this repo.
