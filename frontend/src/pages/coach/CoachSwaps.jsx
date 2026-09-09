import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { useAuth } from "../../context/AuthContext";
import { CoachSelfAPI, SwapAPI } from "../../api/endpoints";
import StatusBadge from "../../components/StatusBadge";
import Modal from "../../components/Modal";

const todayStr = () => new Date().toISOString().slice(0, 10);

export default function CoachSwaps() {
  const { user } = useAuth();
  const [swaps, setSwaps] = useState([]);
  const [loading, setLoading] = useState(true);
  const [coaches, setCoaches] = useState([]);
  const [myClasses, setMyClasses] = useState([]);
  const [form, setForm] = useState({ class_id: "", covering_coach_id: "", date: todayStr(), reason: "" });
  const [submitting, setSubmitting] = useState(false);
  const [declining, setDeclining] = useState(null);
  const [declineReason, setDeclineReason] = useState("");
  const [busyId, setBusyId] = useState(null);

  const load = () => {
    setLoading(true);
    SwapAPI.my()
      .then((r) => setSwaps(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load swaps"))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
    CoachSelfAPI.directory().then((r) => setCoaches(r.data.filter((c) => c.id !== user.id)));
    CoachSelfAPI.myClasses(todayStr()).then((r) => setMyClasses(r.data));
  }, []);

  const submit = async (e) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      await SwapAPI.request({
        class_id: Number(form.class_id),
        covering_coach_id: Number(form.covering_coach_id),
        date: form.date,
        reason: form.reason,
      });
      toast.success("Swap request submitted — awaiting admin approval");
      setForm({ class_id: "", covering_coach_id: "", date: todayStr(), reason: "" });
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to submit request");
    } finally {
      setSubmitting(false);
    }
  };

  const accept = async (s) => {
    setBusyId(s.id);
    try {
      await SwapAPI.respond(s.id, true);
      toast.success("Swap accepted — you now cover this class");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to accept");
    } finally {
      setBusyId(null);
    }
  };

  const openDecline = (s) => {
    setDeclining(s);
    setDeclineReason("");
  };

  const submitDecline = async (e) => {
    e.preventDefault();
    setBusyId(declining.id);
    try {
      await SwapAPI.respond(declining.id, false, declineReason);
      toast.success("Swap declined");
      setDeclining(null);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to decline");
    } finally {
      setBusyId(null);
    }
  };

  const needsMyResponse = (s) => s.initiated_by === "ADMIN" && s.status === "PENDING" && s.covering_coach_id === user.id;

  return (
    <div>
      <div className="page-header">
        <h1>Swaps</h1>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Request a Swap</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -8 }}>
          Ask another coach to cover one of your classes. Needs admin approval before it takes effect.
        </p>
        <form onSubmit={submit}>
          <div className="field">
            <label>Your class</label>
            <select value={form.class_id} onChange={(e) => setForm({ ...form, class_id: e.target.value })} required>
              <option value="">Select class</option>
              {myClasses.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.start_time} - {c.end_time} (Activity #{c.activity_id})
                </option>
              ))}
            </select>
          </div>
          <div className="form-grid">
            <div>
              <label>Covering coach</label>
              <select value={form.covering_coach_id} onChange={(e) => setForm({ ...form, covering_coach_id: e.target.value })} required>
                <option value="">Select coach</option>
                {coaches.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label>Date</label>
              <input type="date" value={form.date} onChange={(e) => setForm({ ...form, date: e.target.value })} required />
            </div>
          </div>
          <div className="field">
            <label>Reason</label>
            <textarea rows={2} value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} />
          </div>
          <button className="btn btn-primary" disabled={submitting}>
            {submitting ? "Submitting..." : "Submit Request"}
          </button>
        </form>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>My Swaps</h3>
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : swaps.length === 0 ? (
          <div className="empty-state">No swaps yet.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Class</th>
                <th>Role</th>
                <th>Status</th>
                <th>Reason</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {swaps.map((s) => {
                const isCovering = s.covering_coach_id === user.id;
                return (
                  <tr key={s.id}>
                    <td>{s.date}</td>
                    <td>Class #{s.class_id}</td>
                    <td>{isCovering ? "Covering" : "Requested coverage"}</td>
                    <td>
                      <StatusBadge status={s.status} />
                    </td>
                    <td>{s.reason || "—"}</td>
                    <td>
                      {needsMyResponse(s) ? (
                        <div className="table-actions">
                          <button className="btn btn-primary btn-sm" disabled={busyId === s.id} onClick={() => accept(s)}>
                            Accept
                          </button>
                          <button className="btn btn-danger btn-sm" disabled={busyId === s.id} onClick={() => openDecline(s)}>
                            Decline
                          </button>
                        </div>
                      ) : (
                        "—"
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      {declining && (
        <Modal title={`Decline swap for ${declining.date}`} onClose={() => setDeclining(null)}>
          <form onSubmit={submitDecline}>
            <div className="field">
              <label>Reason (optional)</label>
              <textarea rows={3} value={declineReason} onChange={(e) => setDeclineReason(e.target.value)} />
            </div>
            <div className="modal-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setDeclining(null)}>
                Cancel
              </button>
              <button className="btn btn-danger">Decline</button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
