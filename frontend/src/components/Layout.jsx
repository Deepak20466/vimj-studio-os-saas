import { NavLink, Outlet, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";

const ADMIN_LINKS = [
  { to: "/", label: "Dashboard" },
  { to: "/students", label: "Students" },
  { to: "/coaches", label: "Coaches" },
  { to: "/activities", label: "Activities" },
  { to: "/attendance", label: "Attendance" },
  { to: "/leave", label: "Leave" },
  { to: "/fees", label: "Fees" },
  { to: "/reports", label: "Reports" },
];

export default function Layout() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  const links = ADMIN_LINKS;

  const handleLogout = async () => {
    await logout();
    navigate("/login");
  };

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="sidebar-logo">
          VIMJ Studio
          <span>Attendance Management</span>
        </div>
        <nav className="sidebar-nav">
          {links.map((link) => (
            <NavLink key={link.to} to={link.to} end={link.to === "/"} className={({ isActive }) => (isActive ? "active" : "")}>
              {link.label}
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-footer">
          <div style={{ fontSize: "0.8rem", opacity: 0.9, marginBottom: 8 }}>
            {user?.name} <br />
            <span style={{ opacity: 0.7 }}>{user?.role}</span>
          </div>
          <button onClick={handleLogout}>Log out</button>
        </div>
      </aside>
      <main className="main-content">
        <Outlet />
      </main>
    </div>
  );
}
