import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { LeaveAPI } from "../api/endpoints";
import StatusBadge from "../components/StatusBadge";

export default function Leave() {
  const [pending, setPending] = useState([]);
  const [pendingLoading, setPendingLoading] = useState(true);
  const [busyId, setBusyId] = useState(null);

  const [history, setHistory] = useState([]);
  const [historyLoading, setHistoryLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState("");

  const loadPending = () => {
    setPendingLoading(true);
    LeaveAPI.pending()
      .then((r) => setPending(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load pending leave requests"))
      .finally(() => setPendingLoading(false));
  };

  const loadHistory = () => {
    setHistoryLoading(true);
    LeaveAPI.list(statusFilter ? { status_filter: statusFilter } : {})
      .then((r) => setHistory(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load leave history"))
      .finally(() => setHistoryLoading(false));
  };

  useEffect(loadPending, []);
  useEffect(() => {
    loadHistory();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [statusFilter]);

  const decide = async (leave, approve) => {
    setBusyId(leave.id);
    try {
      if (approve) {
        await LeaveAPI.approve(leave.id, null);
        toast.success("Leave approved");
      } else {
        const note = prompt("Reason for rejecting (optional):") || "";
        await LeaveAPI.reject(leave.id, note);
        toast.success("Leave rejected");
      }
      loadPending();
      loadHistory();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Action failed");
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>Leave</h1>
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Pending Leave Requests</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -8 }}>
          Approve or reject a coach's leave request. Coaches are notified either way.
        </p>
        {pendingLoading ? (
          <div className="empty-state">Loading...</div>
        ) : pending.length === 0 ? (
          <div className="empty-state">No leave requests awaiting a decision.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Coach</th>
                <th>Start</th>
                <th>End</th>
                <th>Reason</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {pending.map((l) => (
                <tr key={l.id}>
                  <td>{l.coach_name}</td>
                  <td>{l.start_date}</td>
                  <td>{l.end_date}</td>
                  <td>{l.reason}</td>
                  <td className="table-actions">
                    <button className="btn btn-primary btn-sm" disabled={busyId === l.id} onClick={() => decide(l, true)}>
                      Approve
                    </button>
                    <button className="btn btn-danger btn-sm" disabled={busyId === l.id} onClick={() => decide(l, false)}>
                      Reject
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="card">
        <div className="page-header" style={{ marginBottom: 12 }}>
          <h3 style={{ margin: 0 }}>Leave History</h3>
          <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} style={{ width: "auto" }}>
            <option value="">All statuses</option>
            <option value="PENDING">Pending</option>
            <option value="APPROVED">Approved</option>
            <option value="REJECTED">Rejected</option>
          </select>
        </div>
        {historyLoading ? (
          <div className="empty-state">Loading...</div>
        ) : history.length === 0 ? (
          <div className="empty-state">No leave requests found.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Coach</th>
                <th>Start</th>
                <th>End</th>
                <th>Reason</th>
                <th>Status</th>
                <th>Note</th>
                <th>Submitted</th>
              </tr>
            </thead>
            <tbody>
              {history.map((l) => (
                <tr key={l.id}>
                  <td>{l.coach_name}</td>
                  <td>{l.start_date}</td>
                  <td>{l.end_date}</td>
                  <td>{l.reason}</td>
                  <td>
                    <StatusBadge status={l.status} />
                  </td>
                  <td>{l.decision_note || "—"}</td>
                  <td>{new Date(l.created_at).toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
