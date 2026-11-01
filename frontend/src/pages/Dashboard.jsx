import { useCallback, useEffect, useRef, useState } from "react";
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
  const [refreshing, setRefreshing] = useState(false);
  const [focus, setFocus] = useState("risk");
  const [lastUpdated, setLastUpdated] = useState(null);
  const [change, setChange] = useState(null);
  const refreshInFlight = useRef(false);
  const previousInsights = useRef(null);

  const loadDashboard = useCallback(async (silent = false) => {
    if (refreshInFlight.current) return;
    refreshInFlight.current = true;
    if (!silent && !previousInsights.current) setLoading(true);
    else setRefreshing(true);
    try {
      const [riskResult, missingResult] = await Promise.allSettled([
        DashboardAPI.revenueRisk(),
        AttendanceAPI.dailyMissing(),
      ]);
      if (riskResult.status === "fulfilled") {
        const next = riskResult.value.data;
        const previous = previousInsights.current;
        if (previous) {
          setChange({
            risk: Number(next.summary?.total_at_risk || 0) - Number(previous.summary?.total_at_risk || 0),
            forecast: Number(next.forecast?.next_month_revenue || 0) - Number(previous.forecast?.next_month_revenue || 0),
          });
        }
        previousInsights.current = next;
        setInsights(next);
        setLastUpdated(new Date());
        setLoadFailed(false);
      } else {
        if (!previousInsights.current) {
          setLoadFailed(true);
          toast.error(riskResult.reason?.response?.data?.detail || "Failed to load AI insights");
        }
      }
      if (missingResult.status === "fulfilled") {
        setMissing(filterDismissed("missing_attendance", missingResult.value.data, (row) => row.class_id));
      }
    } finally {
      setLoading(false);
      setRefreshing(false);
      refreshInFlight.current = false;
    }
  }, []);

  useEffect(() => {
    loadDashboard();
    const interval = window.setInterval(() => {
      if (document.visibilityState === "visible") loadDashboard(true);
    }, 30000);
    const refreshOnFocus = () => {
      if (document.visibilityState === "visible") loadDashboard(true);
    };
    window.addEventListener("focus", refreshOnFocus);
    document.addEventListener("visibilitychange", refreshOnFocus);
    return () => {
      window.clearInterval(interval);
      window.removeEventListener("focus", refreshOnFocus);
      document.removeEventListener("visibilitychange", refreshOnFocus);
    };
  }, [loadDashboard]);

  useResizeAfterLoad(!loading);

  if (loading) return <div className="empty-state">Loading Admin Command Center...</div>;
  if (loadFailed || !insights) {
    return <div className="empty-state">Failed to load dashboard data. <button className="btn btn-secondary btn-sm" onClick={() => loadDashboard(false)}>Try again</button></div>;
  }

  const kpis = insights.kpis || {};
  const batchRows = insights.batch_analytics?.batches || [];
  const riskTotal = insights.summary?.total_at_risk || 0;
  const feeRisk = (insights.risks || []).find((risk) => risk.type === "fee_default");
  const forecast = insights.forecast?.next_month_revenue || 0;
  const riskCandidates = (insights.risks || []).filter((risk) => risk.type !== "revenue_forecast");
  const topRisk = [...riskCandidates].sort((a, b) => Number(b.revenue_at_risk || 0) - Number(a.revenue_at_risk || 0))[0];
  const bestBatch = insights.batch_analytics?.most_profitable_batch;
  const deltaLabel = (value) => {
    if (value == null || value === 0) return "No change since last refresh";
    return `${value > 0 ? "↑" : "↓"} ${rupees(Math.abs(value))} since last refresh`;
  };

  const sendReminders = async () => {
    const feeIds = [...new Set(feeRisk?.fee_ids || [])];
    if (!feeIds.length) return;
    setReminding(true);
    const results = await Promise.allSettled(feeIds.map((feeId) => FeesAPI.remind(feeId)));
    const queued = results.filter((result) => result.status === "fulfilled").length;
    if (queued) toast.success(`${queued} reminder${queued === 1 ? "" : "s"} queued (mock WhatsApp)`);
    if (queued < feeIds.length) toast.error(`${feeIds.length - queued} reminder${feeIds.length - queued === 1 ? "" : "s"} could not be queued`);
    setReminding(false);
    if (queued) loadDashboard(true);
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
          <p>Live studio signals, revenue opportunities, and rule-based predictions</p>
        </div>
        <div className="ai-refresh-controls">
          <span>{lastUpdated ? `Updated ${lastUpdated.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })}` : "Waiting for live data"}</span>
          <button className="btn btn-secondary btn-sm" disabled={refreshing} onClick={() => loadDashboard(true)}>
            {refreshing ? "Refreshing..." : "Refresh now"}
          </button>
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
            <div>
              <h2>AI Command Center</h2>
              <p>Choose a live signal to inspect</p>
            </div>
            <span className="ai-local-badge">Free / rule-based</span>
          </div>
          <div className="ai-focus-tabs" role="tablist" aria-label="AI insight focus">
            {[["risk", "Most Risk"], ["profit", "Most Profit"], ["forecast", "Future Forecast"]].map(([key, label]) => (
              <button key={key} role="tab" aria-selected={focus === key} className={focus === key ? "active" : ""} onClick={() => setFocus(key)}>{label}</button>
            ))}
          </div>
          {focus === "risk" && (topRisk ? (
            <article className="ai-featured-insight">
              <span className="ai-insight-icon" aria-hidden="true">{topRisk.revenue_at_risk > 0 ? "!" : "OK"}</span>
              <div><strong>{topRisk.type === "fee_default" ? "Fee default risk" : "Attendance drop risk"}</strong><p>{topRisk.message}</p><b>{rupees(topRisk.revenue_at_risk)} at risk</b></div>
            </article>
          ) : <p>No active risk signals.</p>)}
          {focus === "profit" && (bestBatch ? (
            <article className="ai-featured-insight">
              <span className="ai-insight-icon" aria-hidden="true">#1</span>
              <div><strong>{bestBatch.batch_name}</strong><p>Highest estimated monthly revenue share across active batches.</p><b>{rupees(bestBatch.estimated_profit)} estimate / {bestBatch.attendance_pct}% attendance</b></div>
            </article>
          ) : <p>No active batches are available for profitability estimates.</p>)}
          {focus === "forecast" && (
            <article className="ai-featured-insight">
              <span className="ai-insight-icon" aria-hidden="true">Next</span>
              <div><strong>Next month collection estimate</strong><p>Average of the last three monthly fee collections.</p><b>{rupees(forecast)} predicted</b></div>
            </article>
          )}
          {focus === "risk" && feeRisk?.fee_ids?.length > 0 && (
            <button className="btn btn-primary ai-reminder-button" disabled={reminding} onClick={sendReminders}>
              {reminding ? "Queueing..." : "Send Reminders"}
            </button>
          )}
        </section>

        <section className="card ai-panel ai-forecast-panel">
          <div className="ai-panel-heading">
            <h2>Live Outlook</h2>
            <span className="ai-local-badge">Auto refresh / 30 sec</span>
          </div>
          <div className="ai-forecast-primary">
            <span className={`ai-forecast-arrow ${change?.forecast > 0 ? "up" : change?.forecast < 0 ? "down" : "flat"}`} aria-label="Forecast change since last refresh">
              {change?.forecast > 0 ? "UP" : change?.forecast < 0 ? "DN" : "="}
            </span>
            <div>
              <span className="stat-label">Predicted next month</span>
              <strong>{rupees(forecast)}</strong>
              <small>{deltaLabel(change?.forecast)}</small>
            </div>
          </div>
          <div className="ai-forecast-at-risk">
            <span>Revenue at Risk <small>{deltaLabel(change?.risk)}</small></span>
            <strong>{rupees(riskTotal)}</strong>
          </div>
          <p className="ai-forecast-note">Forecast uses collected fee totals from {insights.forecast?.months_used?.join(", ") || "the latest three billing months"}. Batch profitability is estimated because expenses are not stored.</p>
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
            <BarChart data={[...batchRows].sort((a, b) => Number(b.estimated_profit || 0) - Number(a.estimated_profit || 0))} margin={{ top: 12, right: 16, left: 12, bottom: 45 }}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="batch_name" angle={-18} textAnchor="end" interval={0} height={70} fontSize={11} />
              <YAxis yAxisId="revenue" tickFormatter={(value) => `Rs ${Number(value).toLocaleString("en-IN")}`} fontSize={11} />
              <YAxis yAxisId="attendance" orientation="right" domain={[0, 100]} unit="%" fontSize={11} />
              <Tooltip formatter={(value, name) => name === "Attendance" ? [`${value}%`, name] : [rupees(value), name]} />
              <Legend verticalAlign="top" />
              <Bar yAxisId="revenue" dataKey="estimated_profit" name="Estimated revenue share*" fill="#CC7000" radius={[4, 4, 0, 0]} />
              <Line yAxisId="attendance" dataKey="attendance_pct" name="Attendance" stroke="#2563eb" strokeWidth={2} dot={{ r: 3 }} />
            </BarChart>
          </ResponsiveContainer>
        )}
        <p className="ai-chart-note">*Estimated monthly revenue share allocated by activity; expense data is not stored, so net profit is unavailable.</p>
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
