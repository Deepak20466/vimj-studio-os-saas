# Features Added — 2026-09-06

This document maps each of the 11 requested features to exactly where it was implemented, for the existing VIMJ Studio Attendance Management System (FastAPI + PostgreSQL backend, React admin/coach web dashboard). Per the confirmed scope, all of this is **web-only** (React admin + the existing React coach pages) — the separate Flutter mobile app is untouched except for two pre-existing broken-asset-path bugs fixed under 1.3.

Every new endpoint follows the codebase's existing conventions (role-guarded via `Depends(require_admin/require_coach/...)`, `log_action(...)` audit entries before every commit, `notify()` for SMS/WhatsApp — all best-effort/no-op in dev unless Twilio env vars are set).

**Not yet run**: this environment has no Python or Node/npm available, so I could not execute `alembic upgrade head`, start the backend, or run the frontend dev server to test end-to-end. Everything below was written and manually re-read for correctness against the existing code, but you should run the verification steps at the bottom before trusting it in production.

---

## 1.1 Coach Salary Management

- **Backend**: `backend/app/routers/salary.py` — added `GET /salary` (admin, filterable by coach/month/year, lists every coach's salary ledger with acknowledgement status — previously admin could only `POST` blind, with no way to browse); `acknowledge_salary` now also `notify()`s every active admin when a coach acknowledges (previously silent).
  - Schema: `SalaryAdminOut` in `backend/app/schemas/salary.py`.
- **Frontend (admin)**: new page `frontend/src/pages/Salary.jsx` — a ledger list (coach, period, amount, notified date, acknowledgement badge) plus a "Record Salary" modal. Nav link + route added (`/salary`, `App.jsx`, `Layout.jsx` via `ADMIN_LINKS`).
- **Frontend (coach)**: `frontend/src/pages/coach/CoachSalary.jsx` was already implemented (acknowledge button) — unchanged.
- **API**: `SalaryAPI.list()` added in `frontend/src/api/endpoints.js`.

## 1.2 Activity-wise Attendance & Revenue

- **Backend**: `backend/app/routers/reports.py` — `/reports/monthly-analysis`'s per-activity breakdown now also returns `student_count`, `total_present`, `total_absent`, `total_attendance_marks`, and `revenue_collected` (previously only `total_classes`, `avg_attendance_pct`, and a purely projected `revenue`). New endpoint `GET /reports/activity/{activity_id}` returns a full single-activity report (student count, present/absent, fee paid/unpaid counts, a monthly attendance-graph, and a per-coach breakdown) — same shape/pattern as the existing student/coach reports.
  - Schemas: `ActivityBreakdown` (extended), `ActivityDetailReport`, `ActivityCoachBreakdown` in `backend/app/schemas/reports.py`.
  - **Note on "revenue"**: this schema doesn't tie a fee payment to a specific activity (a student can enrol in several activities but has one fee record per month). `revenue` stays the existing projection (monthly fee × enrolled count); the new `revenue_collected` is each student's *actual* paid fee for the month, split proportionally across their enrolled activities. This is documented in the Reports page UI itself.
- **Frontend (admin)**: `frontend/src/pages/Reports.jsx`'s activity table gained the new columns and a "View" button; `frontend/src/pages/Activities.jsx` gained a "Report" button per activity row. Both open the new `frontend/src/components/ActivityReportPanel.jsx` (stat cards, attendance line-chart, coach breakdown table — mirrors the existing `CoachReportPanel.jsx`/`StudentReportPanel.jsx` pattern).
- **API**: `ReportsAPI.activityDetail(id)` added.

## 1.3 App Branding

- Fixed a real pre-existing bug: `Layout.jsx` and `Login.jsx` referenced `/logo.png`, but the only logo asset on disk is `frontend/public/logo.jpeg` — the `<img onError>` was silently hiding a broken image on every page. Both now point at `/logo.jpeg`.
- `frontend/index.html` had no favicon at all — added `<link rel="icon">` and `apple-touch-icon` pointing at `/logo.jpeg`. Page `<title>` ("VIMJ Studio - Attendance Dashboard") was already correct and unchanged.
- Mobile app had the identical bug in two places (`mobile/lib/features/auth/login_screen.dart`, `mobile/lib/features/coach/coach_dashboard_tab.dart` both referenced `assets/images/logo.png`, but the file is `logo.jpeg`) plus `mobile/pubspec.yaml` declaring the non-existent `.png` as a Flutter asset (would fail asset bundling) — all three fixed to `.jpeg`.
- `mobile/pubspec.yaml` — added a `flutter_launcher_icons` dev-dependency + config pointing at the logo, with a comment explaining it needs to be run (`dart run flutter_launcher_icons`) after the native `android/`/`ios/` projects are generated (they aren't checked into this repo — see `mobile/README.md`), since there's no existing native project to bake a launcher icon into yet.
- "VIMJ Studio" branding/name was already used consistently throughout (top bar, login page, page title) — no further changes needed there.

## 1.4 Class/Session Not Taken

- **Backend**: new model `ClassSkipReason` (`backend/app/models/compliance.py`) — one row per class, unique on `class_id`. New router `backend/app/routers/compliance.py`: `POST /compliance/class-not-conducted` (coach, class must be theirs and already ended) notifies every active admin via `notify()` and records the reason; migration `backend/alembic/versions/0005_attendance_compliance.py`.
- **Frontend (coach)**: `frontend/src/pages/coach/CoachClasses.jsx` — a "Not Conducted" button appears on any of the coach's classes once it has ended, opening a reason prompt.
- **Frontend (admin)**: new page `frontend/src/pages/Compliance.jsx` shows every not-conducted class with its reason in the overview table (state = "Not Conducted").

## 1.5 Batch Management

- **Backend**: new model `Batch` (`backend/app/models/batch.py`) — activity, coach, location, session (Morning/Afternoon/Evening), start/end time, days-of-week. New router `backend/app/routers/batches.py`: full CRUD plus `POST /batches/{id}/generate-sessions` (date range → creates one `ClassSession` row per matching weekday, so all existing attendance/reporting code keeps working against `ClassSession` unchanged — batches are a template, not a replacement). `ClassSession` gained a nullable `batch_id` FK. `CoachSwap` gained `reason` and `batch_id` columns (previously had neither). New endpoint `POST /swap/admin-assign` (admin directly reassigns a class to a substitute coach, auto-approved, with a required reason) for the "temporarily reassign/swap a coach" requirement. Migration `0003_batches_and_coach_activities.py`.
- **Frontend (admin)**: new page `frontend/src/pages/Batches.jsx` — create/edit/delete batches (activity, location, session, time, day-toggle buttons, coach picker), a "Generate Sessions" date-range action per batch. The "Reassign coach for one date" action lives on `frontend/src/pages/Attendance.jsx`'s "Coaches Missing Attendance" table (a "Reassign" button per missing class, opening a modal to pick a substitute coach + reason, calling the new `swap/admin-assign` endpoint) — kept there rather than on the Batches page because reassignment needs a specific dated `ClassSession`, not the recurring template.
- **API**: `BatchesAPI` (new), `SwapAPI.adminAssign` (new).
- Note: coach-initiated swap requests and admin approve/reject (the original spec's requirement) already existed before this work and are unchanged.

## 1.6 Fee Receipt Approval

- **Backend**: new model `FeeReceipt` (`backend/app/models/fee_receipt.py`, status PENDING/APPROVED/REJECTED). New router `backend/app/routers/receipts.py`: `POST /receipts` (coach, must be assigned to one of the student's enrolled activities — reuses the new `CoachActivity` link from 1.7), `GET /receipts/my` (coach), `GET /receipts/pending` + `GET /receipts` (admin), `PUT /receipts/{id}/approve` (upserts/marks the matching `StudentFee` PAID, notifies both coach and student) and `PUT /receipts/{id}/reject` (notifies coach with the reason). This sits **alongside** the existing admin-only mark-paid flow in `fees.py`, which is untouched. Migration `0004_fee_receipts.py`.
- **Frontend (coach)**: new page `frontend/src/pages/coach/CoachReceipts.jsx` — submit a receipt for a roster student, see own receipt history + status.
- **Frontend (admin)**: `frontend/src/pages/Fees.jsx` gained a "Pending Fee Receipts" section above the existing fee table, with approve/reject actions.
- **API**: `ReceiptsAPI` (new).

## 1.7 Coach Login

- Coach login already existed (email/password, JWT) — unchanged.
- **Backend**: new model `CoachActivity` (`backend/app/models/coach_activity.py`) — an admin-managed many-to-many link between coaches and the activities they're authorized for (per the confirmed scope: activity assignment only, no separate boolean-permission system). New endpoints `GET/PUT /coaches/{id}/activities` in `backend/app/routers/coaches.py`. This link now drives: which activities a coach can be assigned to on a Batch, which activity a coach must pick when adding a new student (1.10), and which students a coach may bill a fee receipt for (1.6). Migration `0003_batches_and_coach_activities.py`.
- **Frontend (admin)**: `frontend/src/pages/Coaches.jsx` gained an "Activities" action per coach opening a checkbox modal.
- **Frontend (coach)**: `frontend/src/pages/coach/CoachStudents.jsx` reads `GET /coaches/{id}/activities` to show "My Activities" as section headers (this also serves as the "surface my assigned activities" read-only view).
- **API**: `CoachesAPI.getActivities/setActivities`, `CoachSelfAPI.myActivities`.

## 1.8 Attendance Delay/Missed Attendance

- **Backend**: new model `AttendanceSubmission` (`backend/app/models/compliance.py`) — one row per class, created on the coach's first student-mark for that class (`backend/app/routers/attendance.py`, `_get_or_create_submission`). A mark made more than `LATE_MARK_MINUTES = 10` after class end is flagged `is_late=True` (a separate, tighter threshold than the pre-existing hard `MARK_DEADLINE_MINUTES = 60` cutoff, which is unchanged). **Marking itself is never blocked by lateness** — that would have broken the untouched Flutter mobile app's existing mark flow for anything in the 10–60 minute window — a late mark is simply flagged for admin review. The coach can supply the reason inline (new optional `late_reason` field on `POST /attendance/mark-student`) or afterwards via `POST /compliance/late-reason`. Admin: `GET /compliance/pending` (submissions awaiting a decision) and `PUT /compliance/late/{id}/approve|reject`, both `notify()` the coach of the outcome. New scheduler job `job_missed_attendance_admin_alert` in `backend/app/services/scheduler.py` (every minute, same tight-window technique as the existing 15-min coach reminder, but at the 10-minute mark and notifying **admins** instead of the coach) — registered in `start_scheduler()`. Migration `0005_attendance_compliance.py`.
- **Frontend (coach)**: `frontend/src/pages/coach/CoachClasses.jsx` shows a late-reason textarea inline in the marking modal once a class is >10 min past end time.
- **Frontend (admin)**: `frontend/src/pages/Compliance.jsx` — "Pending Late-Attendance Approvals" table with Approve/Reject actions.

## 1.9 Before & After Class Attendance

- **Backend**: `GET /compliance/summary` in `backend/app/routers/compliance.py` (admin, filterable by date range/activity/coach) — for every scheduled class in range, computes one of: `SUBMITTED`, `PENDING` (deadline passed, nothing marked), `DELAYED` (late, awaiting admin decision), `NOT_CONDUCTED`, `LATE_APPROVED`, `LATE_REJECTED`, by cross-referencing `AttendanceSubmission` and `ClassSkipReason` (1.4/1.8's data) against each `ClassSession`.
- **Frontend (admin)**: `frontend/src/pages/Compliance.jsx`'s "Compliance Overview" section — stat cards (submitted/pending/delayed/not-conducted counts) plus a filterable per-class table showing state and the coach's reason/note. Nav link + route added (`/compliance`).
- **API**: `ComplianceAPI` (new — `summary`, `pendingLate`, `approveLate`, `rejectLate`, `classNotConducted`, `lateReason`).

## 1.10 Student Management

- **Backend**: `User` gained `phone_secondary` (`backend/app/models/user.py`); `UserDetails` gained `additional_details`. New schema `StudentCreate` (`backend/app/schemas/user.py`) makes both phone numbers mandatory for a new student and accepts an optional `additional_details`/`activity_id`. `POST /students` (`backend/app/routers/students.py`) now accepts **admin or coach** (`require_admin_or_coach`) — a coach must supply `activity_id` and must be linked to it via `CoachActivity` (1.7), which also auto-enrols the new student in that activity; admin retains unrestricted creation. Migration `0006_student_contact_and_photos.py`.
- **Frontend (admin)**: `frontend/src/pages/Students.jsx` — Add/Edit form gained Primary Phone + Secondary/Emergency Contact fields (both required on create) and an optional Additional Details field on create; the list table gained an "Emergency Contact" column.
- **Frontend (coach)**: new page `frontend/src/pages/coach/CoachStudents.jsx` — the "authorized coach" Add Student section, scoped to the coach's assigned activities (1.7), with the same mandatory two-phone-number form.

## 1.11 Student & Batch Photos

- **Student photo**: reuses the pre-existing `UserDetails.profile_photo` column (already in the schema, previously unused by any endpoint). New endpoints `POST/GET /students/{id}/photo` (`backend/app/routers/students.py`) — upload authorized for admin or a coach whose activity the student is enrolled in; Pillow-compressed the same way selfies are (`services/storage.py`, generalized from a selfie-only helper into `save_selfie/save_student_photo/save_class_photo` + matching `read_*` variants, all still storing outside the webroot under `backend/uploads/`).
  - Frontend: `frontend/src/pages/coach/CoachStudents.jsx` — "Capture Photo" per roster student (reuses the existing camera-capture `SelfieCapture.jsx` component, now given a `title` prop so it isn't selfie-specific wording). Admin: `frontend/src/pages/Students.jsx` gained a "Photo" view action.
- **Batch/session photo**: new model `ClassPhoto` (`backend/app/models/compliance.py`, many photos per class). New endpoints `POST /compliance/class/{class_id}/photo` (coach — the assigned coach *or* an approved covering coach via swap, reusing `attendance.py`'s `_resolve_marking_coach`) and `GET /compliance/class/{class_id}/photos` + `GET /compliance/class-photo/{photo_id}`.
  - Frontend: `frontend/src/pages/coach/CoachClasses.jsx` — "Batch Photo" button on an ended class. Admin: `frontend/src/pages/Compliance.jsx`'s per-row "Photos" button (fetches each photo as an authenticated blob and shows a small gallery — a plain `<img src=".../class-photo/{id}">` would 401 since these endpoints require a Bearer token, which a plain `<img>` tag can't send).
- **"Coach can take a class in case of original coach's absence"**: this was **already implemented** before this work (the approved-swap covering-coach path in `_resolve_marking_coach`, `attendance.py`) — nothing new was needed here beyond making sure the new photo-capture endpoint honors the same covering-coach rule.

---

## Files touched (backend)

New: `models/batch.py`, `models/coach_activity.py`, `models/fee_receipt.py`, `models/compliance.py`, `schemas/batch.py`, `schemas/coach_activity.py`, `schemas/fee_receipt.py`, `schemas/compliance.py`, `routers/batches.py`, `routers/receipts.py`, `routers/compliance.py`, `alembic/versions/0003_batches_and_coach_activities.py`, `0004_fee_receipts.py`, `0005_attendance_compliance.py`, `0006_student_contact_and_photos.py`.

Edited: `models/__init__.py`, `models/class_session.py`, `models/swap.py`, `models/user.py`, `schemas/swap.py`, `schemas/user.py`, `schemas/reports.py`, `schemas/attendance.py`, `schemas/salary.py`, `routers/salary.py`, `routers/swap.py`, `routers/students.py`, `routers/coaches.py`, `routers/reports.py`, `routers/attendance.py`, `services/storage.py`, `services/scheduler.py`, `config.py`, `main.py`.

## Files touched (frontend)

New: `pages/Salary.jsx`, `pages/Batches.jsx`, `pages/Compliance.jsx`, `pages/coach/CoachReceipts.jsx`, `pages/coach/CoachStudents.jsx`, `components/ActivityReportPanel.jsx`.

Edited: `App.jsx`, `api/endpoints.js`, `pages/Coaches.jsx`, `pages/Activities.jsx`, `pages/Reports.jsx`, `pages/Fees.jsx`, `pages/Attendance.jsx`, `pages/Students.jsx`, `pages/Login.jsx`, `pages/coach/CoachClasses.jsx`, `components/Layout.jsx`, `components/SelfieCapture.jsx`, `index.html`.

## Verification (not yet run in this environment — no Python/Node available here)

1. `cd backend && alembic upgrade head` — confirm all 4 new migrations apply cleanly against a real Postgres DB; `alembic downgrade -4` and back up to confirm the downgrade chain too.
2. `uvicorn app.main:app --reload` and exercise the new endpoints via `/docs`: create a batch → generate sessions → mark attendance late → submit/approve the late reason; create a fee receipt → approve → confirm the `StudentFee` flips to PAID; acknowledge a salary → confirm the admin-notify dry-run log line; mark a class not-conducted → confirm it shows in `/compliance/summary`.
3. `cd frontend && npm install && npm run dev` — click through the new admin pages (Salary, Batches, Compliance) and coach pages (Students, Receipts) end-to-end with a real admin and coach test account; confirm the overflow "More" nav sheet in `Layout.jsx` still works with the extra nav links.
4. Confirm nothing existing regressed: ordinary (non-late) attendance marking, the existing manual one-off class scheduling in Activities → Manage → Classes, the existing coach-initiated swap request/admin approve flow, and the existing admin mark-paid fee flow.

---

# Round 2 — 2026-09-06

A second batch of admin/coach requests, layered on top of everything above. Same conventions
(role-guarded routers, `log_action` audit entries, best-effort `notify()`). **Not run** in this
environment either (no Python/Node/Flutter here) — see the verification list at the bottom.

## 2.1 Salary Acknowledgement → Admin Notification

Already implemented in Round 1 (`acknowledge_salary` in `routers/salary.py` notifies every
active admin) — verified unchanged, no new work needed.

## 2.2 Per-Activity Student/Revenue/Attendance Detail

Already implemented in Round 1 (`GET /reports/activity/{id}` returns `student_count`,
`revenue_collected`, `total_present`, `total_absent`, `attendance_pct`, a per-coach
breakdown) — verified unchanged, matches the ask precisely.

## 2.3 App Icon (Academy Logo)

`mobile/pubspec.yaml`'s `flutter_launcher_icons` config (pointing at `logo.jpeg`) was already
correct from Round 1. **Still blocked**: this environment has no Flutter SDK, and the native
`android/`/`ios/` projects aren't generated yet, so `dart run flutter_launcher_icons` has never
been run. Until someone with Flutter runs `flutter create .` then that command, the app uses
Flutter's default icon. Fixed an inaccurate `pubspec.yaml` description ("Coach & Student
mobile app" → "Coach mobile app") and the root `README.md`, which still described the mobile
app as React Native/Expo with a student-facing login — both now describe the real Flutter,
coach-only app.

## 2.4 Coach-Drafted Fee Reminder Content (Admin-Approved, Copy-to-WhatsApp)

- **Backend**: new model `FeeReminderDraft` (`models/fee_reminder_draft.py`, status
  PENDING/APPROVED/REJECTED). New router `routers/fee_reminders.py` (`/fee-reminders`):
  `POST ""` (coach — if `message` is omitted, one is generated from the student's fee record
  for that period via the new shared `fee_reminder_message()` helper), `GET /my`, `GET /pending`
  + `GET ""` (admin), `PUT /{id}/approve` (sends the message via `notify()` to the student and
  notifies the coach it was sent), `PUT /{id}/reject` (notifies the coach with the reason).
  Migration `alembic/versions/0008_fee_reminder_drafts.py`. Reused (rather than duplicated) the
  existing "coach may bill this student" authorization check by extracting it out of
  `routers/receipts.py` into `services/authorization.py::coach_may_bill_student()`.
- **Standardized fee reminder wording** to the requested template ("Dear {name}, this is a
  reminder of your pending fee balance for the month of {month} of Rs {amount}. Kindly pay
  before end of {dd/mm/yyyy}. Ignore if paid.") in `services/notifications.py::fee_reminder_message()`,
  now used by the scheduled monthly job, the manual admin "Remind" button, and reminder drafts —
  one wording, three call sites, instead of three slightly different messages.
- Also added a plain payment-confirmation `notify()` on the existing direct admin
  `POST /fees/mark-paid` (previously silent; the coach-receipt path already notified the student).
- **Frontend (coach)**: new page `pages/coach/CoachFeeReminders.jsx` (`/coach/fee-reminders`) —
  draft a reminder (optional custom message), see status, and a "Copy" button once approved
  (`navigator.clipboard`) to paste into WhatsApp manually alongside the automatic send.
- **Frontend (admin)**: `pages/Fees.jsx` gained a "Pending Fee Reminder Drafts" section
  (approve & send / reject / copy), mirroring the existing fee-receipts section.
- **API**: `FeeRemindersAPI` (new) in `api/endpoints.js`.

## 2.5 Batch Coverage — "Which Slots Aren't Taken, Who Runs What"

- **Backend**: `GET /batches/coverage?check_date=` (admin) in `routers/batches.py` — returns
  active batches with no coach assigned, batches scheduled for that weekday with no
  `ClassSession` generated yet, and a per-activity map of which coach(es) run it (with batch
  counts). No new table — computed from existing `Batch`/`ClassSession` data.
- **Frontend (admin)**: `pages/Batches.jsx` gained a "Coverage" section (date picker + the
  three lists above) above the existing batch table.
- **API**: `BatchesAPI.coverage()`.

## 2.6 Proactive Admin Coach Reassignment (full field set)

The Round 1 "Reassign" action only worked reactively, from an already-missing class on the
Attendance page (needs an existing `class_id`). The new ask wants admin to pick Original Coach
→ Substitute Coach → Activity → Batch → Date → Session & Time Slot → Reason up front, even for
a date whose `ClassSession` hasn't been generated yet.

- **Backend**: `POST /swap/admin-assign` (`routers/swap.py`) now accepts `batch_id` + `date` as
  an alternative to `class_id` — if no matching `ClassSession` exists yet for that batch/date,
  one is created on the fly (activity/time copied from the batch), mirroring
  `POST /batches/{id}/generate-sessions` for a single date. `schemas/swap.py::AdminAssignSwap`
  updated accordingly (`class_id` now optional, `batch_id` added).
- **Frontend (admin)**: `pages/Batches.jsx` gained a "Reassign Coach" button/modal — pick the
  original coach, then one of their batches (activity/session/time shown as read-only context),
  a date, a substitute coach, and a reason. The old reactive "Reassign" button on the Attendance
  page is unchanged and still works for already-missing classes.

## 2.7 Students: Email/Password Now Truly Optional

The spec places "Email" under *optional* student columns (students never log in — the backend
already rejects Student-role logins), but `StudentCreate` required both `email` and `password`,
so every student record carried a real login credential nobody could use. Now:

- **Backend**: `schemas/user.py::StudentCreate.email`/`.password` are optional. `routers/students.py`
  auto-generates a non-guessable, never-logged-in placeholder (`student.<uuid>@no-login.internal`
  email, random password) when omitted, so the shared `users` table's NOT NULL columns are still
  satisfied without implying a real account. Name + both phone numbers remain mandatory, matching
  the ask exactly.
- **Frontend**: `pages/Students.jsx` (admin) and `pages/coach/CoachStudents.jsx` (coach) — Email
  and Password fields are no longer `required`, relabeled "(optional — students don't log in)",
  and blank values are omitted from the request rather than sent as empty strings (which would
  fail validation). Placeholder emails display as "-" in both student tables instead of the raw
  `@no-login.internal` address.

## 2.8 About Section (Academy Details)

- **Backend**: new singleton model `AcademySettings` (`models/academy.py`, always `id=1`). New
  router `routers/academy.py` (`/academy`): `GET` (any authenticated user), `PUT` (admin only,
  get-or-creates the row). Migration `alembic/versions/0007_academy_settings.py` (creates the
  table and seeds the default row).
- **Frontend (admin)**: new page `pages/About.jsx` (`/about`) — name, address, phone, email,
  description, editable by admin.
- **API**: `AcademyAPI` (new).

## 2.9 Before/After-Class Coach Reminders & Facility Entry/Exit Compliance

- **Before class**: new scheduler job `job_coach_before_class_reminder` (`services/scheduler.py`,
  every minute) — reminds the assigned coach 10 minutes before their class starts. (The "after
  class" reminder from the original spec — 15 min after class end — already existed as
  `job_coach_attendance_reminders`; left unchanged rather than retimed, since other logic assumes
  that 15-minute window.)
- **Facility entry/exit compliance**: two new jobs, `job_coach_entry_missing_alert` (10 min after
  a coach's *first* class of the day starts, alerts admins if no `CoachAttendance.entry_time` is
  recorded for that coach today) and `job_coach_exit_missing_alert` (15 min after a coach's *last*
  class of the day ends, alerts admins if no `exit_time` is recorded) — both skip coaches on
  approved leave for that date, same pattern as the existing end-of-day report. This directly
  answers "if before and after batch attendance (i.e., facility entry/exit) is not
  seen/submitted, admin should be notified" — distinct from the existing student-attendance
  late-marking alert (`job_missed_attendance_admin_alert`), which this doesn't change.
- All three jobs registered in `start_scheduler()`.

## Everything else on the new request list

Verified already implemented and unchanged by this round: reason-for-not-taking-a-class
(`ClassSkipReason` / Compliance page), batches by location/activity/session/time-slot (`Batch`
model/page — matches the ask's exact shape), student fee acknowledgement requiring admin
approval before the student is notified (`FeeReceipt` approve flow), student/batch photo
capture (`ClassPhoto` / student `profile_photo`), adding students, attendance-delay admin
approval (`AttendanceSubmission` late-marking flow), mandatory name + two phone numbers /
optional email + profile + additional details, and "coach can cover another coach's class"
(the approved-swap covering-coach path). One request — "individual mail id and password based
on their activity for coaches" — was resolved with the user as: keep the existing one-login-
per-coach design (already linked to one or more activities via `CoachActivity`); no separate
per-activity logins were built, by explicit choice.

## Files touched (backend) — Round 2

New: `models/academy.py`, `models/fee_reminder_draft.py`, `schemas/academy.py`,
`schemas/fee_reminder_draft.py`, `routers/academy.py`, `routers/fee_reminders.py`,
`services/authorization.py`, `alembic/versions/0007_academy_settings.py`,
`0008_fee_reminder_drafts.py`.

Edited: `models/__init__.py`, `schemas/user.py`, `schemas/swap.py`, `routers/receipts.py`,
`routers/students.py`, `routers/fees.py`, `routers/swap.py`, `routers/batches.py`, `main.py`,
`services/notifications.py`, `services/scheduler.py`.

## Files touched (frontend) — Round 2

New: `pages/About.jsx`, `pages/coach/CoachFeeReminders.jsx`.

Edited: `App.jsx`, `api/endpoints.js`, `components/icons.jsx`, `pages/Fees.jsx`,
`pages/Batches.jsx`, `pages/Students.jsx`, `pages/coach/CoachStudents.jsx`.

## Other

`mobile/pubspec.yaml` (description fix), root `README.md` (corrected the mobile-stack
description and the "what's been verified" claims to reflect that this environment has no
Python/Node/Flutter available).

## Verification (not yet run in this environment — no Python/Node/Flutter here)

1. `alembic upgrade head` — confirm migrations `0007`/`0008` apply cleanly (and downgrade
   cleanly) against a real Postgres DB, on top of `0001`-`0006`.
2. Backend: create a fee reminder draft as a coach with no `message` → confirm it's populated
   from the matching `StudentFee`; approve it as admin → confirm the student is notified
   (dry-run log line) and the coach is told it was sent. Create one with an activity the coach
   isn't linked to → confirm 403. Hit `GET /batches/coverage` → confirm unassigned/not-generated
   batches show correctly for a batch with no coach and a batch whose session wasn't generated
   for that date. Call `POST /swap/admin-assign` with `batch_id`+`date` only (no `class_id`) for
   a date with no existing `ClassSession` → confirm one is created and the swap records it.
   Create a student with no `email`/`password` → confirm it succeeds and the generated account
   still can't log in (`POST /auth/login` with any guessed password should fail — there's no way
   to know the random one). `GET /academy` before any `PUT` → confirm it lazily creates and
   returns the default row.
3. Frontend: `npm run dev` and click through the new "About" (admin) and "Fee Reminders" (coach)
   pages, the new "Coverage" and "Reassign Coach" sections on Batches, and the new "Pending Fee
   Reminder Drafts" section on Fees — with a real admin and coach test account.
4. Confirm nothing existing regressed: the Round 1 verification list above, plus ordinary
   (non-draft) fee reminders sent via the scheduled job and the manual "Remind" button now using
   the new wording, and the existing reactive "Reassign" button on the Attendance page.
