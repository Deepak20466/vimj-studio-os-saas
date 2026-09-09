Act as a senior developer and build a complete Production-ready Attendance Management System. *First inspect the existing repository and do not rewrite working functionality unnecessarily.* If this a new project create the architecture below.

# VIMJ Studio Attendance System -

**Tech Stack:**  Frontend web - react js, dashboard ui, analytics charts, React ui.
Frontend app - Flutter (Dart), location, Camera selfie, Notifications (Sms, Whatsup).
Backend - Python, FastApi.
Database - PostgreSQL.
Sms and whatsup - Python.
UI color - #FFA500, #FFF500, #F0F8FF.
---

## ROLES & PERMISSIONS
- **Admin:** View all data, approve leaves, generate reports, manage users with CRUD options in every section
- **Coach:** Mark only own class attendance, can't see other coaches' data, request leave, view own salary/attendance

Students do NOT get login access to any app. They exist only as records
(attendance subjects, fee accounts) that admins and coaches manage — the
backend rejects any login attempt from a Student-role account. Do not
reintroduce a student-facing login/app without an explicit decision to do so.


---

## 15 CORE REQUIREMENTS

### 1. ATTENDANCE TRACKING
- Track student attendance per class with coach name & timestamp
- Manual entry option for admin
- Attendance status: Present/Absent/Leave

### 2. FEE REMINDER
- Auto in every - month of 10th date - fee reminder notification (with sms, whatsup)
- Show paid/unpaid status
- Track outstanding balance

### 3. COACH ENTRY/EXIT
- Record coach arrival time (facility entry)
- Record coach departure time (facility exit)
- Link to assigned activity

### 4. COACH ATTENDANCE REMINDER
- Auto-reminder 15 min after class end time
- Coaches mark attendance after class completes
- Prevents marking after deadline

### 5. ADMIN CONTROL
- Admin sees all activities & attendance
- Can access all student/coach reports
- Can manually manage all records

### 6. DATA ISOLATION
- Coaches CANNOT see other coaches' attendance/activities/students
- Students CANNOT see other students' attendance/fees
- Enforce at API layer (not just UI)

### 7. SALARY ACKNOWLEDGMENT
- Auto notification on 10th of every month
- Coaches acknowledge salary receipt
- Maintain salary history

### 8. COACH SWAPPING
- If coach unavailable, another coach takes class
- Original coach marked absent, covering coach marks attendance
- Track swap history
- Whichever party didn't initiate the swap must accept it before it takes effect:
  admin-initiated reassignment needs the covering coach's accept/decline
  (`PUT /swap/{id}/respond`); coach-initiated requests need admin approval
  (`PUT /swap/{id}/approve|reject`, surfaced in the web/mobile admin UI, not
  just the API). See `backend/app/models/swap.py`'s `SwapInitiator`. Fixed
  2026-09-09 — previously admin-initiated swaps moved the class instantly
  with no consent step at all, and coach-initiated requests had a working
  endpoint but no admin-facing UI anywhere to decide them.

### 9. LIVE LOCATION VERIFICATION
- GPS geofencing (100m radius from facility as of 2026-09-09, raised from 50m —
  consumer GPS commonly drifts 20-50m indoors even with correct coordinates)
- Facility coordinates: `FACILITY_LAT`/`FACILITY_LNG` in `backend/app/config.py`,
  currently 12.9745723 / 77.5689324 — geocoded from the real facility's street
  address (near Chowdeswari Temple, TD Ln, Subhash Nagar, Cottonpete, Bengaluru
  560053), accurate to roughly a city block, NOT an exact pin. Replace with an
  exact Google Maps long-press pin if attendance marking ever fails
  unexpectedly near the real building — see `mobile/README.md`. The previous
  value (12.9716, 77.5946) was demo/placeholder central-Bangalore coordinates
  ~2.8km from the real facility and had never been corrected, so every
  real-world attendance mark failed unconditionally until this fix.
