import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { ChatAPI } from "../api/endpoints";
import ChatThread from "../components/ChatThread";

const POLL_MS = 8000;

function timeAgo(iso) {
  if (!iso) return "";
  const seconds = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (seconds < 60) return "just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

export default function Chat() {
  const [threads, setThreads] = useState([]);
  const [loading, setLoading] = useState(true);
  const [activeCoachId, setActiveCoachId] = useState(null);

  const load = () => {
    ChatAPI.threads()
      .then((r) => {
        setThreads(r.data);
        setActiveCoachId((current) => current ?? r.data[0]?.coach_id ?? null);
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load chats"))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
    const interval = setInterval(load, POLL_MS);
    return () => clearInterval(interval);
  }, []);

  const active = threads.find((t) => t.coach_id === activeCoachId);

  return (
    <div>
      <div className="page-header">
        <h1>Chat</h1>
      </div>

      <div className="chat-layout">
        <div className="card chat-thread-list">
          <h3 style={{ marginTop: 0 }}>Coaches</h3>
          {loading ? (
            <div className="empty-state">Loading...</div>
          ) : threads.length === 0 ? (
            <div className="empty-state">No conversations yet.</div>
          ) : (
            threads.map((t) => (
              <button
                key={t.coach_id}
                className={"chat-thread-item" + (t.coach_id === activeCoachId ? " active" : "")}
                onClick={() => setActiveCoachId(t.coach_id)}
              >
                <div className="chat-thread-item-top">
                  <span className="chat-thread-name">{t.coach_name}</span>
                  {t.unread_count > 0 && <span className="badge badge-pending">{t.unread_count}</span>}
                </div>
                <div className="chat-thread-preview">{t.last_message || "No messages yet"}</div>
                <div className="chat-thread-time">{timeAgo(t.last_message_at)}</div>
              </button>
            ))
          )}
        </div>

        {active ? (
          <ChatThread coachId={active.coach_id} title={`Chat with ${active.coach_name}`} />
        ) : (
          <div className="card chat-panel">
            <div className="empty-state">Select a coach to start chatting.</div>
          </div>
        )}
      </div>
    </div>
  );
}
