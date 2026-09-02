import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { LeaveAPI } from "../api/endpoints";
import Modal from "../components/Modal";

export default function Leave() {
  const [pending, setPending] = useState([]);
  const [loading, setLoading] = useState(true);
  const [decision, setDecision] = useState(null); // { leave, action }
  const [note, setNote] = useState("");

  const load = () => {
    setLoading(true);
    LeaveAPI.pending()
      .then((r) => setPending(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load leave requests"))
      .finally(() => setLoading(false));
  };

  useEffect(load, []);

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

  return (
    <div>
      <div className="page-header">
        <h1>Leave Requests</h1>
      </div>

      <div className="card">
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : pending.length === 0 ? (
          <div className="empty-state">No pending leave requests.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Coach ID</th>
                <th>Start</th>
                <th>End</th>
                <th>Reason</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {pending.map((l) => (
                <tr key={l.id}>
                  <td>{l.coach_id}</td>
                  <td>{l.start_date}</td>
                  <td>{l.end_date}</td>
                  <td>{l.reason}</td>
                  <td>
                    <button className="btn btn-primary" style={{ marginRight: 6 }} onClick={() => openDecision(l, "approve")}>
                      Approve
                    </button>
                    <button className="btn btn-danger" onClick={() => openDecision(l, "reject")}>
                      Reject
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
    </div>
  );
}
