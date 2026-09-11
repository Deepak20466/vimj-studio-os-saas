import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { useAuth } from "../../context/AuthContext";
import { CoachSelfAPI, ResetAPI } from "../../api/endpoints";
import Modal from "../../components/Modal";

const MONTH_NAMES = [
  "", "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

export default function CoachSalary() {
  const { user } = useAuth();
  const [salaries, setSalaries] = useState([]);
  const [loading, setLoading] = useState(true);
  const [ackId, setAckId] = useState(null);
  const [showReset, setShowReset] = useState(false);
  const [resetConfirmText, setResetConfirmText] = useState("");
  const [resetting, setResetting] = useState(false);

  const load = () => {
    setLoading(true);
    CoachSelfAPI.salaryHistory(user.id)
      .then((r) => setSalaries(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load salary history"))
      .finally(() => setLoading(false));
  };

  useEffect(load, []);

  const acknowledge = async (salaryId) => {
    setAckId(salaryId);
    try {
      await CoachSelfAPI.acknowledgeSalary(salaryId);
      toast.success("Salary acknowledged");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to acknowledge");
    } finally {
      setAckId(null);
    }
  };

  const submitReset = async () => {
    if (resetConfirmText.trim().toUpperCase() !== "RESET") return;
    setResetting(true);
    try {
      const { data } = await ResetAPI.mine();
      toast.success(data.detail || "Your history has been reset");
      setShowReset(false);
    } catch (err) {
      toast.error(err.response?.data?.detail || "Reset failed");
    } finally {
      setResetting(false);
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>Salary</h1>
      </div>

      <div className="card">
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : salaries.length === 0 ? (
          <div className="empty-state">No salary records yet.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Period</th>
                <th>Amount</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {salaries.map((s) => (
                <tr key={s.id}>
                  <td>
                    {MONTH_NAMES[s.month]} {s.year}
                  </td>
                  <td>₹{Number(s.amount).toLocaleString()}</td>
                  <td>
                    {s.acknowledged_date ? (
                      <span className="badge badge-paid">Acknowledged</span>
                    ) : (
                      <button className="btn btn-primary" disabled={ackId === s.id} onClick={() => acknowledge(s.id)}>
                        {ackId === s.id ? "Working..." : "Acknowledge"}
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="card" style={{ maxWidth: 640, marginTop: 24, borderColor: "var(--danger)" }}>
        <h3 style={{ marginTop: 0, color: "var(--danger)" }}>Danger Zone</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)" }}>
          Reset your own attendance, leave, and swap history back to a clean slate. This does not
          affect any other coach's data, and cannot be undone.
        </p>
        <button className="btn btn-danger" onClick={() => { setResetConfirmText(""); setShowReset(true); }}>
          Reset My Data
        </button>
      </div>

      {showReset && (
        <Modal title="Reset My Data?" onClose={() => setShowReset(false)}>
          <p>
            This permanently erases <strong>your own</strong> attendance, leave, and swap history.
            It does not touch any other coach's data. This cannot be undone.
          </p>
          <div className="field">
            <label>
              Type <strong>RESET</strong> to confirm
            </label>
            <input value={resetConfirmText} onChange={(e) => setResetConfirmText(e.target.value)} autoFocus />
          </div>
          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={() => setShowReset(false)}>
              Cancel
            </button>
            <button
              className="btn btn-danger"
              disabled={resetting || resetConfirmText.trim().toUpperCase() !== "RESET"}
              onClick={submitReset}
            >
              {resetting ? "Resetting..." : "Reset My Data"}
            </button>
          </div>
        </Modal>
      )}
    </div>
  );
}
