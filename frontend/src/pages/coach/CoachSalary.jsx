import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { useAuth } from "../../context/AuthContext";
import { SalaryAPI } from "../../api/endpoints";

const MONTH_NAMES = [
  "", "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

function formatDate(value) {
  if (!value) return "Not recorded";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleDateString();
}

export default function CoachSalary() {
  const { user } = useAuth();
  const [salaries, setSalaries] = useState([]);
  const [loading, setLoading] = useState(true);
  const [ackId, setAckId] = useState(null);

  const load = async () => {
    if (!user?.id) return;
    setLoading(true);
    try {
      const { data } = await SalaryAPI.coachHistory(user.id);
      setSalaries(data);
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to load salary history");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
    // The logged-in coach is stable for the lifetime of this protected route.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id]);

  const acknowledge = async (salaryId) => {
    setAckId(salaryId);
    try {
      await SalaryAPI.acknowledge(salaryId);
      toast.success("Salary receipt acknowledged");
      await load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to acknowledge salary");
    } finally {
      setAckId(null);
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>My Salary</h1>
        <button className="btn btn-secondary btn-sm" onClick={load} disabled={loading}>
          Refresh
        </button>
      </div>
      <div className="card">
        {loading ? (
          <div className="empty-state">Loading salary history...</div>
        ) : salaries.length === 0 ? (
          <div className="empty-state">No salary records yet.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Period</th>
                <th>Amount</th>
                <th>Notified</th>
                <th>Acknowledgement</th>
              </tr>
            </thead>
            <tbody>
              {salaries.map((salary) => (
                <tr key={salary.id}>
                  <td>{MONTH_NAMES[salary.month]} {salary.year}</td>
                  <td>?{Number(salary.amount).toLocaleString("en-IN", { minimumFractionDigits: 2 })}</td>
                  <td>{formatDate(salary.notified_at)}</td>
                  <td>
                    {salary.acknowledged_date ? (
                      <span className="badge badge-paid">
                        Acknowledged {formatDate(salary.acknowledged_date)}
                      </span>
                    ) : (
                      <button
                        className="btn btn-primary btn-sm"
                        disabled={ackId === salary.id}
                        onClick={() => acknowledge(salary.id)}
                      >
                        {ackId === salary.id ? "Saving..." : "Acknowledge"}
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