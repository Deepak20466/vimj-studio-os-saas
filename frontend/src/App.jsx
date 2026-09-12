import { BrowserRouter, Routes, Route } from "react-router-dom";
import { Toaster } from "react-hot-toast";
import { AuthProvider } from "./context/AuthContext";
import { ThemeProvider } from "./context/ThemeContext";
import ProtectedRoute from "./components/ProtectedRoute";
import Layout from "./components/Layout";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import Students from "./pages/Students";
import Coaches from "./pages/Coaches";
import Activities from "./pages/Activities";
import Attendance from "./pages/Attendance";
import Fees from "./pages/Fees";
import Leave from "./pages/Leave";
import Settings from "./pages/Settings";
import CoachDashboard from "./pages/coach/CoachDashboard";
import CoachClasses from "./pages/coach/CoachClasses";
import CoachAttendance from "./pages/coach/CoachAttendance";
import CoachLeave from "./pages/coach/CoachLeave";
import CoachReceipts from "./pages/coach/CoachReceipts";
import CoachFeeReminders from "./pages/coach/CoachFeeReminders";
import CoachStudents from "./pages/coach/CoachStudents";
import CoachSettings from "./pages/coach/CoachSettings";

const ADMIN_LINKS = [
  { to: "/", label: "Dashboard", icon: "dashboard" },
  { to: "/students", label: "Students", icon: "students" },
  { to: "/coaches", label: "Coaches", icon: "coaches" },
  { to: "/attendance", label: "Attendance", icon: "attendance" },
  { to: "/activities", label: "Activities", icon: "activities" },
  { to: "/fees", label: "Fees", icon: "fees" },
  { to: "/leave", label: "Leave", icon: "leave" },
  { to: "/settings", label: "Settings", icon: "settings" },
];

const COACH_LINKS = [
  { to: "/coach", label: "Dashboard", end: true, icon: "dashboard" },
  { to: "/coach/classes", label: "Classes", icon: "classes" },
  { to: "/coach/students", label: "Students", icon: "students" },
  { to: "/coach/attendance", label: "Attendance", icon: "attendance" },
  { to: "/coach/leave", label: "Leave", icon: "leave" },
  { to: "/coach/receipts", label: "Receipts", icon: "fees" },
  { to: "/coach/fee-reminders", label: "Fee Reminders", icon: "fees" },
  { to: "/coach/settings", label: "Settings", icon: "settings" },
];

export default function App() {
  return (
    <ThemeProvider>
    <AuthProvider>
      <Toaster position="top-right" toastOptions={{ style: { fontSize: "0.85rem" } }} />
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Login />} />

          <Route
            path="/"
            element={
              <ProtectedRoute allow={["ADMIN"]}>
                <Layout links={ADMIN_LINKS} />
              </ProtectedRoute>
            }
          >
            <Route index element={<Dashboard />} />
            <Route path="students" element={<Students />} />
            <Route path="coaches" element={<Coaches />} />
            <Route path="activities" element={<Activities />} />
            <Route path="attendance" element={<Attendance />} />
            <Route path="fees" element={<Fees />} />
            <Route path="leave" element={<Leave />} />
            <Route path="settings" element={<Settings />} />
          </Route>

          <Route
            path="/coach"
            element={
              <ProtectedRoute allow={["COACH"]}>
                <Layout links={COACH_LINKS} />
              </ProtectedRoute>
            }
          >
            <Route index element={<CoachDashboard />} />
            <Route path="classes" element={<CoachClasses />} />
            <Route path="students" element={<CoachStudents />} />
            <Route path="attendance" element={<CoachAttendance />} />
            <Route path="leave" element={<CoachLeave />} />
            <Route path="receipts" element={<CoachReceipts />} />
            <Route path="fee-reminders" element={<CoachFeeReminders />} />
            <Route path="settings" element={<CoachSettings />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </AuthProvider>
    </ThemeProvider>
  );
}
