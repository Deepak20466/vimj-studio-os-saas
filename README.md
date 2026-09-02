# VIMJ Studio Attendance Management System

Production-ready attendance system for a coaching studio: geofenced + selfie-verified
attendance, fee/salary reminders, leave & swap workflows, role-based data isolation, and
business analytics — across a FastAPI backend, a React admin dashboard, and a Flutter
mobile app for coaches and students.

## Structure

```
backend/    FastAPI + PostgreSQL API — all 15 core requirements, RBAC enforced server-side
frontend/   React admin dashboard (students, coaches, activities, attendance, leave, fees, reports)
mobile/     Flutter app for coaches (mark attendance, leave, swaps, salary) and students
            (attendance history, fees, profile)
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

# 3. Mobile (new terminal, after installing the Flutter SDK)
cd mobile
flutter create --org com.vimjstudio --project-name vimj_attendance .
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

## What's been verified in this environment

- **Backend**: imports cleanly, and an end-to-end smoke test (auth, RBAC/data-isolation,
  geofencing, selfie upload + compression, fee/leave workflows, PDF/CSV export) passes
  against SQLite. See `backend/README.md` for how to point it at real PostgreSQL.
- **Frontend**: builds cleanly (`npm run build`) and was driven with a real login against
  the live backend — dashboard, students, and reports pages render with no console errors.
- **Mobile**: Flutter isn't installed on this machine, so `lib/` couldn't be compiled or
  run here. Every API call in the Dart code was cross-checked by hand against the actual
  backend route signatures. See `mobile/README.md` before your first run — it documents
  the one-time `flutter create` scaffolding step and required platform permissions.

## Production deployment

No Docker, per the spec. See `backend/README.md` for gunicorn + systemd + Nginx, and
`backend/nginx.conf.example` for reverse-proxying the API and serving the built React app.
