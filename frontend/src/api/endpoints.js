import client from "./client";

export const AuthAPI = {
  login: (email, password) => client.post("/auth/login", { email, password }),
  logout: () => client.post("/auth/logout"),
  forgotPassword: (email) => client.post("/auth/forgot-password", { email }),
  resetPassword: (token, new_password) => client.post("/auth/reset-password", { token, new_password }),
  me: () => client.get("/auth/me"),
  updateMe: (payload) => client.put("/auth/me", payload),
};

export const StudentsAPI = {
  list: (search) => client.get("/students", { params: { search } }),
  create: (payload) => client.post("/students", payload),
  update: (id, payload) => client.put(`/students/${id}`, payload),
  remove: (id) => client.delete(`/students/${id}`),
  attendance: (id) => client.get(`/students/${id}/attendance`),
  fees: (id) => client.get(`/students/${id}/fees`),
  uploadPhoto: (id, photoBase64) => client.post(`/students/${id}/photo`, { photo_base64: photoBase64 }),
  photoBlob: (id) => client.get(`/students/${id}/photo`, { responseType: "blob" }),
};

export const CoachesAPI = {
  list: (search) => client.get("/coaches", { params: { search } }),
  create: (payload) => client.post("/coaches", payload),
  update: (id, payload) => client.put(`/coaches/${id}`, payload),
  remove: (id) => client.delete(`/coaches/${id}`),
  attendance: (id) => client.get(`/coaches/${id}/attendance`),
  salary: (id) => client.get(`/coaches/${id}/salary`),
  getActivities: (id) => client.get(`/coaches/${id}/activities`),
  setActivities: (id, activityIds) => client.put(`/coaches/${id}/activities`, { activity_ids: activityIds }),
};

export const ActivitiesAPI = {
  list: () => client.get("/activities"),
  create: (payload) => client.post("/activities", payload),
  update: (id, payload) => client.put(`/activities/${id}`, payload),
  remove: (id) => client.delete(`/activities/${id}`),
  classes: (activityId) => client.get(`/activities/${activityId}/classes`),
  createClass: (payload) => client.post("/activities/classes", payload),
  updateClass: (classId, payload) => client.put(`/activities/classes/${classId}`, payload),
  removeClass: (classId) => client.delete(`/activities/classes/${classId}`),
  enroll: (payload) => client.post("/activities/enroll", payload),
  unenroll: (enrollmentId) => client.delete(`/activities/enroll/${enrollmentId}`),
  roster: (activityId) => client.get(`/activities/${activityId}/roster`),
};

export const AttendanceAPI = {
  markManual: (payload) => client.post("/attendance/mark-student/manual", payload),
  dailyMissing: () => client.get("/attendance/daily-missing"),
  selfieUrl: (id) => `/api/attendance/selfie/${id}`,
  list: (params) => client.get("/attendance/students", { params }),
  update: (id, payload) => client.put(`/attendance/students/${id}`, payload),
  remove: (id) => client.delete(`/attendance/students/${id}`),
};

export const LeaveAPI = {
  pending: () => client.get("/leave/pending"),
  list: (params) => client.get("/leave", { params }),
  approve: (id, note) => client.put(`/leave/${id}/approve`, { note }),
  reject: (id, note) => client.put(`/leave/${id}/reject`, { note }),
  update: (id, payload) => client.put(`/leave/${id}`, payload),
  remove: (id) => client.delete(`/leave/${id}`),
};

export const FeesAPI = {
  unpaid: () => client.get("/fees/unpaid"),
  list: (params) => client.get("/fees", { params }),
  create: (payload) => client.post("/fees", payload),
  update: (id, payload) => client.put(`/fees/${id}`, payload),
  remove: (id) => client.delete(`/fees/${id}`),
  markPaid: (fee_id) => client.post("/fees/mark-paid", { fee_id }),
  remind: (feeId) => client.post(`/fees/${feeId}/remind`),
  receiptPdf: (feeId) => client.get(`/fees/${feeId}/receipt`, { responseType: "blob" }),
};

export const SalaryAPI = {
  create: (payload) => client.post("/salary", payload),
  coachHistory: (coachId) => client.get(`/salary/coach/${coachId}`),
  list: (params) => client.get("/salary", { params }),
};

export const SwapAPI = {
  pending: () => client.get("/swap/pending"),
  recent: () => client.get("/swap/recent"),
  approve: (id) => client.put(`/swap/${id}/approve`),
  reject: (id) => client.put(`/swap/${id}/reject`),
  adminAssign: (payload) => client.post("/swap/admin-assign", payload),
};

export const NotificationsAPI = {
  list: () => client.get("/notifications"),
  markRead: (id) => client.put(`/notifications/${id}/read`),
  markAllRead: () => client.put("/notifications/read-all"),
};

export const ChatAPI = {
  threads: () => client.get("/chat/threads"),
  messages: (coachId, sinceId) =>
    client.get("/chat/messages", { params: { coach_id: coachId, since_id: sinceId } }),
  send: (message, coachId) => client.post("/chat/messages", { message, coach_id: coachId }),
  markRead: (coachId) => client.put("/chat/read", null, { params: { coach_id: coachId } }),
  unreadCount: () => client.get("/chat/unread-count"),
};

