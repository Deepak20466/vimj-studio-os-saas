import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { useAuth } from "../../context/AuthContext";
import { CoachSelfAPI } from "../../api/endpoints";
import StatusBadge from "../../components/StatusBadge";
import Modal from "../../components/Modal";

export default function CoachLeave() {
  const { user } = useAuth();
  const [leaves, setLeaves] = useState([]);
  const [balance, setBalance] = useState(null);
  const [loading, setLoading] = useState(true);
  const [form, setForm] = useState({ start_date: "", end_date: "", reason: "" });
  const [submitting, setSubmitting] = useState(false);
  const [editing, setEditing] = useState(null);
  const [editForm, setEditForm] = useState({ start_date: "", end_date: "", reason: "" });
  const [busyId, setBusyId] = useState(null);

  const load = () => {
    setLoading(true);
    const year = new Date().getFullYear();
    Promise.all([CoachSelfAPI.myLeaves(), CoachSelfAPI.leaveBalance(user.id, year)])
      .then(([leavesRes, balanceRes]) => {
        setLeaves(leavesRes.data);
        setBalance(balanceRes.data);
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load leave data"))
      .finally(() => setLoading(false));
  };

  useEffect(load, []);

  const submit = async (e) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      await CoachSelfAPI.requestLeave(form);
      toast.success("Leave request submitted");
      setForm({ start_date: "", end_date: "", reason: "" });
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to submit request");
    } finally {
      setSubmitting(false);
    }
  };

  const openEdit = (leave) => {
    setEditing(leave);
    setEditForm({ start_date: leave.start_date, end_date: leave.end_date, reason: leave.reason });
  };

  const submitEdit = async (e) => {
    e.preventDefault();
    try {
      await CoachSelfAPI.updateLeave(editing.id, editForm);
      toast.success("Leave request updated");
      setEditing(null);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Update failed");
    }
  };

  const cancelLeave = async (leave) => {
    if (!confirm("Cancel this leave request?")) return;
    setBusyId(leave.id);
    try {
      await CoachSelfAPI.cancelLeave(leave.id);
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

      {balance && (
        <div className="stat-grid">
          <div className="stat-card">
            <div className="stat-label">Entitlement</div>
            <div className="stat-value">{balance.entitlement_days}</div>
          </div>
          <div className="stat-card">
            <div className="stat-label">Used</div>
            <div className="stat-value">{balance.used_days}</div>
          </div>
          <div className="stat-card">
            <div className="stat-label">Remaining</div>
            <div className="stat-value">{balance.remaining_days}</div>
          </div>
        </div>
      )}

      <div className="card">
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
            <textarea rows={3} required value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} />
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
                <th>Note</th>
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
                      <div style={{ display: "flex", gap: 6 }}>
                        <button className="btn btn-secondary" onClick={() => openEdit(l)}>
                          Edit
                        </button>
                        <button className="btn btn-danger" disabled={busyId === l.id} onClick={() => cancelLeave(l)}>
                          Cancel
                        </button>
                      </div>
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

      {editing && (
        <Modal title="Edit Leave Request" onClose={() => setEditing(null)}>
          <form onSubmit={submitEdit}>
            <div style={{ display: "flex", gap: 12 }}>
              <div className="field" style={{ flex: 1 }}>
                <label>Start date</label>
                <input
                  type="date"
                  required
                  value={editForm.start_date}
                  onChange={(e) => setEditForm({ ...editForm, start_date: e.target.value })}
                />
              </div>
              <div className="field" style={{ flex: 1 }}>
                <label>End date</label>
                <input
                  type="date"
                  required
                  value={editForm.end_date}
                  onChange={(e) => setEditForm({ ...editForm, end_date: e.target.value })}
                />
              </div>
            </div>
            <div className="field">
              <label>Reason</label>
              <textarea rows={3} required value={editForm.reason} onChange={(e) => setEditForm({ ...editForm, reason: e.target.value })} />
            </div>
            <div className="modal-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setEditing(null)}>
                Cancel
              </button>
              <button className="btn btn-primary">Save</button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
