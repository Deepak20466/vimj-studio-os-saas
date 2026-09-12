import { useEffect, useState } from "react";
import { PieChart, Pie, Cell, Tooltip, Legend, ResponsiveContainer, BarChart, Bar, XAxis, YAxis, CartesianGrid } from "recharts";
import { DashboardAPI, AttendanceAPI } from "../api/endpoints";
import toast from "react-hot-toast";
import useResizeAfterLoad from "../hooks/useResizeAfterLoad";

const PIE_COLORS = ["#16a34a", "#d97706", "#dc2626"];

export default function Dashboard() {
  const [summary, setSummary] = useState(null);
  const [feeGraph, setFeeGraph] = useState(null);
  const [missing, setMissing] = useState([]);
  const [activityAttendance, setActivityAttendance] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      DashboardAPI.summary(),
      DashboardAPI.feeStatus(),
      AttendanceAPI.dailyMissing(),
      DashboardAPI.activityAttendance(),
    ])
      .then(([s, f, m, a]) => {
        setSummary(s.data);
        setFeeGraph(f.data);
        setMissing(m.data);
        setActivityAttendance(a.data.points);
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load dashboard"))
      .finally(() => setLoading(false));
  }, []);

  useResizeAfterLoad(!loading);

  if (loading) return <div className="empty-state">Loading dashboard...</div>;

  const feeData = feeGraph
    ? [
        { name: "Paid", value: feeGraph.paid },
        { name: "Unpaid", value: feeGraph.unpaid },
        { name: "Overdue", value: feeGraph.overdue },
      ]
    : [];

  const activityData = activityAttendance.map((a) => ({
    name: a.activity_name,
    attendance: a.avg_attendance_pct,
  }));

  return (
    <div>
      <div className="page-header">
        <h1>Dashboard</h1>
      </div>

      <div className="stat-grid">
        <div className="stat-card">
          <div className="stat-label">Total Students</div>
          <div className="stat-value">{summary.total_students}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Total Coaches</div>
          <div className="stat-value">{summary.total_coaches}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Classes This Month</div>
          <div className="stat-value">{summary.total_classes_this_month}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Monthly Revenue</div>
          <div className="stat-value">₹{summary.monthly_revenue.toLocaleString()}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Unpaid/Overdue Fees</div>
          <div className="stat-value">{summary.unpaid_fees_count}</div>
        </div>
      </div>

      <div className="chart-grid">
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Fee Status</h3>
          <ResponsiveContainer width="100%" height={260}>
            <PieChart>
              <Pie data={feeData} dataKey="value" nameKey="name" outerRadius={90} label>
                {feeData.map((_, i) => (
                  <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />
                ))}
              </Pie>
              <Tooltip />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
        </div>

        <div className="card">
          <h3 style={{ marginTop: 0 }}>Activity Attendance %</h3>
          <ResponsiveContainer width="100%" height={260}>
            <BarChart data={activityData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="name" fontSize={12} />
              <YAxis fontSize={12} />
              <Tooltip />
              <Bar dataKey="attendance" fill="#CC7000" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Coaches Missing Attendance Today</h3>
        {missing.length === 0 ? (
          <div className="empty-state">All coaches have marked attendance for ended classes today.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Coach</th>
                <th>Activity</th>
                <th>Class Date</th>
                <th>End Time</th>
              </tr>
            </thead>
            <tbody>
              {missing.map((m) => (
                <tr key={m.class_id}>
                  <td>{m.coach_name}</td>
                  <td>{m.activity_name}</td>
                  <td>{m.date}</td>
                  <td>{m.end_time}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
