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
  // A plain <img src> can't attach the Bearer token this API requires, so the
  // selfie has to be fetched as an authenticated blob (like StudentsAPI.photoBlob)
  // rather than linked to directly.
  selfieBlob: (id) => client.get(`/attendance/selfie/${id}`, { responseType: "blob" }),
  list: (params) => client.get("/attendance/students", { params }),
  update: (id, payload) => client.put(`/attendance/students/${id}`, payload),
  remove: (id) => client.delete(`/attendance/students/${id}`),
  // Admin review of a coach-marked record — once decided, the coach can no longer edit it.
  approve: (id, note) => client.put(`/attendance/students/${id}/approve`, { note }),
  reject: (id, note) => client.put(`/attendance/students/${id}/reject`, { note }),
  // Coach facility attendance — manual entry with full CRUD (separate from student attendance)
  coachList: (params) => client.get("/attendance/coaches", { params }),
  coachCreateManual: (payload) => client.post("/attendance/coaches/manual", payload),
  coachUpdate: (id, payload) => client.put(`/attendance/coaches/${id}`, payload),
  coachRemove: (id) => client.delete(`/attendance/coaches/${id}`),
};

export const LeaveAPI = {
  request: (payload) => client.post("/leave/request", payload),
  my: () => client.get("/leave/my"),
  cancel: (id) => client.delete(`/leave/${id}`),
  pending: () => client.get("/leave/pending"),
  list: (params) => client.get("/leave", { params }),
  approve: (id, note) => client.put(`/leave/${id}/approve`, { note }),
  reject: (id, note) => client.put(`/leave/${id}/reject`, { note }),
};

export const FeesAPI = {
  unpaid: () => client.get("/fees/unpaid"),
  list: (params) => client.get("/fees", { params }),
  create: (payload) => client.post("/fees", payload),
  update: (id, payload) => client.put(`/fees/${id}`, payload),
  remove: (id) => client.delete(`/fees/${id}`),
  markPaid: (fee_id) => client.post("/fees/mark-paid", { fee_id }),
  remind: (feeId) => client.post(`/fees/${feeId}/remind`),
  // fmt: "pdf" | "csv"; disposition: "attachment" (download) | "inline" (view)
  receipt: (feeId, fmt = "pdf", disposition = "attachment") =>
    client.get(`/fees/${feeId}/receipt`, { params: { fmt, disposition }, responseType: "blob" }),
  receiptPdf: (feeId) => client.get(`/fees/${feeId}/receipt`, { responseType: "blob" }),
};

export const NotificationsAPI = {
  list: () => client.get("/notifications"),
  markRead: (id) => client.put(`/notifications/${id}/read`),
  markAllRead: () => client.put("/notifications/read-all"),
  remove: (id) => client.delete(`/notifications/${id}`),
  removeAll: () => client.delete("/notifications"),
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
  // fmt: "pdf" | "csv"; disposition: "attachment" (download) | "inline" (view)
  pdf: (id, fmt = "pdf", disposition = "attachment") =>
    client.get(`/receipts/${id}/pdf`, { params: { fmt, disposition }, responseType: "blob" }),
};

export const CoachSelfAPI = {
  myClasses: (classDate) => client.get("/activities/classes/my", { params: classDate ? { class_date: classDate } : {} }),
  classSummary: (classId) => client.get(`/activities/classes/${classId}/summary`),
  roster: (activityId) => client.get(`/activities/${activityId}/roster`),
  markAttendance: (payload) => client.post("/attendance/mark-student", payload),
  coachMark: (payload) => client.post("/attendance/coach-mark", payload),
  myAttendance: (coachId) => client.get(`/coaches/${coachId}/attendance`),
  myStudentAttendance: (params) => client.get("/attendance/students", { params }),
  myActivities: (coachId) => client.get(`/coaches/${coachId}/activities`),
  directory: () => client.get("/coaches/directory"),
};

export const DashboardAPI = {
  summary: () => client.get("/dashboard/summary"),
  feeStatus: () => client.get("/dashboard/fee-status"),
  activityAttendance: () => client.get("/dashboard/activity-attendance"),
};

export const ResetAPI = {
  // Admin-only: wipes attendance/fee/notification history system-wide.
  // Keeps Users, Activities, and Batches intact.
  all: () => client.post("/reset/all"),
  // Coach-only: wipes only the caller's own attendance history.
  mine: () => client.post("/reset/mine"),
};
