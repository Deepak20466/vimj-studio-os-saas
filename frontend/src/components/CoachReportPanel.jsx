import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { ReportsAPI, CoachesAPI } from "../api/endpoints";
import StatusBadge from "./StatusBadge";

export default function CoachReportPanel({ coachId }) {
  const [report, setReport] = useState(null);
  const [salary, setSalary] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([ReportsAPI.coachReport(coachId), CoachesAPI.salary(coachId)])
      .then(([r, s]) => {
        setReport(r.data);
        setSalary(s.data);
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load report"))
      .finally(() => setLoading(false));
  }, [coachId]);

  const downloadReport = async (fmt) => {
    try {
      const { data } = await ReportsAPI.exportCoach(coachId, fmt);
      const url = window.URL.createObjectURL(new Blob([data]));
      const a = document.createElement("a");
      a.href = url;
      a.download = `coach_${coachId}_report.${fmt}`;
      a.click();
      window.URL.revokeObjectURL(url);
    } catch {
      toast.error("Export failed");
    }
  };

  if (loading) return <div className="empty-state">Loading report...</div>;
  if (!report) return null;

  return (
    <div>
      <div className="stat-grid" style={{ marginBottom: 12 }}>
        <div className="stat-card">
          <div className="stat-label">Student Attendance %</div>
          <div className="stat-value">{report.student_attendance_pct}%</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Leaves Taken</div>
          <div className="stat-value">{report.leaves_taken}</div>
        </div>
      </div>

      <table style={{ marginBottom: 16 }}>
        <tbody>
          <tr>
            <td>Total Classes</td>
            <td>{report.total_classes}</td>
          </tr>
          <tr>
            <td>Days Present</td>
            <td>{report.days_present}</td>
          </tr>
          <tr>
            <td>Days Absent</td>
            <td>{report.days_absent}</td>
          </tr>
        </tbody>
      </table>

      <h4>Salary History</h4>
      {salary.length === 0 ? (
        <div className="empty-state">No salary records yet.</div>
      ) : (
        <table style={{ marginBottom: 16 }}>
          <thead>
            <tr>
              <th>Period</th>
              <th>Amount</th>
              <th>Acknowledged</th>
            </tr>
          </thead>
          <tbody>
            {salary.map((s) => (
              <tr key={s.id}>
                <td>
                  {s.month}/{s.year}
                </td>
                <td>₹{s.amount}</td>
                <td>
                  <StatusBadge status={s.acknowledged_date ? "approved" : "pending"} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <div className="modal-actions">
        <button className="btn btn-secondary" onClick={() => downloadReport("csv")}>
          Export CSV
        </button>
        <button className="btn btn-primary" onClick={() => downloadReport("pdf")}>
          Export PDF
        </button>
      </div>
    </div>
  );
}