- Rejection messages now state the actual distance and limit (e.g. "You are
  340m from the facility — must be within 100m"), not a flat "outside the
  geofence" — a coordinate misconfiguration is now self-diagnosable from the
  error text instead of reading exactly like a dead button.
- Selfie photo verification during check-in
- Prevent marking attendance outside location
- Store photo proof with record (in the database as of 2026-09-09, not on
  disk — see DEPLOYMENT below)

### 10. END-OF-DAY REPORT
- Admin gets list of coaches who didn't mark attendance
- Automated daily report
- Action alerts for missing records

### 11. LEAVE MANAGEMENT
- Coaches submit leave requests (reason, dates)
- Stored in system for tracking
- Leave balance calculation

### 12. LEAVE APPROVAL
- Admin approves/rejects leave requests
- Coaches cannot mark attendance during approved leave
- Status notification to coach

### 13. 100% ATTENDANCE TRACKING
- Identify coaches with 100% student attendance
- Generate monthly analysis
- Admin report showing these coaches

### 14. BUSINESS ANALYTICS
- Per-activity: total classes, avg attendance %, revenue
- Overall facility: total students/coaches, monthly revenue, attendance rate
- Month-over-month comparison

### 15. REPORTS & GRAPHS
- Individual student/coach detailed reports
- Attendance graph (line chart by month)
- Activity-based breakdown (bar chart)
- Fee status (pie chart: paid vs unpaid)
- Leaves taken count
- Export to PDF/CSV

---

## DATABASE SCHEMA (PostgreSQL)

```
Users (id, email, password_hash, name, phone, role, created_at)
Activities (id, name, capacity, location_lat, location_lng, created_at)
Classes (id, activity_id, coach_id, date, start_time, end_time, created_at)

StudentAttendance (id, student_id, class_id, status, coach_id, timestamp, location_lat, location_lng, selfie_photo, created_at)
- status: PRESENT, ABSENT, LEAVE

CoachAttendance (id, coach_id, date, entry_time, exit_time, status, created_at)
CoachLeave (id, coach_id, start_date, end_date, reason, status, approved_by_admin_id, created_at)
CoachSwap (id, original_coach_id, covering_coach_id, class_id, date, created_at)

StudentFees (id, student_id, month, year, amount, status, due_date, paid_date, created_at)
- status: PAID, UNPAID, OVERDUE

CoachSalary (id, coach_id, month, year, amount, acknowledged_date, created_at)
UserDetails (id, user_id, address, phone, dob, profile_photo, created_at)
```

---

## BACKEND API (FastAPI)

### Authentication
- `POST /auth/login` - Login with email/password with forgot and recover password 
- `POST /auth/refresh` - Refresh JWT token. Rotates the refresh token on every call
  (returns a new one each time, not just a new access token) — makes the session a
  30-day *sliding* window (`REFRESH_TOKEN_EXPIRE_DAYS`) rather than a hard 7-day cap
  from original login, which is what "gets logged out on its own" actually was.
  Both web and mobile must persist the rotated refresh token, not just the access
  token, or this silently breaks again.
- `POST /auth/logout` - Logout

### Student Management
- `GET /students` - List students (admin only)
- `POST /students` - Create student (admin)
- `GET /students/{id}/attendance` - Student attendance history
- `GET /students/{id}/fees` - Student fee status

### Coach Management
- `GET /coaches` - List coaches (admin only)
- `POST /coaches` - Create coach (admin)
- `GET /coaches/{id}/attendance` - Coach attendance history
- `GET /coaches/{id}/salary` - Coach salary history

### Attendance
- `POST /attendance/mark-student` - Coach marks student (validate geofence + selfie)
- `POST /attendance/coach-entry` - Coach entry (validate geofence)
- `POST /attendance/coach-exit` - Coach exit (validate geofence)
- `GET /attendance/daily-missing` - Coaches without marked attendance (admin)

### Leave
- `POST /leave/request` - Coach submits leave
- `GET /leave/pending` - Pending requests (admin only)
- `PUT /leave/{id}/approve` - Approve leave (admin)
- `PUT /leave/{id}/reject` - Reject leave (admin)

### Fees
- `POST /fees/mark-paid` - Mark fee as paid (admin)
- `GET /fees/unpaid` - List unpaid fees (admin)

### Salary
- `POST /salary/acknowledge` - Coach acknowledge salary receipt
- `GET /salary/coach/{id}` - Coach salary history

### Swaps
- `POST /swap/request` - Coach requests another coach cover their class (needs admin approval)
- `POST /swap/admin-assign` - Admin proposes reassigning a class (needs the covering coach's acceptance — does NOT move the class until accepted)
- `PUT /swap/{id}/respond` - Covering coach accepts/declines an admin-initiated swap
- `PUT /swap/{id}/approve` / `PUT /swap/{id}/reject` - Admin approves/rejects a coach-initiated request
- `GET /swap/my` - A coach's own swaps (either side)
- `GET /swap/pending` - Coach-initiated requests awaiting admin decision (admin)
- `GET /swap/recent` - Most recent swaps of any status/initiator (admin)

### Reports
- `GET /reports/student/{id}` - Detailed student report
- `GET /reports/coach/{id}` - Detailed coach report
- `GET /reports/monthly-analysis` - Business analytics (admin)
- `GET /reports/100-percent-coaches/{month}` - Coaches with 100% attendance
- `GET /reports/attendance-graph/{user_id}` - Graph data (line chart)
- `GET /reports/fee-status-graph` - Fee breakdown (pie chart)

### Features
- Geofencing: Haversine formula, 100m radius validation (see LIVE LOCATION
  VERIFICATION above for the 2026-09-09 facility-coordinate fix)
- Auto-reminders: Scheduled tasks (end-of-month fees, 10th salary, 15min after class).
  As of 2026-09-09, every admin/coach-facing reminder writes an in-app bell
  notification (`notify_and_push`), not just SMS/WhatsApp — SMS/WhatsApp
  (`NOTIFICATIONS_ENABLED`) is off in production, so before this fix most of these
  reminders were invisible in practice. Student-facing messages (fee reminders,
  payment confirmations) remain SMS/WhatsApp-only since students have no login/bell.
- Batches: creating or updating a recurring schedule (`Batch`) now immediately
  generates the coach's upcoming dated classes (30 days ahead, same horizon as the
  nightly auto-generate job) instead of only the nightly job or a manual "Generate
  Sessions" click doing it — previously a newly-assigned schedule was invisible to
  its coach for up to ~24h, which read as "the coach never received the schedule."
- Image upload: selfies, student photos, and class/batch photos are stored as
  bytes directly in Postgres (2026-09-09), not on local disk — this host's
  filesystem is ephemeral (wiped on restart/cold-start), so disk-stored photos
  were silently lost shortly after upload. See DEPLOYMENT below.
- Response time: All endpoints <2 sec
- Rate limit: 5 login attempts per 15 min
- RBAC: Enforce at service layer - coaches can't access other coaches' data

---

## FRONTEND (React Admin Dashboard)

### Pages
- **Dashboard:** Total students, coaches, classes, monthly revenue
- **Students:** List, add, edit, individual report with attendance graph & fee status
- **Coaches:** List, add, edit, remove attendance history, leave management
- **Attendance:** Daily missing coaches, manual entry, verify selfies
- **Reports:** Student/coach individual reports, business analytics, graphs, export PDF/CSV
- **Leave:** Pending requests, approve/reject with reason input
- **Fees:** Unpaid list, mark paid, send reminder
- **Activities:** List, classes, activity analytics

### Features
- Search & filter on all lists
- Date range picker for reports
- Line/bar/pie charts with data export
- Confirmation dialogs for actions
- Toast notifications for feedback
- Mobile responsive layout

---

## MOBILE (Flutter)

One app, two logged-in experiences based on the account's role — students
never log in anywhere (see ROLES & PERMISSIONS). Originally coach-only, with
admin directed to the web dashboard instead; changed by explicit decision
(2026-09-07) to also support admin login natively in the app.

`mobile/android/` and `mobile/ios/` are committed to git (2026-09-09 fix) —
do NOT re-add them to `mobile/.gitignore` or treat them as disposable
`flutter create` output. Real, hand-added customizations only ever existed
inside them (the branded launcher icon, all runtime permissions, release
signing config) and were never on GitHub before this fix; every fresh
checkout silently reverted to Flutter's defaults. See `mobile/README.md`.

### Coach App
Bottom-nav shell (`lib/features/coach/`) with 4 primary tabs (Dashboard,
Classes, Leave, Swaps) plus a "More" sheet — same overflow pattern as the
web dashboard's `Layout.jsx` — for My Students, Fee Receipts, Fee Reminders,
Chat, and Profile. Full parity with the web coach dashboard's 9 sections
(as of 2026-09-08):
- **Dashboard:** Today's classes, mark attendance button, facility entry/exit
- **Mark Attendance:** GPS validation (50m), camera for selfie, confirmation with timestamp
- **Classes:** View assigned classes, mark multiple students, flag not-conducted, late-mark reason, batch photo
- **My Students:** Own roster grouped by assigned activity, add a student
- **Leave:** Submit request, view status, view approved/rejected history
- **Salary / Attendance history:** Folded into Profile — attendance %, salary history, acknowledgment (10th)
- **Fee Receipts:** Record a fee collected in person, pending admin approval
- **Fee Reminders:** Draft a reminder message, pending admin approval, copy once approved
- **Swaps:** Request a swap; accept/decline one an admin proposed. Web now has
  the equivalent (`frontend/src/pages/coach/CoachSwaps.jsx`, route `/coach/swaps`)
  as of 2026-09-09 — no longer mobile-only.
- **Chat:** Direct line to admin
- **Offline:** Queue marking offline, sync when online
- Biometric login (fingerprint)
- Dark/light theme
- **Notifications (2026-09-09):** a bell icon + full notification-center screen
  (`features/shared/notification_bell_action.dart` / `notification_center_screen.dart`)
  on the Dashboard/Classes/Leave/Swaps tabs, backed by a single app-wide poller
  (`core/notification_polling_service.dart`, mirrors `SyncService`'s one-service
  pattern — do NOT let individual screens poll `/notifications` themselves again,
  every `IndexedStack` tab stays alive at once and duplicate pollers means
  duplicate popped notifications). New items also pop as a real OS notification
  (phone's notification shade/lock screen) via `flutter_local_notifications` while
  the app process is alive — requires the Android 13+ runtime permission request
  in `notification_service.dart`'s `init()`, which is easy to accidentally drop if
  this file gets rewritten. This is NOT push (does not survive the app being fully
  closed for hours/days, unlike WhatsApp) — that needs Firebase Cloud Messaging,
  which needs a real Firebase project (the academy's own Google account) and
  hasn't been started; see the mobile `CHANGELOG.md` entry for what's needed.

### Admin App
Same login screen, routed by role. Bottom-nav shell (`lib/features/admin/admin_home.dart`)
as of 2026-09-09 — 4 primary tabs (Dashboard/Students/Coaches/Attendance) plus a
"More" sheet for the other 10, matching the Coach app and the web dashboard's
`Layout.jsx` pattern exactly (was a left `Drawer`, the only screen in the whole
system still using one — changed for consistency switching between the two apps).
Full parity with all 14 web admin dashboard sections (as of 2026-09-08):
Dashboard (stats + fee pie chart + coaches missing attendance), Students
(CRUD, activate/deactivate, individual report + CSV/PDF export via the
share sheet), Coaches (CRUD, manage activities, activate/deactivate,
individual report + export), Activities (CRUD), Batches (recurring
schedule CRUD, generate-sessions, day/month pickers — now with a "Pending Swap
Requests" approve/reject section as of 2026-09-09), Attendance (daily
missing + manual entry), Compliance (submitted/pending/delayed tracking,
late-attendance approval), Leave (approve/reject with note), Fees (unpaid
list, mark paid, remind, create), Salary (list, create, edit, delete),
Reports (business analytics), Chat (message any coach), Settings (own +
coach credentials — plus a dark/light theme toggle as of 2026-09-09, previously
only reachable from the coach app), About (academy profile). CSV/PDF export
opens the native share sheet (`share_plus`) since there's no browser download
folder on mobile. Same notification bell/center as the coach app, on the shell
AppBar (covers all 14 sections, unlike the coach app's per-tab placement).

---

## SECURITY
- Passwords: bcrypt 12+ rounds
- Sensitive data: encrypted at rest (salary, fees)
- HTTPS only
- CORS: only frontend domain
- Coaches can't query other coaches' data (API layer validation)
- Selfies/student photos/class photos: stored as bytes in Postgres (2026-09-09,
  moved off local disk — see DEPLOYMENT), served only through authenticated,
  access-controlled endpoints, never a public path
- Audit log: all attendance changes logged

---

## DEPLOYMENT (No Docker)
- Python venv: `python -m venv venv && pip install -r requirements.txt`
- Run backend: `gunicorn -w 4 -b 0.0.0.0:8000 main:app` (actual module path is
  `app.main:app`, not `main:app` — see `render.yaml`'s `startCommand`)
- Nginx: reverse proxy + static React files
- PostgreSQL: native installation with daily backups
- Currently deployed on Render (`https://vimj-backend.onrender.com`, free tier —
  cold starts after ~15min idle take 20-40s). Render's free tier has an
  **ephemeral filesystem**, wiped on every restart/cold-start — this is why
  selfies/photos moved off disk into Postgres (2026-09-09); do not reintroduce
  disk-based file storage for anything that needs to persist without first
  confirming the hosting plan has a real persistent disk.
- Systemd service file for auto-start (for a non-Render deployment target)

---

## SUCCESS CHECKLIST
✅ All 15 requirements implemented
✅ Coaches see only their own data (API enforced)
✅ Students see only own attendance/fees
✅ Geofencing prevents attendance outside 100m radius
✅ Selfie verification with timestamps
✅ All endpoints respond within 2 seconds
✅ Daily non-compliance reports generated
✅ Automated reminders (fees, salary, attendance)
✅ Monthly business analytics dashboard
✅ PDF/CSV export for all reports
✅ No Docker - direct server deployment
✅ Mobile offline support with sync
✅ Role-based access control enforced at API