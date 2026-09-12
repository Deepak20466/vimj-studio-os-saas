import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { LeaveAPI } from "../../api/endpoints";
import StatusBadge from "../../components/StatusBadge";

const emptyForm = { start_date: "", end_date: "", reason: "" };

export default function CoachLeave() {
  const [leaves, setLeaves] = useState([]);
  const [loading, setLoading] = useState(true);
  const [form, setForm] = useState(emptyForm);
  const [submitting, setSubmitting] = useState(false);
  const [busyId, setBusyId] = useState(null);

  const load = () => {
    setLoading(true);
    LeaveAPI.my()
      .then((r) => setLeaves(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load leave history"))
      .finally(() => setLoading(false));
  };

  useEffect(load, []);

  const submit = async (e) => {
    e.preventDefault();
    if (form.end_date < form.start_date) {
      toast.error("End date cannot be before start date");
      return;
    }
    setSubmitting(true);
    try {
      await LeaveAPI.request(form);
      toast.success("Leave request submitted — awaiting admin decision");
      setForm(emptyForm);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to submit request");
    } finally {
      setSubmitting(false);
    }
  };

  const cancelLeave = async (leave) => {
    if (!confirm("Cancel this leave request?")) return;
    setBusyId(leave.id);
    try {
      await LeaveAPI.cancel(leave.id);
      toast.success("Leave request cancelled");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Cancel failed");
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>Leave</h1>
      </div>

      <div className="card" style={{ maxWidth: 640 }}>
        <h3 style={{ marginTop: 0 }}>Request Leave</h3>
        <form onSubmit={submit}>
          <div style={{ display: "flex", gap: 12 }}>
            <div className="field" style={{ flex: 1 }}>
              <label>Start date</label>
              <input
                type="date"
                required
                value={form.start_date}
                onChange={(e) => setForm({ ...form, start_date: e.target.value })}
              />
            </div>
            <div className="field" style={{ flex: 1 }}>
              <label>End date</label>
              <input
                type="date"
                required
                value={form.end_date}
                onChange={(e) => setForm({ ...form, end_date: e.target.value })}
              />
            </div>
          </div>
          <div className="field">
            <label>Reason</label>
            <textarea
              rows={3}
              required
              minLength={3}
              placeholder="e.g. family function, medical appointment..."
              value={form.reason}
              onChange={(e) => setForm({ ...form, reason: e.target.value })}
            />
          </div>
          <button className="btn btn-primary" disabled={submitting}>
            {submitting ? "Submitting..." : "Submit Request"}
          </button>
        </form>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>My Leave History</h3>
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : leaves.length === 0 ? (
          <div className="empty-state">No leave requests yet.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Start</th>
                <th>End</th>
                <th>Reason</th>
                <th>Status</th>
                <th>Admin Note</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {leaves.map((l) => (
                <tr key={l.id}>
                  <td>{l.start_date}</td>
                  <td>{l.end_date}</td>
                  <td>{l.reason}</td>
                  <td>
                    <StatusBadge status={l.status} />
                  </td>
                  <td>{l.decision_note || "—"}</td>
                  <td>
                    {l.status === "PENDING" ? (
                      <button className="btn btn-danger btn-sm" disabled={busyId === l.id} onClick={() => cancelLeave(l)}>
                        Cancel
                      </button>
                    ) : (
                      "—"
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
