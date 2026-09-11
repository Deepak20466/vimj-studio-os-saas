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

### Notifications
- `GET /notifications` - List the caller's own notifications + unread count
- `PUT /notifications/{id}/read` / `PUT /notifications/read-all` - Mark read
- `DELETE /notifications/{id}` / `DELETE /notifications` - Delete one / clear all
  (2026-09-11). In-app bell/notification-center only — mobile deliberately does
  not mirror new items as OS-level notifications (see MOBILE below).

### Reset (2026-09-11)
- `POST /reset/all` - Admin-only: wipes attendance/fee/leave/salary/swap/
  compliance/receipt/notification history system-wide. Keeps Users, Activities,
  Batches, and generated ClassSessions intact.
- `POST /reset/mine` - Coach-only: wipes only the caller's own attendance/leave/
  swap history. Never touches another coach's data or any fee/salary/receipt record.

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
- **Notifications (2026-09-09, revised 2026-09-11):** a bell icon + full
  notification-center screen (`features/shared/notification_bell_action.dart` /
  `notification_center_screen.dart`) on the Dashboard/Classes/Leave/Swaps tabs,
  backed by a single app-wide poller (`core/notification_polling_service.dart`,
  mirrors `SyncService`'s one-service pattern — do NOT let individual screens
  poll `/notifications` themselves again, every `IndexedStack` tab stays alive
  at once and duplicate pollers means duplicate in-app notifications). Supports
  deleting one or all (2026-09-11). In-app only by explicit client decision as
  of 2026-09-11: new items do NOT pop as an OS notification (phone's
  notification shade/lock screen) anymore — `NotificationService`
  (`flutter_local_notifications`) is no longer called from anywhere
  (`main.dart` no longer calls its `init()` either, so the Android 13+ runtime
  notification-permission prompt is also gone). `notification_service.dart`
  itself is unused but left in the tree in case OS-level popups are wanted back
  — re-wiring it is a small, contained change (call `.init()` from `main.dart`
  and `.show()` from the poller), not a rebuild. True push (survives the app
  being fully closed, like WhatsApp) still needs Firebase Cloud Messaging and a
  real Firebase project — that's a separate, bigger effort, not what this toggle
  is: a `firebase_messaging`/`firebase_core` integration needing the academy's
  own Firebase project, a `google-services.json` file, and a backend-side
  sender using that project's credentials — none of which exists yet.

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

## 2026-09-11 CLIENT FEEDBACK ROUND — 10 fixes

1. **Mobile auto-logout, take 3**: `mobile/lib/core/api_client.dart`'s `_tryRefresh()`
   had a real concurrency bug the two earlier auto-logout fixes (see the 2026-09-09
   round below) didn't touch. It guarded against concurrent refreshes with a bare
   `bool _isRefreshing`, so when a screen fires several parallel GETs via
   `Future.wait` (most admin/coach tabs do) right as the 30-minute access token
   expires, only the FIRST 401'd request actually refreshed — every other
   concurrent one saw "a refresh is already in progress," immediately treated
   that as a failed refresh, cleared the stored session, and threw "Session
   expired." That silently logged the user out mid-session even though the real
   refresh was seconds from succeeding. Fixed by sharing one `Future<bool>?
   _refreshFuture` that every concurrent caller awaits instead of racing.
2. **Notifications**: added `DELETE /notifications/{id}` and `DELETE
   /notifications` (clear all) — wired into the web bell (`NotificationBell.jsx`)
   and the mobile notification center (`notification_center_screen.dart`). Also,
   per an explicit client request, mobile notifications are now in-app only:
   `NotificationPollingService` no longer calls `NotificationService.show()` (no
   more OS notification-shade/lock-screen popups), and `main.dart` no longer
   calls `NotificationService.init()` (no more runtime notification-permission
   prompt either). The in-app bell/badge/notification-center keep working
   exactly as before — only the "outside the app" OS popup was removed.
