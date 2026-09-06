import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { useAuth } from "../../context/AuthContext";
import { CoachSelfAPI } from "../../api/endpoints";

const MONTH_NAMES = [
  "", "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

export default function CoachSalary() {
  const { user } = useAuth();
  const [salaries, setSalaries] = useState([]);
  const [loading, setLoading] = useState(true);
  const [ackId, setAckId] = useState(null);

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
    </div>
  );
}
