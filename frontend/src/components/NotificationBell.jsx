import { useEffect, useRef, useState } from "react";
import { NotificationsAPI } from "../api/endpoints";
import { IconBell } from "./icons";

const POLL_MS = 20000;

function timeAgo(iso) {
  const seconds = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

export default function NotificationBell() {
  const [open, setOpen] = useState(false);
  const [items, setItems] = useState([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const boxRef = useRef(null);

  const load = () => {
    NotificationsAPI.list()
      .then((r) => {
        setItems(r.data.items);
        setUnreadCount(r.data.unread_count);
      })
      .catch(() => {});
  };

  useEffect(() => {
    load();
    const interval = setInterval(load, POLL_MS);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    if (!open) return;
    const onClickOutside = (e) => {
      if (boxRef.current && !boxRef.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener("mousedown", onClickOutside);
    return () => document.removeEventListener("mousedown", onClickOutside);
  }, [open]);

  const toggle = () => setOpen((o) => !o);

  const markRead = async (n) => {
    if (n.is_read) return;
    try {
      await NotificationsAPI.markRead(n.id);
      setItems((list) => list.map((i) => (i.id === n.id ? { ...i, is_read: true } : i)));
      setUnreadCount((c) => Math.max(0, c - 1));
    } catch {
      // best-effort
    }
  };

  const markAllRead = async () => {
    try {
      await NotificationsAPI.markAllRead();
      setItems((list) => list.map((i) => ({ ...i, is_read: true })));
      setUnreadCount(0);
    } catch {
      // best-effort
    }
  };

  const remove = async (n, e) => {
    e.stopPropagation();
    try {
      await NotificationsAPI.remove(n.id);
      setItems((list) => list.filter((i) => i.id !== n.id));
      if (!n.is_read) setUnreadCount((c) => Math.max(0, c - 1));
    } catch {
      // best-effort
    }
  };

  const removeAll = async () => {
    if (!confirm("Delete all notifications?")) return;
    try {
      await NotificationsAPI.removeAll();
      setItems([]);
      setUnreadCount(0);
    } catch {
      // best-effort
    }
  };

  return (
    <div style={{ position: "relative" }} ref={boxRef}>
      <button className="icon-btn" title="Notifications" onClick={toggle} style={{ position: "relative" }}>
        <IconBell />
        {unreadCount > 0 && (
          <span
            style={{
              position: "absolute",
              top: 2,
              right: 2,
              background: "var(--danger)",
              color: "white",
              borderRadius: 999,
              fontSize: "0.6rem",
              fontWeight: 700,
              minWidth: 16,
              height: 16,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              padding: "0 3px",
            }}
          >
            {unreadCount > 9 ? "9+" : unreadCount}
          </span>
        )}
      </button>

      {open && (
        <div
          className="card"
          style={{
            position: "absolute",
            right: 0,
            top: 46,
            width: 320,
            maxHeight: 420,
            overflowY: "auto",
            zIndex: 60,
            padding: 12,
          }}
        >
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
            <strong style={{ fontSize: "0.9rem" }}>Notifications</strong>
            <div style={{ display: "flex", gap: 10 }}>
              {unreadCount > 0 && (
                <button className="link-btn" onClick={markAllRead}>
                  Mark all read
                </button>
              )}
              {items.length > 0 && (
                <button className="link-btn" onClick={removeAll}>
                  Clear all
                </button>
              )}
            </div>
          </div>
          {items.length === 0 ? (
            <div className="empty-state" style={{ padding: "20px 8px" }}>
              No notifications yet.
            </div>
          ) : (
            items.map((n) => (
              <div
                key={n.id}
                onClick={() => markRead(n)}
                style={{
                  padding: "8px 6px",
                  borderBottom: "1px solid var(--border)",
                  cursor: n.is_read ? "default" : "pointer",
                  background: n.is_read ? "transparent" : "#fff3e6",
                  borderRadius: 8,
                }}
              >
                <div style={{ display: "flex", justifyContent: "space-between", gap: 8 }}>
                  <span style={{ fontWeight: 700, fontSize: "0.82rem" }}>{n.title}</span>
                  <span style={{ display: "flex", alignItems: "center", gap: 6, whiteSpace: "nowrap" }}>
                    <span style={{ fontSize: "0.68rem", color: "var(--text-muted)" }}>{timeAgo(n.created_at)}</span>
                    <button
                      className="icon-btn"
                      title="Delete notification"
                      onClick={(e) => remove(n, e)}
                      style={{ padding: "0 4px", fontSize: "0.85rem", lineHeight: 1, color: "var(--text-muted)" }}
                    >
                      ✕
                    </button>
                  </span>
                </div>
                <div style={{ fontSize: "0.8rem", color: "var(--text)", marginTop: 2 }}>{n.message}</div>
                {n.delay_minutes != null && (
                  <span className="badge badge-pending" style={{ marginTop: 4, display: "inline-block" }}>
                    {n.delay_minutes >= 0 ? `${n.delay_minutes} min after` : `${Math.abs(n.delay_minutes)} min before`}
                  </span>
                )}
              </div>
            ))
          )}
        </div>
      )}
    </div>
  );
}
