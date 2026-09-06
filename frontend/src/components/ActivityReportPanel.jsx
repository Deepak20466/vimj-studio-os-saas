import { useEffect, useState } from "react";
import { LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from "recharts";
import toast from "react-hot-toast";
import { ReportsAPI, ActivitiesAPI } from "../api/endpoints";
import useResizeAfterLoad from "../hooks/useResizeAfterLoad";

function formatTiming(startTime) {
  const [hStr, mStr] = startTime.split(":");
  let h = Number(hStr);
  const m = mStr || "00";
  const suffix = h >= 12 ? "PM" : "AM";
  h = h % 12;
  if (h === 0) h = 12;
  return `${h}:${m} ${suffix}`;
}

function BatchCard({ batch, activityName }) {
  const barData = [
    { name: "Attendance", Present: batch.present_count, Absent: batch.absent_count },
    { name: "Fees", Paid: batch.fee_paid_count, Unpaid: batch.fee_unpaid_count },
  ];
  return (
    <div className="card" style={{ marginBottom: 12 }}>
      <div style={{ display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: 8, marginBottom: 8 }}>
        <div>
          <span className="badge" style={{ marginRight: 8 }}>{activityName}</span>
          <strong>{batch.location}</strong>
          <span style={{ color: "var(--text-muted)", fontSize: "0.85rem" }}>
            {" "}
            · {batch.start_time}–{batch.end_time} · {batch.days_of_week.join(", ")}
          </span>
        </div>
        <span style={{ fontSize: "0.85rem", color: "var(--text-muted)" }}>Coach: {batch.coach_name}</span>
      </div>

      <div className="stat-grid" style={{ marginBottom: 12 }}>
        <div className="stat-card">
          <div className="stat-label">Students</div>
          <div className="stat-value">{batch.student_count}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Attendance %</div>
          <div className="stat-value">{batch.attendance_pct}%</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Fees Paid / Unpaid</div>
          <div className="stat-value" style={{ fontSize: "1.1rem" }}>
            {batch.fee_paid_count} / {batch.fee_unpaid_count}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Fee Revenue</div>
          <div className="stat-value" style={{ fontSize: "1.1rem" }}>₹{batch.fee_revenue.toLocaleString()}</div>
        </div>
      </div>

      <ResponsiveContainer width="100%" height={180}>
        <BarChart data={barData}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey="name" fontSize={11} />
          <YAxis fontSize={11} allowDecimals={false} />
          <Tooltip />
          <Legend />
          <Bar dataKey="Present" fill="#B35900" />
          <Bar dataKey="Absent" fill="#fee2e2" />
          <Bar dataKey="Paid" fill="#16a34a" />
          <Bar dataKey="Unpaid" fill="#fef3c7" />
        </BarChart>
      </ResponsiveContainer>

      {batch.students.length === 0 ? (
        <div className="empty-state">No student records yet for this batch.</div>
      ) : (
        <table style={{ marginTop: 8 }}>
          <thead>
            <tr>
              <th>Student</th>
              <th>Phone</th>
              <th>Fee Status</th>
            </tr>
          </thead>
          <tbody>
            {batch.students.map((s) => (
              <tr key={s.id}>
                <td>{s.name}</td>
                <td>{s.phone || "-"}</td>
                <td>
                  <span className={`badge ${s.fee_status === "PAID" ? "badge-paid" : s.fee_status === "OVERDUE" ? "badge-overdue" : "badge-unpaid"}`}>
                    {s.fee_status}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

function TimingsSection({ sessionBreakdown, activityName }) {
  const allBatches = sessionBreakdown.flatMap((g) => g.batches);
  const timings = [...new Set(allBatches.map((b) => b.start_time))].sort();
  const [selected, setSelected] = useState(timings[0]);
  const activeTiming = timings.includes(selected) ? selected : timings[0];
  const batches = allBatches.filter((b) => b.start_time === activeTiming);

  const totalStudents = new Set(batches.flatMap((b) => b.students.map((s) => s.id))).size;
  const totalCoaches = new Set(batches.map((b) => b.coach_id).filter(Boolean)).size;
  const totalPresent = batches.reduce((sum, b) => sum + b.present_count, 0);
  const totalAbsent = batches.reduce((sum, b) => sum + b.absent_count, 0);
  const totalMarks = totalPresent + totalAbsent;
  const attendancePct = totalMarks ? Math.round((totalPresent / totalMarks) * 10000) / 100 : 0;
  const feePaid = batches.reduce((sum, b) => sum + b.fee_paid_count, 0);
  const feeUnpaid = batches.reduce((sum, b) => sum + b.fee_unpaid_count, 0);
  const feeRevenue = batches.reduce((sum, b) => sum + b.fee_revenue, 0);

  return (
    <div style={{ marginBottom: 16 }}>
      <h4>Timings</h4>
      <div className="tab-bar">
        {timings.map((t) => (
          <button key={t} className={t === activeTiming ? "active" : ""} onClick={() => setSelected(t)}>
            {formatTiming(t)}
          </button>
        ))}
      </div>

      <div className="stat-grid" style={{ marginBottom: 12 }}>
        <div className="stat-card">
          <div className="stat-label">Total Students</div>
          <div className="stat-value">{totalStudents}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Total Coaches</div>
          <div className="stat-value">{totalCoaches}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Present / Absent</div>
          <div className="stat-value" style={{ fontSize: "1.1rem" }}>
            {totalPresent} / {totalAbsent}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Attendance %</div>
          <div className="stat-value">{attendancePct}%</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Fees Paid / Unpaid</div>
          <div className="stat-value" style={{ fontSize: "1.1rem" }}>
            {feePaid} / {feeUnpaid}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Fee Revenue</div>
          <div className="stat-value" style={{ fontSize: "1.1rem" }}>₹{feeRevenue.toLocaleString()}</div>
        </div>
      </div>

      <h5 style={{ margin: "0 0 8px", color: "var(--brand-orange-dark)" }}>
        {activityName} — {formatTiming(activeTiming)} batches
      </h5>
      {batches.length === 0 ? (
        <div className="empty-state">No batches scheduled at this timing.</div>
      ) : (
        batches.map((b) => <BatchCard key={b.group_key} batch={b} activityName={activityName} />)
      )}
    </div>
  );
}

export default function ActivityReportPanel({ activityId }) {
  const [activities, setActivities] = useState([]);
  const [selectedActivityId, setSelectedActivityId] = useState(activityId);
  const [sportSearch, setSportSearch] = useState("");
  const [report, setReport] = useState(null);
  const [loading, setLoading] = useState(true);
  const [showTimings, setShowTimings] = useState(false);

  useEffect(() => {
    ActivitiesAPI.list()
      .then((r) => setActivities(r.data))
      .catch(() => {});
  }, []);

  useEffect(() => {
    setLoading(true);
    ReportsAPI.activityDetail(selectedActivityId)
      .then((r) => setReport(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load activity report"))
      .finally(() => setLoading(false));
  }, [selectedActivityId]);

  const filteredActivities = activities.filter((a) => a.name.toLowerCase().includes(sportSearch.toLowerCase()));

  useResizeAfterLoad(!loading && !!report);

  if (loading) return <div className="empty-state">Loading report...</div>;
  if (!report) return null;

  return (
    <div>
      <div className="stat-grid" style={{ marginBottom: 12 }}>
        <div className="stat-card">
          <div className="stat-label">Students</div>
          <div className="stat-value">{report.student_count}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Attendance %</div>
          <div className="stat-value">{report.attendance_pct}%</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Revenue Collected</div>
          <div className="stat-value">₹{report.revenue_collected.toLocaleString()}</div>
        </div>
      </div>

      <table style={{ marginBottom: 16 }}>
        <tbody>
          <tr>
            <td>Total Classes</td>
            <td>{report.total_classes}</td>
          </tr>
          <tr>
            <td>Total Present</td>
            <td>{report.total_present}</td>
          </tr>
          <tr>
            <td>Total Absent</td>
            <td>{report.total_absent}</td>
          </tr>
          <tr>
            <td>Fees Paid / Unpaid</td>
            <td>
              {report.fee_paid_count} / {report.fee_unpaid_count}
            </td>
          </tr>
        </tbody>
      </table>

      {report.attendance_graph.length > 0 && (
        <div style={{ marginBottom: 16 }}>
          <h4 style={{ marginBottom: 4 }}>Attendance Trend</h4>
          <ResponsiveContainer width="100%" height={200}>
            <LineChart data={report.attendance_graph}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="label" fontSize={11} />
              <YAxis fontSize={11} />
              <Tooltip />
              <Line type="monotone" dataKey="value" stroke="#B35900" strokeWidth={2} name="Attendance %" />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}

      <div style={{ marginBottom: 16 }}>
        <button className="btn btn-secondary" onClick={() => setShowTimings((v) => !v)}>
          {showTimings ? "Hide Timings" : "Timings"}
        </button>
        {showTimings && (
          <div style={{ marginTop: 12 }}>
            <div className="field" style={{ maxWidth: 320, marginBottom: 8 }}>
              <label>Search Sport/Activity</label>
              <input
                value={sportSearch}
                onChange={(e) => setSportSearch(e.target.value)}
                placeholder="e.g. Badminton, Football..."
              />
            </div>
            <div className="tab-bar" style={{ flexWrap: "wrap" }}>
              {filteredActivities.length === 0 ? (
                <span style={{ color: "var(--text-muted)", fontSize: "0.85rem" }}>No activities match "{sportSearch}".</span>
              ) : (
                filteredActivities.map((a) => (
                  <button
                    key={a.id}
                    className={a.id === selectedActivityId ? "active" : ""}
                    onClick={() => setSelectedActivityId(a.id)}
                  >
                    {a.name}
                  </button>
                ))
              )}
            </div>
            {report.session_breakdown && report.session_breakdown.length > 0 ? (
              <TimingsSection key={selectedActivityId} sessionBreakdown={report.session_breakdown} activityName={report.activity_name} />
            ) : (
              <div className="empty-state">No batches/timings scheduled for {report.activity_name} yet.</div>
            )}
          </div>
        )}
      </div>

      <h4>Coach Breakdown</h4>
      {report.coach_breakdown.length === 0 ? (
        <div className="empty-state">No classes recorded for this activity yet.</div>
      ) : (
        <table>
          <thead>
            <tr>
              <th>Coach</th>
              <th>Total Classes</th>
              <th>Avg Attendance %</th>
            </tr>
          </thead>
          <tbody>
            {report.coach_breakdown.map((c) => (
              <tr key={c.coach_id}>
                <td>{c.coach_name}</td>
                <td>{c.total_classes}</td>
                <td>{c.avg_attendance_pct}%</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
