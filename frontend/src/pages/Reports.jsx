import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from "recharts";
import { ReportsAPI } from "../api/endpoints";
import Modal from "../components/Modal";
import ActivityReportPanel from "../components/ActivityReportPanel";

const MONTH_NAMES = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

export default function Reports() {
  const now = new Date();
  const [month, setMonth] = useState(now.getMonth() + 1);
  const [year, setYear] = useState(now.getFullYear());
  const [analysis, setAnalysis] = useState(null);
  const [hundredPct, setHundredPct] = useState([]);
  const [loading, setLoading] = useState(true);
  const [viewingActivity, setViewingActivity] = useState(null);

  const load = () => {
    setLoading(true);
    Promise.all([ReportsAPI.monthlyAnalysis(month, year), ReportsAPI.hundredPercentCoaches(month, year)])
      .then(([a, h]) => {
        setAnalysis(a.data);
        setHundredPct(h.data);
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load analytics"))
      .finally(() => setLoading(false));
  };

  useEffect(load, [month, year]);

  const revenueDelta = analysis ? analysis.monthly_revenue - analysis.prev_month_revenue : 0;
  const attendanceDelta = analysis ? analysis.attendance_rate - analysis.prev_month_attendance_rate : 0;

  return (
    <div>
      <div className="page-header">
        <h1>Business Analytics</h1>
        <div style={{ display: "flex", gap: 8 }}>
          <select value={month} onChange={(e) => setMonth(Number(e.target.value))}>
            {MONTH_NAMES.slice(1).map((m, i) => (
              <option key={i + 1} value={i + 1}>
                {m}
              </option>
            ))}
          </select>
          <input type="number" value={year} onChange={(e) => setYear(Number(e.target.value))} style={{ width: 100 }} />
        </div>
      </div>

      {loading || !analysis ? (
        <div className="empty-state">Loading analytics...</div>
      ) : (
        <>
          <div className="stat-grid">
            <div className="stat-card">
              <div className="stat-label">Total Students</div>
              <div className="stat-value">{analysis.total_students}</div>
            </div>
            <div className="stat-card">
              <div className="stat-label">Total Coaches</div>
              <div className="stat-value">{analysis.total_coaches}</div>
            </div>
            <div className="stat-card">
              <div className="stat-label">Total Classes</div>
              <div className="stat-value">{analysis.total_classes}</div>
            </div>
            <div className="stat-card">
              <div className="stat-label">Attendance Rate</div>
              <div className="stat-value">
                {analysis.attendance_rate}%{" "}
                <span style={{ fontSize: "0.8rem", color: attendanceDelta >= 0 ? "var(--success)" : "var(--danger)" }}>
                  {attendanceDelta >= 0 ? "▲" : "▼"} {Math.abs(attendanceDelta).toFixed(1)}pp
                </span>
              </div>
            </div>
            <div className="stat-card">
              <div className="stat-label">Monthly Revenue</div>
              <div className="stat-value">
                ₹{analysis.monthly_revenue.toLocaleString()}{" "}
                <span style={{ fontSize: "0.8rem", color: revenueDelta >= 0 ? "var(--success)" : "var(--danger)" }}>
                  {revenueDelta >= 0 ? "▲" : "▼"} ₹{Math.abs(revenueDelta).toLocaleString()}
                </span>
              </div>
            </div>
          </div>

          <div className="card">
            <h3 style={{ marginTop: 0 }}>Activity Breakdown</h3>
            <ResponsiveContainer width="100%" height={280}>
              <BarChart data={analysis.activity_breakdown}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="activity_name" fontSize={12} />
                <YAxis yAxisId="left" fontSize={12} />
                <YAxis yAxisId="right" orientation="right" fontSize={12} />
                <Tooltip />
                <Legend />
                <Bar yAxisId="left" dataKey="avg_attendance_pct" name="Attendance %" fill="#CC7000" radius={[4, 4, 0, 0]} />
                <Bar yAxisId="right" dataKey="revenue" name="Revenue (₹)" fill="#E6D200" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>

            <table style={{ marginTop: 12 }}>
              <thead>
                <tr>
                  <th>Activity</th>
                  <th>Students</th>
                  <th>Total Classes</th>
                  <th>Present</th>
                  <th>Absent</th>
                  <th>Avg Attendance %</th>
                  <th>Revenue (Projected)</th>
                  <th>Revenue Collected</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {analysis.activity_breakdown.map((a) => (
                  <tr key={a.activity_id}>
                    <td>{a.activity_name}</td>
                    <td>{a.student_count}</td>
                    <td>{a.total_classes}</td>
                    <td>{a.total_present}</td>
                    <td>{a.total_absent}</td>
                    <td>{a.avg_attendance_pct}%</td>
                    <td>₹{a.revenue.toLocaleString()}</td>
                    <td>₹{a.revenue_collected.toLocaleString()}</td>
                    <td className="table-actions">
                      <button className="btn btn-secondary btn-sm" onClick={() => setViewingActivity(a)}>
                        View
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p style={{ fontSize: "0.78rem", color: "var(--text-muted)", marginTop: 8 }}>
              "Revenue (Projected)" is monthly fee × enrolled students. "Revenue Collected" attributes each student's
              actual paid fee proportionally across their enrolled activities, since fees aren't tracked per-activity.
            </p>
          </div>

          <div className="card">
            <h3 style={{ marginTop: 0 }}>Coaches with 100% Student Attendance</h3>
            {hundredPct.length === 0 ? (
              <div className="empty-state">No coach hit 100% attendance this period.</div>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>Coach</th>
                    <th>Attendance %</th>
                  </tr>
                </thead>
                <tbody>
                  {hundredPct.map((c) => (
                    <tr key={c.coach_id}>
                      <td>{c.coach_name}</td>
                      <td>{c.attendance_pct}%</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </>
      )}

      {viewingActivity && (
        <Modal title={`Report: ${viewingActivity.activity_name}`} onClose={() => setViewingActivity(null)}>
          <ActivityReportPanel activityId={viewingActivity.activity_id} />
        </Modal>
      )}
    </div>
  );
}
