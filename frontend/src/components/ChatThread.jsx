import { useEffect, useRef, useState } from "react";
import toast from "react-hot-toast";
import { ChatAPI } from "../api/endpoints";
import { useAuth } from "../context/AuthContext";

const POLL_MS = 4000;

function timeLabel(iso) {
  const d = new Date(iso);
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

export default function ChatThread({ coachId, title }) {
  const { user } = useAuth();
  const [messages, setMessages] = useState([]);
  const [draft, setDraft] = useState("");
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const listRef = useRef(null);
  const lastIdRef = useRef(0);

  useEffect(() => {
    setMessages([]);
    lastIdRef.current = 0;
    setLoading(true);
    if (!coachId) return;

    let cancelled = false;

    const poll = async () => {
      try {
        const { data } = await ChatAPI.messages(coachId, lastIdRef.current || undefined);
        if (cancelled || data.length === 0) return;
        lastIdRef.current = data[data.length - 1].id;
        setMessages((prev) => [...prev, ...data]);
      } catch {
        // best-effort
      }
    };

    ChatAPI.messages(coachId)
      .then(({ data }) => {
        if (cancelled) return;
        setMessages(data);
        if (data.length) lastIdRef.current = data[data.length - 1].id;
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load chat"))
      .finally(() => !cancelled && setLoading(false));

    ChatAPI.markRead(coachId).catch(() => {});

    const interval = setInterval(poll, POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, [coachId]);

  useEffect(() => {
    if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight;
    if (messages.length) ChatAPI.markRead(coachId).catch(() => {});
  }, [messages, coachId]);

  const send = async (e) => {
    e.preventDefault();
    const text = draft.trim();
    if (!text) return;
    setSending(true);
    try {
      const { data } = await ChatAPI.send(text, coachId);
      setMessages((prev) => [...prev, data]);
      lastIdRef.current = data.id;
      setDraft("");
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to send message");
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="card chat-panel">
      <h3 style={{ marginTop: 0 }}>{title}</h3>

      <div className="chat-messages" ref={listRef}>
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : messages.length === 0 ? (
          <div className="empty-state">No messages yet. Say hello!</div>
        ) : (
          messages.map((m) => {
            const mine = m.sender_id === user.id;
            return (
              <div key={m.id} className={"chat-bubble-row" + (mine ? " mine" : "")}>
                <div className="chat-bubble">
                  {!mine && <div className="chat-bubble-sender">{m.sender_name}</div>}
                  <div>{m.message}</div>
                  <div className="chat-bubble-time">{timeLabel(m.created_at)}</div>
                </div>
              </div>
            );
          })
        )}
      </div>

      <form className="chat-composer" onSubmit={send}>
        <input
          type="text"
          placeholder="Type a message..."
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          disabled={!coachId || sending}
        />
        <button className="btn btn-primary" disabled={!coachId || sending || !draft.trim()}>
          Send
        </button>
      </form>
    </div>
  );
}
