Act as a senior developer and build a complete Production-ready Attendance Management System. *First inspect the existing repository and do not rewrite working functionality unnecessarily.* If this a new project create the architecture below.

> **⚠️ 2026-09-12 — Both dashboards rebuilt to reduced scopes, same day.** The
> admin dashboard was rebuilt first around 7 sections (Students, Coaches,
> Attendance, Activities incl. Batches, Fees, Settings, Notifications), then
> the coach dashboard was rebuilt around 6 sections (Students, Attendance incl.
> an admin-approval lock + photo, Leave, Fees, Settings, Notifications) in a
> second round the same day. The 15 requirements and full API list below are
> the **pre-2026-09-12 architecture** — still accurate for anything not called
> out in the "2026-09-12 ADMIN DASHBOARD REBUILD" and "2026-09-12 COACH
> DASHBOARD REBUILD" sections near the end of this file. Leave came back
> system-wide as part of the coach round (it had been deleted in the admin
> round) with a fresh, simpler shape — coach requests, admin approves/rejects,
> no leave-balance concept, no leave-blocking of attendance marking. Salary,
> Coach Swapping, Chat, and Compliance remain deleted and are NOT coming back
> as part of this round. Do not "fix" old broken calls by resurrecting deleted
> backend without an explicit decision to do so.
>
> **⚠️ 2026-09-13 — follow-up correction, same client.** Two more changes, see
> "2026-09-13 CLIENT FEEDBACK" near the end of this file: (1) attendance
> marking (both a coach marking a student, and a coach's own facility
> check-in) dropped GPS/selfie verification entirely for plain manual entry —
> Present/Absent/Leave/**Not Confirm** (a genuine new 4th status) — and a
> coach can no longer self-edit a mark at all once submitted, not even
> same-day (tighter than the coach-round's approval-lock). (2) Activities and
> Batches were removed from the admin dashboard entirely (they had been kept,
> folded together, in the 2026-09-12 admin rebuild) — admin now has no UI to
> create a new Activity/Batch/manually generate sessions; the underlying data
> model and every read usage elsewhere is untouched and still works.

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
> **Superseded 2026-09-12 — see "COACH DASHBOARD REBUILD" above for the
> current, accurate section list.** The bullet list below describes the
> pre-2026-09-12 design (9 sections including Swaps/Chat/Salary) and is kept
> only for its still-accurate mechanics (GPS/selfie flow, offline queue,
> notification poller, biometric login, theme). As of 2026-09-12 the coach app
> has exactly 6 sections — Students, Attendance (now with an admin-approval
> lock + photo visibility), Leave (resurrected in a simpler shape), Fees
> (Receipts/Fee Reminders), Settings (new — profile edit/password/theme/reset),
> and the Notifications bell — with Swaps/Chat/Salary and the Compliance-tied
> half of Classes (batch photo, not-conducted, late-reason) deleted. Bottom-nav
> shell (`lib/features/coach/coach_home.dart`) is now 4 primary tabs
> (Dashboard/Classes/Students/Attendance) + a "More" sheet (Leave/Receipts/Fee
> Reminders/Settings).

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
> **Superseded 2026-09-12 — see "ADMIN DASHBOARD REBUILD" above for the
> current section list** (Dashboard, Students, Coaches, Attendance, Activities
> incl. Batches, Fees, Settings incl. Academy Profile, Notifications — plus a
> `AdminLeaveTab` added back into the "More" sheet in the coach-rebuild round
> right after). Compliance, Salary, Reports, and About are gone; Batches
> stayed mobile-only (stripped of its swap-dependent panels) rather than
> folding into Activities the way web did.

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

## 2026-09-12 ADMIN DASHBOARD REBUILD — client-directed feature cut

Client feedback: the admin dashboard had grown too large and bug-prone.
Instruction was to delete entire sections rather than keep patching them, and
rebuild the admin side around exactly 7 requirements, same brand colors. Coach
requirements are being defined separately in a follow-up round — the coach app
was **not** touched to that new spec this round (see the warning banner at the
top of this file).

**Deleted system-wide** (backend routers + models + schemas + DB tables via
Alembic migration `0013`, web pages/components, mobile tabs/screens):
Leave (`CoachLeave`), Salary (`CoachSalary`), Coach Swapping (`CoachSwap`),
Chat (`ChatMessage`), Compliance (`AttendanceSubmission`, `ClassSkipReason`,
`ClassPhoto` — late-attendance approval, class-not-conducted reasons, batch
photos), and the standalone Reports/Analytics section (`/reports/*`:
individual student/coach reports, monthly business analytics, 100%-attendance
coaches, month-over-month comparison, CSV/PDF exports for those). Requirement
items #3 (coach attendance reminder's late-approval half), #7 (salary
acknowledgment), #8 (coach swapping), #10 (end-of-day missing report's
leave-exclusion logic), #11/#12 (leave management/approval), and #13
(100%-attendance report) from the original 15 no longer exist. Attendance
marking itself (`POST /attendance/mark-student`) is simplified: no more
leave-blocking, no more swap-covering-coach check, no more late-submission
tracking — a coach can only mark their own assigned class, full stop.

**New:** `GET /dashboard/summary` / `/dashboard/fee-status` /
`/dashboard/activity-attendance` (`backend/app/routers/dashboard.py`) replace
`/reports/dashboard-summary`, `/reports/fee-status-graph`, and
`/reports/monthly-analysis`'s `activity_breakdown` respectively, feeding the
same bar/pie charts (recharts on web, fl_chart on mobile) that already existed
on the Dashboard — the visual design didn't change, only where the data comes
from. Admin can now also CRUD **coach** facility attendance manually (add/edit/
delete), not just student attendance: `GET/POST /attendance/coaches`,
`POST /attendance/coaches/manual`, `PUT`/`DELETE /attendance/coaches/{id}`
(web: second section on the Attendance page; mobile: second section on
`admin_attendance_tab.dart`). Fee receipts (`GET /fees/{id}/receipt`,
`GET /receipts/{id}/pdf`) now take `fmt=pdf|csv` and `disposition=
attachment|inline` query params — same `receipt_pdf.py` template/logo/colors,
just also exportable as CSV and viewable inline (web: opens a new tab; mobile:
still shares via the OS share sheet, `fmt` just changes the shared file's
extension/content). Settings gained an Academy Profile editor (`AcademyAPI`,
pre-existing backend, previously only reachable via the deleted "About" page)
and a coach activate/deactivate toggle, on both web and mobile.

**Web nav** (`frontend/src/App.jsx`'s `ADMIN_LINKS`) is now exactly: Dashboard,
Students, Coaches, Attendance, Activities, Fees, Settings — Batches was folded
into Activities' pre-existing per-activity "Sessions" modal (batch CRUD +
roster) rather than kept as a 8th top-level page; `pages/Batches.jsx` was
deleted. **Mobile** (`admin_home.dart`) kept Batches as its own "More"-sheet
entry instead (stripped of the Reassign-Coach/Pending-Swap-Requests/Recent-
Reassignments panels, which were swap-dependent) — a deliberate small
divergence from web, not an oversight; both approaches satisfy requirement 4
("Batches creation with proper crud options... your preferred specifications").

**Per-student/coach/activity "View Report" buttons removed** from Students.jsx,
Coaches.jsx, Activities.jsx (web) and their mobile equivalents — they opened
`StudentReportPanel`/`CoachReportPanel`/`ActivityReportPanel` (web, now
deleted) or `ReportScreen`/`ActivityReportScreen` (mobile, now deleted), both
of which called the now-gone `/reports/*` endpoints. Plain CRUD (add/edit/
delete/activate/deactivate) remains on all three, matching requirements 1 and
2's literal wording.

**Left alone / still present, do not re-delete:** `academy.py` (backend
router/model) — kept because it now backs the Settings > Academy Profile
editor; `receipts.py` and `fee_reminders.py` (coach-submitted, admin-approved
fee receipts/reminders) — not on the client's deletion list, still feed the
Fees page's approval queues; `services/export.py`'s `rows_to_csv`/
`rows_to_pdf` — trimmed of the two Reports-only PDF builders
(`build_monthly_analysis_pdf`, `build_coach_monthly_report_pdf`) but kept for
reuse by the new fee-receipt CSV export; `coaches.py`'s `GET /coaches/
directory` endpoint — originally described as "used to pick a covering coach
for a swap," now unused by admin but harmless, left in place.

**Verified live, not just by inspection** (per this repo's testing
convention): backend endpoints curl-tested directly (dashboard charts, coach-
attendance manual CRUD, fee receipt CSV); web frontend driven end-to-end with
Playwright/Firefox (22/22 scripted checks — login, simplified nav, dashboard
charts, student CRUD create+delete, coach-attendance CRUD create+list+delete,
fees View/PDF/CSV buttons, Settings Academy Profile + coach activate toggle);
mobile driven via the established Flutter web-server (port 8082) +
Playwright/Firefox coordinate-click technique (`flutter analyze`: 0 errors/
warnings; screenshotted the Dashboard's live bar+pie charts, the Attendance
tab's Student and Coach sections with real CRUD data, the More sheet's exact
5-item contents, the Fees screen's PDF/CSV buttons, and Settings' Academy
Profile + coach account list) — no Android emulator available in this
environment, so the native share-sheet/PDF-viewer behavior on a real device
is still unverified, consistent with prior sessions' documented limitation.

---

## 2026-09-12 COACH DASHBOARD REBUILD — client-directed feature cut, round 2

Same day as the admin rebuild above, same client pattern (see
`[[feedback-cut-scope-not-patch]]` in memory): a short numbered list of exactly
6 requirements, everything else gone. Unlike the admin round, one previously-
deleted feature came back — **Leave management** — but reshaped to the new,
simpler spec rather than restored as it was.

**The 6 requirements, mapped to what shipped:**
1. **Students** — already full CRUD on both web (`CoachStudents.jsx`) and
   mobile (`coach_students_tab.dart`); untouched, no gap existed.
2. **Attendance marking + admin-approval lock + photo visibility** — new. Every
   `StudentAttendance` row now carries `approval_status` (`PENDING` on a
   coach's own mark, auto-`APPROVED` on an admin manual entry). While
   `PENDING`, the marking coach can still edit/delete it same-day exactly as
   before; the moment admin approves or **rejects** it via the new
   `PUT /attendance/students/{id}/approve` / `.../reject`, it is **permanently
   locked from the coach's side** — a reject does NOT reopen it for
   re-marking, only admin's own manual-entry/edit/delete tools can still touch
   it (an explicit client choice, not the default "reopen on reject" option).
   The selfie a coach already captured on marking is now visible to the coach
   too, not just admin: web's `CoachClasses.jsx`/`CoachAttendance.jsx` and
   mobile's `mark_attendance_screen.dart`/`coach_facility_attendance_tab.dart`
   all gained a "View Photo" action (same authenticated-blob pattern as the
   existing admin "View Selfie", `GET /attendance/selfie/{id}` already allowed
   the marking coach — no backend RBAC change needed there). Admin's
   `Attendance.jsx` / `admin_attendance_tab.dart` gained Approve/Reject actions
   per pending row (shown only while `approval_status == PENDING`) and a
   review-status filter/column. Deliberately scoped to **student** attendance
   only — coach's own facility entry/exit (`CoachAttendance`) has no approval
   concept, since the client's wording ("attendance of each student") pointed
   at student records specifically; adding it there would have been scope
   creep nobody asked for.
3. **Leave management** — resurrected system-wide with a fresh, simpler shape
   (new `CoachLeave` model/table via Alembic `0014`, new
   `backend/app/routers/leave.py`): coach `POST /leave/request` /
   `GET /leave/my` / `DELETE /leave/{id}` (cancel, PENDING-only), admin
   `GET /leave/pending` / `GET /leave` / `PUT /leave/{id}/approve|reject`. No
   leave-balance/entitlement concept (the old pre-cut design had one; this
   round's client list didn't ask for it) and no generic edit endpoint (cancel
   and resubmit instead) — both deliberate simplifications, not oversights.
   Leave does **not** block attendance marking (the original requirement #12's
   behavior) — that coupling was cut along with everything else in the admin
   round and nothing in this round's client list asked to bring it back. New
   web `pages/Leave.jsx` (admin, added as an 8th top-level nav item — the
   client's explicit choice over folding it into an existing page, unlike how
   Batches folded into Activities) and `pages/coach/CoachLeave.jsx`; new mobile
   `admin_leave_tab.dart` (recreated from scratch — the pre-cut version was
   deleted in the admin round) and a simplified `leave_tab.dart` (dropped its
   old balance-grid and edit-mode).
4. **Fees — receipt PDF/CSV view + download** — the backend
   (`GET /receipts/{id}/pdf?fmt=pdf|csv&disposition=inline|attachment`) already
   supported this from the admin round; the gap was purely in the coach UI.
   Web `CoachReceipts.jsx` gained View (inline, new tab) alongside the
   existing PDF download, plus a CSV button. Mobile `coach_receipts_tab.dart`
   gained a CSV share-sheet export alongside the existing PDF one (no inline
   "View" on mobile — this app's established convention is share-sheet-only
   exports on mobile, there's no in-app PDF viewer anywhere else either, so
   PDF+CSV via share sheet already satisfies "view and download" on this
   platform). Same receipt PDF template/logo/colors throughout — untouched.
5. **Settings — reset + "some extra functions"** — the coach reset-mine danger
   zone already existed on mobile only; web had **no coach Settings page at
   all**. New web `pages/coach/CoachSettings.jsx` and a repurposed mobile
   `coach_profile_tab.dart` (kept the filename, dropped its dead
   attendance-%/salary-history section) both now offer: profile edit
   (name/phone/login email via an extended `PUT /auth/me`, which gained
   optional `name`/`phone` fields), password change, a theme toggle, and the
   reset-mine danger zone (copy corrected to no longer mention "swap history").
   `POST /reset/mine` and `POST /reset/all` were extended to also wipe
   `CoachLeave` rows.
6. **Notifications + light/dark mode** — the in-app bell/notification-center
   (web `NotificationBell.jsx`, mobile's polling service) was already generic
   and unaffected by any of this — no changes needed. Real SMS for
   coach-facing notifications was explicitly declined (client's own choice
   when asked): stays in-app only, `NOTIFICATIONS_ENABLED` stays `false` in
   production, same as every other notification in this system. Dark/light
   mode already existed (web `Layout.jsx` topbar toggle, mobile
   `ThemeToggleTile`) — now also duplicated into the new Settings pages on
   both platforms for discoverability, matching the admin app's pattern.

**Deleted system-wide** (the coach-side leftovers that were already broken
after the admin round, per that section's warning): Coach Swapping
(`frontend/src/pages/coach/CoachSwaps.jsx`, mobile `swap_tab.dart`), Chat
(`CoachChat.jsx`, `components/ChatThread.jsx`, mobile `coach_chat_tab.dart`),
Salary (`CoachSalary.jsx` and the salary-history half of
`coach_profile_tab.dart`), and the Compliance-tied half of the class-marking
flow (batch-photo upload, "class not conducted" reporting, late-mark reason —
`frontend/src/pages/coach/CoachClasses.jsx` and mobile `classes_tab.dart` both
had this code even though the backend was already gone; now removed on both).
`frontend/src/api/endpoints.js`'s dead `SwapAPI`/`ChatAPI`/`ComplianceAPI`
exports and `CoachSelfAPI`'s dead leave/salary/report methods were deleted
outright (no longer needed as build-only stubs — new `LeaveAPI` replaces the
old leave methods).

**Web nav** (`frontend/src/App.jsx`): `ADMIN_LINKS` gained a `Leave` entry
before Settings (8 items total: Dashboard, Students, Coaches, Attendance,
Activities, Fees, Leave, Settings). `COACH_LINKS` is now exactly Dashboard,
Classes, Students, Attendance, Leave, Receipts, Fee Reminders, Settings (8
items, first 4 primary tabs + 4 in the "More" sheet via `Layout.jsx`'s
existing overflow pattern — no `Layout.jsx` changes needed). **Mobile**
(`admin_home.dart`): `AdminLeaveTab` inserted into the "More" sheet right
before Settings. `coach_home.dart`: primary tabs Dashboard/Classes/Students/
Attendance (Students and Attendance promoted out of the old "More" sheet);
More sheet now Leave/Receipts/Fee Reminders/Settings.

**Verified live** (not just by inspection, per this repo's testing
convention): backend curl-tested directly (leave request→approve→notify→
cancel-blocked cycle; attendance mark→admin-approve→coach-edit-blocked-400
cycle, and the reject variant; receipt create→approve→view-inline→
download-csv cycle; `PUT /auth/me` name/phone update; `/reset/mine` now
deleting leave rows too). Web driven end-to-end with Playwright/Firefox
(coach nav/More-sheet contents, Leave submit→admin-approve→coach-sees-status
round trip across two separate browser sessions, Settings profile+theme
render, Receipts View/PDF/CSV buttons all present and functional). Mobile
driven via the same Flutter web-server (port 8082) + Playwright/Firefox
coordinate-click technique used in the admin round: `flutter analyze` clean
(0 errors/warnings, same 14 pre-existing info-level notices as before this
change); screenshotted and functionally exercised the coach bottom-nav/More
sheet, the Leave screen (confirmed it reflects a decision made from the web
session moments earlier — real cross-platform state, not two disconnected
mocks), the Settings screen (profile fields correctly pre-filled from
`GET /auth/me`, corrected danger-zone copy), the coach Attendance tab's
"View Photo" action (the actual uploaded selfie bytes rendered, not a
placeholder), and the admin side's Approve action on both the Attendance tab
(status flipped PENDING→APPROVED live, action icons correctly disappeared
afterward, confirmation snackbar shown) and the new Leave tab (pending
request moved into history as APPROVED live). No Android emulator available
in this environment, so real-device-only concerns (gesture-nav safe areas,
native share-sheet behavior) remain unverified here, consistent with every
prior mobile round's documented limitation — worth a real-device smoke test
before assuming the CSV export share sheet is flawless.

Backend (port 8000) and web frontend dev server (port 5173) were left running
at the end of this session; the Flutter web-server test instance was shut
down. Hit the login rate limiter (`LOGIN_RATE_LIMIT=5/15minutes`) again from
repeated test logins across curl + two separate Playwright passes (web and
mobile) — bumped it to `200/15minutes`, restarted the backend, and **restored
it to `5/15minutes` + restarted again** before finishing, per the existing
gotcha noted in the admin-round section above.

---

## 2026-09-13 CLIENT FEEDBACK — GPS/selfie removed from marking, Activities/Batches cut

Third round from the same client, same day-after the coach rebuild above. Two
items, both implemented exactly as specified (no incidental changes):

1. **Attendance marking is now pure manual entry — no GPS, no selfie, and
   locked the instant it's submitted.** This applies to BOTH surfaces that
   used to be geofenced: a coach marking a student in "My Classes" AND a
   coach's own facility check-in on their Dashboard. The status options are
   now **Present / Absent / Leave / Not Confirm** — `NOT_CONFIRM` is a
   genuinely new 4th enum value (client's explicit choice over relabeling
   Leave), added to both `AttendanceStatus` and `CoachAttendanceStatus` via
   Alembic `0015` (`ALTER TYPE ... ADD VALUE` — Postgres 12+ allows this
   inside a normal transaction as long as the new value isn't *used* in that
   same transaction, which this migration doesn't do, so no autocommit/
   `transaction_per_migration` workaround was needed).

   - `POST /attendance/mark-student` no longer takes or validates
     `location_lat`/`location_lng`/`selfie_base64` — `MarkStudentAttendanceRequest`
     is now just `{student_id, class_id, status}`. The 60-minute post-class
     marking deadline is unchanged (not asked to be removed).
   - The old two-step `POST /attendance/coach-entry` / `POST /attendance/coach-exit`
     (GPS-gated, `entry_time`/`exit_time` pair) were **replaced outright** by
     a single `POST /attendance/coach-mark` (`{status, activity_id?}`, no
     location) — one manual mark per coach per day, 400 if already marked
     today. `CoachAttendance.entry_time` is still set (as a plain "marked at"
     timestamp, not a check-in), `exit_time` is simply never populated by this
     new flow (still nullable, still settable by admin's manual tools).
   - **Coach self-editing is gone entirely** — not just locked after admin
     review like the previous round, but locked from the moment of
     submission. `PUT /attendance/students/{id}` and
     `DELETE /attendance/students/{id}` are now `require_admin`-only (the old
     `_authorize_own_attendance_edit` coach branch, and the same-day exception
     it granted, no longer exist). This was an explicit client tightening
     ("once submit it cannot be changed further, if any changes required then
     only admin should approve") beyond what the coach-dashboard round shipped
     the day before.
   - `services/geofence.py` and `services/storage.py`'s `save_selfie` are
     **left in the tree, unused** by this flow — `get_selfie`/viewing a
     historical selfie on old records still works (has_selfie/View Photo
     stay functional for anything marked before this change), and nothing
     else currently calls geofence_check, but neither file was deleted since
     that wasn't asked and doing so would be a one-way door if a future round
     ever wants location data back.
   - Web: `CoachClasses.jsx`'s roster modal now shows 4 buttons instead of
     the old Present/Absent/Leave + camera flow, and marked rows show a
     permanent "Locked" state (no more same-day edit dropdown). `CoachDashboard.jsx`'s
     Check In/Check Out card became a single "My Attendance Today" pick.
     `CoachAttendance.jsx` dropped its edit/delete controls entirely (dead
     now that the backend 403s them) but keeps View Photo for legacy selfies.
     Admin's `Attendance.jsx` status dropdowns/filters gained `NOT_CONFIRM`
     everywhere `LEAVE` already appeared. New `--info` color token
     (`#4f46e5` light / `#818cf8` dark) and `.badge-not_confirm` class in
     `theme.css` — the first status not slotted into the existing
     success/warning/danger three-color system, since the client's whole
     point was a status genuinely distinct from Leave/Pending's existing
     yellow.
   - Mobile: `mark_attendance_screen.dart` mirrors the same 4-button/no-camera/
     locked-forever pattern (offline queueing still works for genuine network
     failures — `QueuedAttendance`'s `lat`/`lng` fields are now unused
     placeholders rather than a schema migration, since the local SQLite
     queue table's `NOT NULL` columns aren't worth a migration for a value
     nobody reads anymore). `coach_dashboard_tab.dart`'s check-in/out
     replaced with the same single manual pick. `coach_facility_attendance_tab.dart`
     and `admin_attendance_tab.dart` updated to match (dropdowns gained
     `NOT_CONFIRM`, coach-side edit/delete controls removed).

2. **Activities and Batches removed from the admin dashboard entirely** —
   client's explicit follow-up correction: the 2026-09-12 admin rebuild kept
   Activities (with Batches folded into it) as one of the 7 sections; this
   round says remove it, full stop. `frontend/src/pages/Activities.jsx`
   deleted, its route/nav entry removed from `App.jsx` (admin nav is now
   Dashboard/Students/Coaches/Attendance/Fees/Leave/Settings — 7 items became
   6 plus the Leave item added the day before). Mobile: `admin_activities_tab.dart`
   and `admin_batches_tab.dart` deleted, removed from `admin_home.dart`'s
   nav list.

   **Deliberately NOT touched**: the underlying `Activity`/`Batch`/
   `ClassSession` backend models, routers, and every *read* usage elsewhere
   (coach's own classes/roster, admin's manual attendance entry forms, the
   dashboard's activity-attendance chart, student enrollment, coach-activity
   assignment) — deleting those would cascade-break the entire attendance
   system, which is clearly not what "remove Activities section and Batches"
   meant. The practical consequence, told to the client: **admin now has no
   UI anywhere to create a new Activity, a new Batch, or manually trigger
   "Generate Sessions"** — the nightly `job_auto_generate_batch_sessions` cron
   still runs against whatever Batches already exist, but a brand-new
   activity/schedule needs direct database access until a future round
   decides to bring some UI back for it. `ActivitiesAPI`'s create/update/
   remove/enroll/unenroll methods and the entire `BatchesAPI` object in
   `frontend/src/api/endpoints.js` are now unreachable dead exports (left in
   place, same precedent as `academy.py`/`coaches.py`'s directory endpoint —
   harmless, not deleted since nothing asked for it).

**Verified live** (same techniques as every prior round): backend curl-tested
directly (mark-student with no location/selfie fields succeeds; NOT_CONFIRM
accepted; coach PUT/DELETE on their own record now 403s unconditionally;
admin PUT still works; `coach-mark` succeeds once then 400s on a same-day
retry). Web build clean (`npm run build`). Mobile `flutter analyze` clean (0
errors/warnings, 12 pre-existing info-level notices — 2 fewer than the prior
round because deleting `admin_batches_tab.dart` removed 2 of its own
pre-existing lint infos). Full click-through via the Flutter web-server +
Playwright/Firefox technique: confirmed no GPS/camera prompt fires anywhere
in the new marking flow, a Not-Confirm mark submits and instantly shows
"Locked" with zero edit controls, the coach Dashboard's "My Attendance Today"
correctly reflects a mark made earlier via curl (real cross-session state),
admin's Attendance tab shows the NOT_CONFIRM badge and approve/reject icons
correctly (icons disappear once decided), and admin's "More" sheet no longer
lists Activities or Batches.

---

## 2026-09-13 CLIENT FEEDBACK — coach group/batch photo (mobile only)

New, small feature request from the same client: one photo per finished class,
covering the whole roster, captured by the assigned coach — distinct from the
old compliance-era `ClassPhoto` feature (deleted in the 2026-09-12 admin round;
allowed many disk-stored photos per class with skip-reason/late-mark tracking
attached). This is a single photo per `ClassSession`, bytes-in-Postgres like
every other photo in this app. **Mobile coach app only**, by explicit client
choice — no web dashboard changes.

- `classes.group_photo` (`LargeBinary`) + `classes.group_photo_uploaded_at`
  columns added via Alembic `0016` (additive, no table rename/recreate).
  `ClassSession.has_group_photo` mirrors the `StudentAttendance.has_selfie`
  property pattern.
- `POST /activities/classes/{class_id}/group-photo` (`{photo_base64}`,
  `require_coach`) — only the class's assigned coach, and only after
  `now() >= class_end_dt` ("the class hasn't finished yet" 400 otherwise, same
  style as the existing mark-deadline checks). Re-uploading replaces the photo
  — no lock, unlike attendance marks. Reuses `services/storage.py`'s
  pre-existing (previously unused) `save_class_photo`.
- `GET /activities/classes/{class_id}/group-photo` — admin or the owning
  coach only, same authorization shape as `GET /attendance/selfie/{id}`.
- `ClassOut` gained `has_group_photo`/`group_photo_uploaded_at` so both
  `/activities/{id}/classes` and `/activities/classes/my` surface it without a
  separate call.
- Mobile: `classes_tab.dart`'s per-class row shows a "Group Photo" button once
  a class has ended (rear camera via the existing `image_picker` dependency —
  `CameraDevice.rear`, unlike the front-camera selfie/student-photo captures
  elsewhere in this app, since this photo is of the group, not the coach) and
  a "View Group Photo" button once one exists, with the same authenticated-
  blob `Image.memory` pattern as `mark_attendance_screen.dart`'s existing
  "View Photo" action.

**Verified live**: backend curl-tested directly against the local dev DB
(upload before class-end 400s with the expected message; upload after class-
end by the assigned coach succeeds and round-trips a real JPEG; a different
coach gets 403 on both upload and view of another coach's class; admin can
view any class's photo; unauthenticated requests 401). `flutter analyze`
clean (0 errors/warnings, same 12 pre-existing info-level notices as the prior
round — no new ones introduced). Hit the login rate limiter again from
repeated test logins — bumped `LOGIN_RATE_LIMIT` to `200/15minutes`, restarted
the backend, tested, then **restored it to `5/15minutes` and restarted again**.
No Android emulator/Flutter-web-server pass done this round (small, additive
UI change reusing an already-proven camera-capture pattern) — worth a real-
device smoke test of the camera flow before assuming it's flawless, consistent
with this project's standing mobile-testing caveat.

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