3.-6. **"Record/receipt not found" on delete/download (Attendance, Batches,
   Leave, Fees)**: every backend delete/PDF endpoint was verified correct via
   direct curl testing (valid IDs delete/download with 200/204 every time) — no
   server-side bug found in any of the four. The reported "not found" errors are
   consistent with acting on a stale row: the admin dashboard's lists are loaded
   once and don't self-heal if the same record is deleted/changed from another
   session (web + mobile used side by side) or by a duplicate tap during a slow
   response. Hardened defensively on mobile and web: each delete/download
   handler now guards against double-submission (disables the specific
   row's control while its request is in flight) and, on a 404 specifically,
   shows a neutral "already gone — refreshing" message and reloads the list
   instead of leaving a dead-end error on a stale row. Also fixed a real bug
   found while doing this: mobile's `ApiClient.getBytes()` (used for every
   PDF/CSV download) discarded the backend's actual error `detail` and always
   showed a generic "Download failed (404)", and the web equivalent had the same
   problem for any request made with `responseType: "blob"` (the error body
   decodes as a Blob, not JSON, so `err.response.data.detail` was always
   undefined) — see `frontend/src/utils/download.js`'s new `blobErrorDetail()`.
   Both now surface the real reason (e.g. "Fee must be marked paid..." instead
   of a bare status code).
7. **Reset Data**: new `POST /reset/all` (admin) and `POST /reset/mine` (coach)
   endpoints (`backend/app/routers/reset.py`). Admin's wipes attendance, fees,
   salary, leave, swaps, compliance (submissions/skip-reasons/class photos), fee
   receipts, fee-reminder drafts, and notifications system-wide — but
   deliberately KEEPS Users/Students/Coaches, Activities, Batches, and generated
   ClassSessions, so the app is immediately usable right after (nothing needs
   re-creating). Coach's only wipes their own attendance/leave/swap history,
   never another coach's data or any fee/salary/receipt record (those stay
   admin-controlled financial records per DATA ISOLATION). Both require the
   caller to type `RESET` to confirm on web and mobile (Settings.jsx /
   admin_settings_tab.dart for admin; CoachSalary.jsx / coach_profile_tab.dart
   for coach, under a "Danger Zone").
8. **Coach "Capture Photo" (My Students)**: the upload always worked
   (`POST /students/{id}/photo`) but nothing ever displayed the result — the
   roster row was a static person icon regardless of whether a photo existed,
   and the screen never refreshed after a successful capture. Coach mobile
   (`coach_students_tab.dart`) and coach web (`CoachStudents.jsx`) now fetch and
   show each student's photo as a small thumbnail next to their name, and
   refresh just that student's thumbnail immediately after a new capture
   succeeds — no full-roster reload needed.
9. **Admin visibility into coach-submitted photos**: student profile photos were
   already viewable by admin (`admin_students_tab.dart`'s `_StudentProfileSheet`,
   web `Students.jsx`) — no gap there. Attendance **selfies** were the real gap:
   the backend (`GET /attendance/selfie/{id}`) always worked, but nothing in
   either UI ever called it — web's `AttendanceAPI.selfieUrl` was dead,
   unreachable code (a plain `<img src>` can't attach the Bearer token this API
   requires, so it could never have worked even if used) and mobile had no
   selfie button at all. Added `has_selfie` to `StudentAttendanceAdminOut`
   (`GET /attendance/students`) and a "View Selfie" action on both the web
   Attendance page (blob fetch, matching `StudentsAPI.photoBlob`'s pattern) and
   `admin_attendance_tab.dart` (`ApiClient.getBytes` + `Image.memory`).
10. **Coach batch/group photos**: same "uploads but never shows" gap as #8, in
   both coach Classes screens (`classes_tab.dart`, `CoachClasses.jsx`) — fixed
   the same way, with a small thumbnail strip next to each ended class,
   refreshed immediately after a new batch photo is captured. Admin's
   Compliance view already displayed these correctly on both platforms
   (`admin_compliance_tab.dart`'s `_viewPhotos`, web `Compliance.jsx`) — no
   changes needed there.

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