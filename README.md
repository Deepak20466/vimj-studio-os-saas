# VIMJ Studio Attendance Management System

Production-ready attendance system for a coaching studio: geofenced + selfie-verified
attendance, fee/salary reminders, leave & swap workflows, role-based data isolation, and
business analytics — across a FastAPI backend, a React admin dashboard, and a React
Native (Expo) mobile app for coaches and students.

## Structure

```
backend/    FastAPI + PostgreSQL API — all 15 core requirements, RBAC enforced server-side
frontend/   React admin dashboard (students, coaches, activities, attendance, leave, fees, reports)
mobile/     React Native (Expo) app for coaches (mark attendance, leave, swaps, salary) and
            students (attendance history, fees, profile)
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

# 3. Mobile (new terminal)
cd mobile
npm install
npm start   # press 'a' for Android, 'i' for iOS, or scan the QR code with Expo Go
```

## What's been verified in this environment

- **Backend**: imports cleanly, and an end-to-end smoke test (auth, RBAC/data-isolation,
  geofencing, selfie upload + compression, fee/leave workflows, PDF/CSV export) passes
  against SQLite. See `backend/README.md` for how to point it at real PostgreSQL.
- **Frontend**: builds cleanly (`npm run build`) and was driven with a real login against
  the live backend — dashboard, students, and reports pages render with no console errors.
- **Mobile**: TypeScript compiles cleanly (`npx tsc --noEmit`), the Metro bundle builds
  successfully end-to-end (`npx expo export`), and `npx expo-doctor` reports no issues.
  No physical device/emulator was available to run it here, so every API call was
  cross-checked by hand against the actual backend route signatures. See
  `mobile/README.md` for setup and the backend URL configuration.

## Production deployment

No Docker, per the spec. See `backend/README.md` for gunicorn + systemd + Nginx, and
`backend/nginx.conf.example` for reverse-proxying the API and serving the built React app.
