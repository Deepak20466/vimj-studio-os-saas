import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { LeaveAPI } from "../api/endpoints";
import Modal from "../components/Modal";
import StatusBadge from "../components/StatusBadge";

export default function Leave() {
  const [leaves, setLeaves] = useState([]);
  const [loading, setLoading] = useState(true);
  const [pendingOnly, setPendingOnly] = useState(true);
  const [decision, setDecision] = useState(null); // { leave, action }
  const [note, setNote] = useState("");
  const [editing, setEditing] = useState(null);
  const [editForm, setEditForm] = useState({ start_date: "", end_date: "", reason: "" });

  const load = () => {
    setLoading(true);
    const request = pendingOnly ? LeaveAPI.pending() : LeaveAPI.list();
    request
      .then((r) => setLeaves(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load leave requests"))
      .finally(() => setLoading(false));
  };

  useEffect(load, [pendingOnly]);

  const openDecision = (leave, action) => {
    setDecision({ leave, action });
    setNote("");
  };

  const confirmDecision = async (e) => {
    e.preventDefault();
    try {
      if (decision.action === "approve") {
        await LeaveAPI.approve(decision.leave.id, note);
        toast.success("Leave approved");
      } else {
        await LeaveAPI.reject(decision.leave.id, note);
        toast.success("Leave rejected");
      }
      setDecision(null);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Action failed");
    }
  };

  const openEdit = (leave) => {
    setEditing(leave);
    setEditForm({ start_date: leave.start_date, end_date: leave.end_date, reason: leave.reason });
  };

  const submitEdit = async (e) => {
    e.preventDefault();
    try {
      await LeaveAPI.update(editing.id, editForm);
      toast.success("Leave request updated");
      setEditing(null);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Update failed");
    }
  };

  const remove = async (leave) => {
    if (!confirm(`Delete this leave request from ${leave.coach_name || `#${leave.coach_id}`}?`)) return;
    try {
      await LeaveAPI.remove(leave.id);
      toast.success("Leave request deleted");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Delete failed");
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>Leave Requests</h1>
      </div>

      <div className="card">
        <div className="toolbar" style={{ marginBottom: 12 }}>
          <label style={{ display: "flex", alignItems: "center", gap: 6, fontSize: "0.85rem" }}>
            <input type="checkbox" checked={pendingOnly} onChange={(e) => setPendingOnly(e.target.checked)} />
            Show pending only
          </label>
        </div>
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : leaves.length === 0 ? (
          <div className="empty-state">No leave requests{pendingOnly ? " pending" : ""}.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Coach</th>
                <th>Start</th>
                <th>End</th>
                <th>Reason</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {leaves.map((l) => (
                <tr key={l.id}>
                  <td>{l.coach_name || `#${l.coach_id}`}</td>
                  <td>{l.start_date}</td>
                  <td>{l.end_date}</td>
                  <td>{l.reason}</td>
                  <td>
                    <StatusBadge status={l.status} />
                  </td>
                  <td className="table-actions">
                    {l.status === "PENDING" && (
                      <>
                        <button className="btn btn-primary btn-sm" onClick={() => openDecision(l, "approve")}>
                          Approve
                        </button>
                        <button className="btn btn-danger btn-sm" onClick={() => openDecision(l, "reject")}>
                          Reject
                        </button>
                      </>
                    )}
                    <button className="btn btn-secondary btn-sm" onClick={() => openEdit(l)}>
                      Edit
                    </button>
                    <button className="btn btn-danger btn-sm" onClick={() => remove(l)}>
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {decision && (
        <Modal title={`${decision.action === "approve" ? "Approve" : "Reject"} Leave Request`} onClose={() => setDecision(null)}>
          <form onSubmit={confirmDecision}>
            <div className="field">
              <label>Note (optional)</label>
              <textarea rows={3} value={note} onChange={(e) => setNote(e.target.value)} />
            </div>
            <div className="modal-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setDecision(null)}>
                Cancel
              </button>
              <button className={decision.action === "approve" ? "btn btn-primary" : "btn btn-danger"}>
                Confirm {decision.action === "approve" ? "Approval" : "Rejection"}
              </button>
            </div>
          </form>
        </Modal>
      )}

      {editing && (
        <Modal title={`Edit Leave Request — ${editing.coach_name || `#${editing.coach_id}`}`} onClose={() => setEditing(null)}>
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
