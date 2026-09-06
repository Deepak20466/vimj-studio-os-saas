import { useState } from "react";
import { NavLink, Outlet, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { useTheme } from "../context/ThemeContext";
import { ICONS_BY_KEY, IconMore, IconLogout, IconClose, IconSun, IconMoon } from "./icons";
import NotificationBell from "./NotificationBell";

const MAX_TABS = 4;

export default function Layout({ links }) {
  const { user, logout } = useAuth();
  const { theme, toggleTheme } = useTheme();
  const navigate = useNavigate();
  const [moreOpen, setMoreOpen] = useState(false);

  const overflow = links.length > MAX_TABS + 1;
  const tabs = overflow ? links.slice(0, MAX_TABS) : links;
  const rest = overflow ? links.slice(MAX_TABS) : [];

  const handleLogout = async () => {
    await logout();
    navigate("/login");
  };

  const initials = (user?.name || "?")
    .split(" ")
    .map((p) => p[0])
    .slice(0, 2)
    .join("")
    .toUpperCase();

  const renderIcon = (key, active) => {
    const Icon = ICONS_BY_KEY[key] || ICONS_BY_KEY.dashboard;
    return <Icon style={{ opacity: active ? 1 : 0.75 }} />;
  };

  return (
    <div className="app-shell">
      <header className="topbar">
        <div className="topbar-brand">
          <img
            src="/logo.jpeg"
            alt="VIMJ Studio"
            className="topbar-logo"
            onError={(e) => {
              e.currentTarget.style.display = "none";
            }}
          />
          <div className="topbar-titles">
            <span className="topbar-title">VIMJ Studio</span>
            <span className="topbar-subtitle">Attendance Management</span>
          </div>
        </div>
        <div className="topbar-user">
          <div className="user-chip">
            <span className="user-avatar">{initials}</span>
            <span className="user-meta">
              <span className="user-name">{user?.name}</span>
              <span className="user-role">{user?.role}</span>
            </span>
          </div>
          <NotificationBell />
          <button
            className="icon-btn"
            title={theme === "dark" ? "Switch to light mode" : "Switch to dark mode"}
            onClick={toggleTheme}
          >
            {theme === "dark" ? <IconSun /> : <IconMoon />}
          </button>
          <button className="icon-btn" title="Log out" onClick={handleLogout}>
            <IconLogout />
          </button>
        </div>
      </header>

      <main className="main-content">
        <Outlet />
      </main>

      <nav className="bottom-nav">
        {tabs.map((link) => (
          <NavLink
            key={link.to}
            to={link.to}
            end={link.end ?? link.to === "/"}
            className={({ isActive }) => "bottom-nav-item" + (isActive ? " active" : "")}
          >
            {({ isActive }) => (
              <>
                {renderIcon(link.icon, isActive)}
                <span>{link.label}</span>
              </>
            )}
          </NavLink>
        ))}
        {overflow && (
          <button
            className={"bottom-nav-item" + (moreOpen ? " active" : "")}
            onClick={() => setMoreOpen(true)}
          >
            <IconMore style={{ opacity: moreOpen ? 1 : 0.75 }} />
            <span>More</span>
          </button>
        )}
      </nav>

      {moreOpen && (
        <div className="more-sheet-backdrop" onClick={() => setMoreOpen(false)}>
          <div className="more-sheet" onClick={(e) => e.stopPropagation()}>
            <div className="more-sheet-handle" />
            <div className="more-sheet-header">
              <span>More</span>
              <button className="icon-btn" onClick={() => setMoreOpen(false)}>
                <IconClose />
              </button>
            </div>
            <div className="more-sheet-grid">
              {rest.map((link) => (
                <NavLink
                  key={link.to}
                  to={link.to}
                  className="more-sheet-item"
                  onClick={() => setMoreOpen(false)}
                >
                  {renderIcon(link.icon, false)}
                  <span>{link.label}</span>
                </NavLink>
              ))}
            </div>
            <button className="more-sheet-logout" onClick={handleLogout}>
              <IconLogout />
              <span>Log out</span>
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
