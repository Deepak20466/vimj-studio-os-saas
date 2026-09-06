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
import Leave from "./pages/Leave";
import Fees from "./pages/Fees";
import Reports from "./pages/Reports";
import Salary from "./pages/Salary";
import Batches from "./pages/Batches";
import Compliance from "./pages/Compliance";
import Chat from "./pages/Chat";
import About from "./pages/About";
import Settings from "./pages/Settings";
import CoachDashboard from "./pages/coach/CoachDashboard";
import CoachClasses from "./pages/coach/CoachClasses";
import CoachAttendance from "./pages/coach/CoachAttendance";
import CoachLeave from "./pages/coach/CoachLeave";
import CoachSalary from "./pages/coach/CoachSalary";
import CoachReceipts from "./pages/coach/CoachReceipts";
import CoachFeeReminders from "./pages/coach/CoachFeeReminders";
import CoachStudents from "./pages/coach/CoachStudents";
import CoachChat from "./pages/coach/CoachChat";

const ADMIN_LINKS = [
  { to: "/", label: "Dashboard", icon: "dashboard" },
  { to: "/students", label: "Students", icon: "students" },
  { to: "/coaches", label: "Coaches", icon: "coaches" },
  { to: "/attendance", label: "Attendance", icon: "attendance" },
  { to: "/compliance", label: "Compliance", icon: "attendance" },
  { to: "/activities", label: "Activities", icon: "activities" },
  { to: "/batches", label: "Batches", icon: "classes" },
  { to: "/leave", label: "Leave", icon: "leave" },
  { to: "/fees", label: "Fees", icon: "fees" },
  { to: "/salary", label: "Salary", icon: "salary" },
  { to: "/reports", label: "Reports", icon: "reports" },
  { to: "/chat", label: "Chat", icon: "chat" },
  { to: "/settings", label: "Settings", icon: "settings" },
  { to: "/about", label: "About", icon: "about" },
];

const COACH_LINKS = [
  { to: "/coach", label: "Dashboard", end: true, icon: "dashboard" },
  { to: "/coach/classes", label: "Classes", icon: "classes" },
  { to: "/coach/students", label: "Students", icon: "students" },
  { to: "/coach/attendance", label: "Attendance", icon: "attendance" },
  { to: "/coach/leave", label: "Leave", icon: "leave" },
  { to: "/coach/salary", label: "Salary", icon: "salary" },
  { to: "/coach/receipts", label: "Receipts", icon: "fees" },
  { to: "/coach/fee-reminders", label: "Fee Reminders", icon: "fees" },
  { to: "/coach/chat", label: "Chat", icon: "chat" },
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
            <Route path="batches" element={<Batches />} />
            <Route path="attendance" element={<Attendance />} />
            <Route path="compliance" element={<Compliance />} />
            <Route path="leave" element={<Leave />} />
            <Route path="fees" element={<Fees />} />
            <Route path="salary" element={<Salary />} />
            <Route path="reports" element={<Reports />} />
            <Route path="chat" element={<Chat />} />
            <Route path="settings" element={<Settings />} />
            <Route path="about" element={<About />} />
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
            <Route path="salary" element={<CoachSalary />} />
            <Route path="receipts" element={<CoachReceipts />} />
            <Route path="fee-reminders" element={<CoachFeeReminders />} />
            <Route path="chat" element={<CoachChat />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </AuthProvider>
    </ThemeProvider>
  );
}
