import client from "./client";

export const AuthAPI = {
  login: (email, password) => client.post("/auth/login", { email, password }),
  logout: () => client.post("/auth/logout"),
  forgotPassword: (email) => client.post("/auth/forgot-password", { email }),
  resetPassword: (token, new_password) => client.post("/auth/reset-password", { token, new_password }),
};

export const StudentsAPI = {
  list: (search) => client.get("/students", { params: { search } }),
  create: (payload) => client.post("/students", payload),
  update: (id, payload) => client.put(`/students/${id}`, payload),
  remove: (id) => client.delete(`/students/${id}`),
  attendance: (id) => client.get(`/students/${id}/attendance`),
  fees: (id) => client.get(`/students/${id}/fees`),
};

export const CoachesAPI = {
  list: (search) => client.get("/coaches", { params: { search } }),
  create: (payload) => client.post("/coaches", payload),
  update: (id, payload) => client.put(`/coaches/${id}`, payload),
  remove: (id) => client.delete(`/coaches/${id}`),
  attendance: (id) => client.get(`/coaches/${id}/attendance`),
  salary: (id) => client.get(`/coaches/${id}/salary`),
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
};

export const SalaryAPI = {
  create: (payload) => client.post("/salary", payload),
  coachHistory: (coachId) => client.get(`/salary/coach/${coachId}`),
};

export const SwapAPI = {
  pending: () => client.get("/swap/pending"),
  approve: (id) => client.put(`/swap/${id}/approve`),
  reject: (id) => client.put(`/swap/${id}/reject`),
};

export const CoachSelfAPI = {
  myClasses: (classDate) => client.get("/activities/classes/my", { params: classDate ? { class_date: classDate } : {} }),
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
};
