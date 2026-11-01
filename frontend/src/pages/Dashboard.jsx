import { useEffect, useState } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  Line,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { AttendanceAPI, DashboardAPI, FeesAPI } from "../api/endpoints";
import toast from "react-hot-toast";
import useResizeAfterLoad from "../hooks/useResizeAfterLoad";
import { dismissItem, filterDismissed } from "../utils/dismissedItems";
import "./admin-dashboard.css";

const rupees = (value) => `Rs ${Number(value || 0).toLocaleString("en-IN", { maximumFractionDigits: 0 })}`;

export default function Dashboard() {
  const [insights, setInsights] = useState(null);
  const [missing, setMissing] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadFailed, setLoadFailed] = useState(false);
  const [reminding, setReminding] = useState(false);

  useEffect(() => {
    Promise.all([DashboardAPI.revenueRisk(), AttendanceAPI.dailyMissing()])
      .then(([riskResponse, missingResponse]) => {
        setInsights(riskResponse.data);
        setMissing(filterDismissed("missing_attendance", missingResponse.data, (row) => row.class_id));
      })
      .catch((err) => {
        toast.error(err.response?.data?.detail || "Failed to load Admin AI Command Center");
        setLoadFailed(true);
      })
      .finally(() => setLoading(false));
  }, []);

  useResizeAfterLoad(!loading);

  if (loading) return <div className="empty-state">Loading Admin Command Center...</div>;
  if (loadFailed || !insights) {
    return <div className="empty-state">Failed to load dashboard data. Please refresh the page.</div>;
  }

  const kpis = insights.kpis || {};
  const batchRows = insights.batch_analytics?.batches || [];
  const riskTotal = insights.summary?.total_at_risk || 0;
  const feeRisk = (insights.risks || []).find((risk) => risk.type === "fee_default");
  const forecast = insights.forecast?.next_month_revenue || 0;
  const trendIsDown = riskTotal > 0;

  const sendReminders = async () => {
    const feeIds = [...new Set(feeRisk?.fee_ids || [])];
    if (!feeIds.length) return;
    setReminding(true);
    const results = await Promise.allSettled(feeIds.map((feeId) => FeesAPI.remind(feeId)));
    const queued = results.filter((result) => result.status === "fulfilled").length;
    if (queued) toast.success(`${queued} reminder${queued === 1 ? "" : "s"} queued (mock WhatsApp)`);
    if (queued < feeIds.length) toast.error(`${feeIds.length - queued} reminder${feeIds.length - queued === 1 ? "" : "s"} could not be queued`);
    setReminding(false);
  };

  const dismissMissing = (classId) => {
    dismissItem("missing_attendance", classId);
    setMissing((previous) => previous.filter((row) => row.class_id !== classId));
  };

  return (
    <div className="admin-command-center">
      <div className="page-header ai-center-header">
        <div>
          <h1>Admin AI Command Center</h1>
          <p>Local rule-based revenue and attendance insights</p>
        </div>
      </div>

      <div className="stat-grid ai-kpi-grid">
        <div className="stat-card">
          <div className="stat-label">Total Students</div>
          <div className="stat-value">{Number(kpis.total_students || 0).toLocaleString("en-IN")}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Today Present</div>
          <div className="stat-value">{Number(kpis.today_present || 0).toLocaleString("en-IN")}</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Fee Pending Amount</div>
          <div className="stat-value">{rupees(kpis.fee_pending_amount)}</div>
        </div>
        <div className={`stat-card ${riskTotal > 0 ? "stat-risk" : ""}`}>
          <div className="stat-label">Revenue at Risk</div>
          <div className="stat-value">{rupees(riskTotal)}</div>
        </div>
      </div>

      <div className="ai-card-grid">
        <section className="card ai-panel">
          <div className="ai-panel-heading">
            <h2>⚠️ AI Revenue Risk</h2>
            <span className="ai-local-badge">Local rules</span>
          </div>
          <div className="ai-risk-list">
            {(insights.risks || []).map((risk) => (
              <article className="ai-risk-item" key={risk.type}>
                <div className="ai-risk-icon" aria-hidden="true">{risk.revenue_at_risk > 0 ? "⚠️" : "•"}</div>
                <div className="ai-risk-copy">
                  <strong>{risk.message}</strong>
                  <span>{rupees(risk.revenue_at_risk)} at risk</span>
                  {risk.batches?.length > 0 && (
                    <ul className="ai-risk-batches">
                      {risk.batches.map((batch) => <li key={batch.batch_id}>{batch.batch_name} — down {batch.attendance_drop_pct}%</li>)}
                    </ul>
                  )}
                </div>
              </article>
            ))}
          </div>
          {feeRisk?.fee_ids?.length > 0 && (
            <button className="btn btn-primary ai-reminder-button" disabled={reminding} onClick={sendReminders}>
              {reminding ? "Queueing..." : "Send Reminders"}
            </button>
          )}
        </section>

        <section className="card ai-panel ai-forecast-panel">
          <div className="ai-panel-heading">
            <h2>📈 AI Forecast</h2>
            <span className="ai-local-badge">3-month average</span>
          </div>
          <div className="ai-forecast-primary">
            <span className={`ai-forecast-arrow ${trendIsDown ? "down" : "up"}`} aria-label={trendIsDown ? "Revenue risk is present" : "No flagged revenue risk"}>
              {trendIsDown ? "↓" : "↑"}
            </span>
            <div>
              <span className="stat-label">Predicted next month</span>
              <strong>{rupees(forecast)}</strong>
            </div>
          </div>
          <div className="ai-forecast-at-risk">
            <span>At Risk</span>
            <strong>{rupees(riskTotal)}</strong>
          </div>
          <p className="ai-forecast-note">Forecast uses collected fee totals from {insights.forecast?.months_used?.join(", ") || "the latest three billing months"}.</p>
        </section>
      </div>

      <section className="card ai-chart-panel">
        <div className="ai-panel-heading">
          <div>
            <h2>Batch Profitability vs Attendance</h2>
            <p>Estimated monthly tuition share compared with recent attendance</p>
          </div>
        </div>
        {batchRows.length === 0 ? (
          <div className="empty-state">No active batches are available for comparison.</div>
        ) : (
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={batchRows} margin={{ top: 12, right: 16, left: 12, bottom: 45 }}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="batch_name" angle={-18} textAnchor="end" interval={0} height={70} fontSize={11} />
              <YAxis yAxisId="revenue" tickFormatter={(value) => `Rs ${Number(value).toLocaleString("en-IN")}`} fontSize={11} />
              <YAxis yAxisId="attendance" orientation="right" domain={[0, 100]} unit="%" fontSize={11} />
              <Tooltip formatter={(value, name) => name === "Attendance" ? [`${value}%`, name] : [rupees(value), name]} />
              <Legend verticalAlign="top" />
              <Bar yAxisId="revenue" dataKey="estimated_profit" name="Estimated profit*" fill="#CC7000" radius={[4, 4, 0, 0]} />
              <Line yAxisId="attendance" dataKey="attendance_pct" name="Attendance" stroke="#2563eb" strokeWidth={2} dot={{ r: 3 }} />
            </BarChart>
          </ResponsiveContainer>
        )}
        <p className="ai-chart-note">*Revenue estimate allocated by activity. Batch expense data is not stored.</p>
      </section>

      <section className="card">
        <h3 style={{ marginTop: 0 }}>Coaches Missing Attendance Today</h3>
        {missing.length === 0 ? (
          <div className="empty-state">All coaches have marked attendance for ended classes today.</div>
        ) : (
          <table>
            <thead><tr><th>Coach</th><th>Activity</th><th>Class Date</th><th>End Time</th><th>Actions</th></tr></thead>
            <tbody>
              {missing.map((row) => (
                <tr key={row.class_id}>
                  <td>{row.coach_name}</td><td>{row.activity_name}</td><td>{row.date}</td><td>{row.end_time}</td>
                  <td><button className="btn btn-danger btn-sm" title="Dismiss this alert" onClick={() => dismissMissing(row.class_id)}>Delete</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </div>
  );
}
