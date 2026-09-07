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

### 9. LIVE LOCATION VERIFICATION
- GPS geofencing (50m radius from facility)
- Selfie photo verification during check-in
- Prevent marking attendance outside location
- Store photo proof with record

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
- `POST /auth/refresh` - Refresh JWT token
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
- `POST /swap/request` - Request activity swap
- `PUT /swap/{id}/approve` - Approve swap (admin)

### Reports
- `GET /reports/student/{id}` - Detailed student report
- `GET /reports/coach/{id}` - Detailed coach report
- `GET /reports/monthly-analysis` - Business analytics (admin)
- `GET /reports/100-percent-coaches/{month}` - Coaches with 100% attendance
- `GET /reports/attendance-graph/{user_id}` - Graph data (line chart)
- `GET /reports/fee-status-graph` - Fee breakdown (pie chart)

### Features
- Geofencing: Haversine formula for 50m radius validation
- Auto-reminders: Scheduled tasks (end-of-month fees, 10th salary, 15min after class)
- Image upload: Store selfies in `/uploads/selfies/` with access control
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
- **Swaps:** View swap requests, accept/reject (ahead of web here — web has no coach-facing swap UI yet)
- **Chat:** Direct line to admin
- **Offline:** Queue marking offline, sync when online
- Biometric login (fingerprint)
- Dark/light theme
- Push notifications (with sms)

### Admin App
Same login screen, routed by role. Drawer-nav shell (`lib/features/admin/`),
full parity with all 14 web admin dashboard sections (as of 2026-09-08):
Dashboard (stats + fee pie chart + coaches missing attendance), Students
(CRUD, activate/deactivate, individual report + CSV/PDF export via the
share sheet), Coaches (CRUD, manage activities, activate/deactivate,
individual report + export), Activities (CRUD), Batches (recurring
schedule CRUD, generate-sessions, day/month pickers), Attendance (daily
missing + manual entry), Compliance (submitted/pending/delayed tracking,
late-attendance approval), Leave (approve/reject with note), Fees (unpaid
list, mark paid, remind, create), Salary (list, create, edit, delete),
Reports (business analytics), Chat (message any coach), Settings (own +
coach credentials), About (academy profile). CSV/PDF export opens the
native share sheet (`share_plus`) since there's no browser download folder
on mobile.

---

## SECURITY
- Passwords: bcrypt 12+ rounds
- Sensitive data: encrypted at rest (salary, fees)
- HTTPS only
- CORS: only frontend domain
- Coaches can't query other coaches' data (API layer validation)
- Selfies: stored outside webroot, user access control only
- Audit log: all attendance changes logged

---

## DEPLOYMENT (No Docker)
- Python venv: `python -m venv venv && pip install -r requirements.txt`
- Run backend: `gunicorn -w 4 -b 0.0.0.0:8000 main:app`
- Nginx: reverse proxy + static React files
- PostgreSQL: native installation with daily backups
- Selfies: `/uploads/selfies/` directory with compression (max 500KB)
- Systemd service file for auto-start

---

## SUCCESS CHECKLIST
✅ All 15 requirements implemented
✅ Coaches see only their own data (API enforced)
✅ Students see only own attendance/fees
✅ Geofencing prevents attendance outside 50m radius
✅ Selfie verification with timestamps
✅ All endpoints respond within 2 seconds
✅ Daily non-compliance reports generated
✅ Automated reminders (fees, salary, attendance)
✅ Monthly business analytics dashboard
✅ PDF/CSV export for all reports
✅ No Docker - direct server deployment
✅ Mobile offline support with sync
✅ Role-based access control enforced at API