export const BatchesAPI = {
  list: (activityId) => client.get("/batches", { params: activityId ? { activity_id: activityId } : {} }),
  create: (payload) => client.post("/batches", payload),
  update: (id, payload) => client.put(`/batches/${id}`, payload),
  remove: (id) => client.delete(`/batches/${id}`),
  generateSessions: (id, payload) => client.post(`/batches/${id}/generate-sessions`, payload),
  my: () => client.get("/batches/my"),
  coverage: (checkDate) => client.get("/batches/coverage", { params: checkDate ? { check_date: checkDate } : {} }),
  roster: (batchId, classDate) => client.get(`/batches/${batchId}/roster`, { params: classDate ? { class_date: classDate } : {} }),
};

export const AcademyAPI = {
  get: () => client.get("/academy"),
  update: (payload) => client.put("/academy", payload),
};

export const FeeRemindersAPI = {
  create: (payload) => client.post("/fee-reminders", payload),
  my: () => client.get("/fee-reminders/my"),
  pending: () => client.get("/fee-reminders/pending"),
  list: () => client.get("/fee-reminders"),
  approve: (id, decision_note) => client.put(`/fee-reminders/${id}/approve`, { decision_note }),
  reject: (id, decision_note) => client.put(`/fee-reminders/${id}/reject`, { decision_note }),
};

export const ReceiptsAPI = {
  create: (payload) => client.post("/receipts", payload),
  my: () => client.get("/receipts/my"),
  pending: () => client.get("/receipts/pending"),
  list: () => client.get("/receipts"),
  approve: (id, decision_note) => client.put(`/receipts/${id}/approve`, { decision_note }),
  reject: (id, decision_note) => client.put(`/receipts/${id}/reject`, { decision_note }),
  pdf: (id) => client.get(`/receipts/${id}/pdf`, { responseType: "blob" }),
};

export const ComplianceAPI = {
  classNotConducted: (classId, reason) => client.post("/compliance/class-not-conducted", { class_id: classId, reason }),
  lateReason: (classId, reason) => client.post("/compliance/late-reason", { class_id: classId, reason }),
  pendingLate: () => client.get("/compliance/pending"),
  approveLate: (id, decision_note) => client.put(`/compliance/late/${id}/approve`, { decision_note }),
  rejectLate: (id, decision_note) => client.put(`/compliance/late/${id}/reject`, { decision_note }),
  summary: (params) => client.get("/compliance/summary", { params }),
  uploadClassPhoto: (classId, photoBase64) => client.post(`/compliance/class/${classId}/photo`, { class_id: classId, photo_base64: photoBase64 }),
  classPhotos: (classId) => client.get(`/compliance/class/${classId}/photos`),
  classPhotoBlob: (photoId) => client.get(`/compliance/class-photo/${photoId}`, { responseType: "blob" }),
};

export const CoachSelfAPI = {
  myClasses: (classDate) => client.get("/activities/classes/my", { params: classDate ? { class_date: classDate } : {} }),
  classSummary: (classId) => client.get(`/activities/classes/${classId}/summary`),
  roster: (activityId) => client.get(`/activities/${activityId}/roster`),
  markAttendance: (payload) => client.post("/attendance/mark-student", payload),
  coachEntry: (payload) => client.post("/attendance/coach-entry", payload),
  coachExit: (payload) => client.post("/attendance/coach-exit", payload),
  myAttendance: (coachId) => client.get(`/coaches/${coachId}/attendance`),
  requestLeave: (payload) => client.post("/leave/request", payload),
  myLeaves: () => client.get("/leave/my"),
  updateLeave: (id, payload) => client.put(`/leave/${id}`, payload),
  cancelLeave: (id) => client.delete(`/leave/${id}`),
  leaveBalance: (coachId, year) => client.get(`/leave/balance/${coachId}`, { params: { year } }),
  salaryHistory: (coachId) => client.get(`/coaches/${coachId}/salary`),
  acknowledgeSalary: (salaryId) => client.post("/salary/acknowledge", { salary_id: salaryId }),
  myStudentAttendance: (params) => client.get("/attendance/students", { params }),
  updateStudentAttendance: (id, payload) => client.put(`/attendance/students/${id}`, payload),
  deleteStudentAttendance: (id) => client.delete(`/attendance/students/${id}`),
  myActivities: (coachId) => client.get(`/coaches/${coachId}/activities`),
  monthlyReport: (month, year, fmt) =>
    client.get("/reports/export/coach-monthly", { params: { month, year, fmt }, responseType: "blob" }),
};

export const ReportsAPI = {
  dashboardSummary: () => client.get("/reports/dashboard-summary"),
  studentReport: (id) => client.get(`/reports/student/${id}`),
  coachReport: (id) => client.get(`/reports/coach/${id}`),
  attendanceGraph: (userId) => client.get(`/reports/attendance-graph/${userId}`),
  feeStatusGraph: () => client.get("/reports/fee-status-graph"),
  monthlyAnalysis: (month, year) => client.get("/reports/monthly-analysis", { params: { month, year } }),
  hundredPercentCoaches: (month, year) => client.get(`/reports/100-percent-coaches/${month}`, { params: { year } }),
  exportStudent: (id, fmt) => client.get(`/reports/export/student/${id}`, { params: { fmt }, responseType: "blob" }),
  exportCoach: (id, fmt) => client.get(`/reports/export/coach/${id}`, { params: { fmt }, responseType: "blob" }),
  activityDetail: (id) => client.get(`/reports/activity/${id}`),
};
