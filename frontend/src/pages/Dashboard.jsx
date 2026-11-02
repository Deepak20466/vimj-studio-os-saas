import { useCallback, useEffect, useRef, useState } from "react";
import { AttendanceAPI, DashboardAPI, FeesAPI } from "../api/endpoints";
import toast from "react-hot-toast";
import useResizeAfterLoad from "../hooks/useResizeAfterLoad";
import { dismissItem, filterDismissed } from "../utils/dismissedItems";
import "./admin-dashboard.css";

const rupees = (value) => `Rs ${Number(value || 0).toLocaleString("en-IN", { maximumFractionDigits: 0 })}`;
const AI_LIST_PREVIEW = 5;

export default function Dashboard() {
  const [insights, setInsights] = useState(null);
  const [missing, setMissing] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadFailed, setLoadFailed] = useState(false);
  const [reminding, setReminding] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [focus, setFocus] = useState("risk");
  const [showAllInsights, setShowAllInsights] = useState(false);
  const [showAllBatches, setShowAllBatches] = useState(false);
  const [insightFilter, setInsightFilter] = useState("");
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
  const filterText = insightFilter.trim().toLocaleLowerCase();
  const riskRows = [
    ...(feeRisk?.students || []).map((student) => ({
      key: `student-${student.student_id}`,
      label: student.student_name,
      detail: `${student.fees?.length || student.fee_ids?.length || 0} overdue fee record(s)`,
      amount: Number(student.pending_amount || 0),
      type: "Fee default",
    })),
    ...(insights.risks || []).filter((risk) => risk.type === "attendance_drop")
      .flatMap((risk) => (risk.batches || []).map((batch) => ({
        key: `batch-risk-${batch.batch_id}`,
        label: batch.batch_name,
        detail: `Attendance down ${Number(batch.attendance_drop_pct || 0).toFixed(1)}%${batch.attendance_drop_weekdays?.length ? ` on ${batch.attendance_drop_weekdays.join(", ")}` : ""}`,
        amount: Number(batch.revenue_at_risk || 0),
        type: "Attendance drop",
      }))),
  ].sort((a, b) => b.amount - a.amount).filter((row) => `${row.label} ${row.detail} ${row.type}`.toLocaleLowerCase().includes(filterText));
  const profitRows = [...batchRows].sort((a, b) => Number(b.estimated_profit || 0) - Number(a.estimated_profit || 0))
    .filter((row) => (row.batch_name || "").toLocaleLowerCase().includes(filterText));
  const forecastRows = [...(insights.forecast?.monthly_collections || [])]
    .sort((a, b) => String(a.month || "").localeCompare(String(b.month || "")))
    .filter((row) => String(row.month || "").toLocaleLowerCase().includes(filterText));
  const visibleRows = (rows) => showAllInsights ? rows : rows.slice(0, AI_LIST_PREVIEW);
  const chartBatches = showAllBatches ? profitRows : profitRows.slice(0, AI_LIST_PREVIEW);
  const maxBatchEstimate = Math.max(1, ...chartBatches.map((row) => Number(row.estimated_profit || 0)));
  const actualMonths = [...(insights.forecast?.monthly_collections || [])]
    .sort((a, b) => String(a.month || "").localeCompare(String(b.month || "")));
  const forecastChartMax = Math.max(1, Number(forecast || 0), ...actualMonths.map((row) => Number(row.collected || 0)));
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
            {[["risk", "Most Risk"], ["profit", "Top Revenue"], ["forecast", "Future Forecast"]].map(([key, label]) => (
              <button key={key} role="tab" aria-selected={focus === key} className={focus === key ? "active" : ""} onClick={() => { setFocus(key); setShowAllInsights(false); }}>{label}</button>
            ))}
          </div>
          <input className="ai-list-filter" aria-label="Filter AI insights" placeholder="Filter this list..." value={insightFilter} onChange={(event) => setInsightFilter(event.target.value)} />
          {focus === "risk" && (riskRows.length ? (
            <div className="ai-ranked-list" aria-label="Revenue risks sorted highest to lowest">
              {visibleRows(riskRows).map((row, index) => <article className="ai-ranked-row" key={row.key}>
                <span className="ai-rank">{index + 1}</span><div className="ai-ranked-copy"><strong>{row.label}</strong><small>{row.type} · {row.detail}</small></div><b>{rupees(row.amount)}</b>
              </article>)}
              {riskRows.length > AI_LIST_PREVIEW && <button className="ai-view-toggle" onClick={() => setShowAllInsights((value) => !value)}>{showAllInsights ? "View less" : `View all ${riskRows.length} risks`}</button>}
            </div>
          ) : <p>No matching active risks.</p>)}
          {focus === "profit" && (profitRows.length ? (
            <div className="ai-ranked-list" aria-label="Batches sorted by estimated monthly revenue">
              {visibleRows(profitRows).map((row, index) => <article className="ai-ranked-row" key={row.batch_id}>
                <span className="ai-rank">{index + 1}</span><div className="ai-ranked-copy"><strong>{row.batch_name}</strong><small>{Number(row.attendance_pct || 0).toFixed(1)}% recent attendance</small></div><b>{rupees(row.estimated_profit)}</b>
              </article>)}
              {profitRows.length > AI_LIST_PREVIEW && <button className="ai-view-toggle" onClick={() => setShowAllInsights((value) => !value)}>{showAllInsights ? "View less" : `View all ${profitRows.length} batches`}</button>}
            </div>
          ) : <p>No matching active batches.</p>)}
          {focus === "forecast" && (
            <>
              <article className="ai-featured-insight"><span className="ai-insight-icon" aria-hidden="true">Next</span><div><strong>Next month collection estimate</strong><p>Average of the last three monthly fee collections.</p><b>{rupees(forecast)} predicted</b></div></article>
              {forecastRows.length ? <div className="ai-ranked-list" aria-label="Monthly collections in date order">
                {visibleRows(forecastRows).map((row, index) => <article className="ai-ranked-row" key={row.month}>
                  <span className="ai-rank">{index + 1}</span><div className="ai-ranked-copy"><strong>{row.month}</strong><small>Collected fees</small></div><b>{rupees(row.collected)}</b>
                </article>)}
                {forecastRows.length > AI_LIST_PREVIEW && <button className="ai-view-toggle" onClick={() => setShowAllInsights((value) => !value)}>{showAllInsights ? "View less" : `View all ${forecastRows.length} months`}</button>}
              </div> : <p>Monthly collection history is not available for this account.</p>}
            </>
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
          <div className="ai-forecast-visual" role="img" aria-label="Last three monthly collections compared with the next month estimate">
            <div className="ai-forecast-bars">
              {actualMonths.map((row) => <div className="ai-forecast-bar-column" key={row.month}>
                <span>{rupees(row.collected)}</span>
                <div className="ai-forecast-bar-track"><i style={{ height: `${Math.max(5, Number(row.collected || 0) / forecastChartMax * 100)}%` }} /></div>
                <small>{row.month}</small>
              </div>)}
              <div className="ai-forecast-bar-column predicted">
                <span>{rupees(forecast)}</span>
                <div className="ai-forecast-bar-track"><i style={{ height: `${Math.max(5, Number(forecast || 0) / forecastChartMax * 100)}%` }} /></div>
                <small>Next month</small>
              </div>
            </div>
            <p>How to read it: the next month estimate is the average of these three months.</p>
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
            <h2>Batch Revenue vs Attendance</h2>
            <p>Estimated revenue ranked against recent attendance</p>
          </div>
        </div>
        {batchRows.length === 0 ? (
          <div className="empty-state">No active batches are available for comparison.</div>
        ) : (
          <div className="ai-batch-list">
            {chartBatches.map((row, index) => <article className="ai-batch-row" key={row.batch_id}>
              <div className="ai-batch-row-heading"><span className="ai-rank">{index + 1}</span><strong>{row.batch_name}</strong><b>{rupees(row.estimated_profit)}</b></div>
              <div className="ai-batch-revenue-track" aria-label={`Estimated revenue share ${rupees(row.estimated_profit)}`}><i style={{ width: `${Math.max(0, Number(row.estimated_profit || 0) / maxBatchEstimate * 100)}%` }} /></div>
              <div className="ai-batch-attendance"><span>Recent attendance</span><b>{Number(row.attendance_pct || 0).toFixed(0)}%</b></div>
            </article>)}
            {profitRows.length > AI_LIST_PREVIEW && <button className="ai-view-toggle" onClick={() => setShowAllBatches((value) => !value)}>{showAllBatches ? "View less" : `View all ${profitRows.length} batches`}</button>}
          </div>
        )}
        <p className="ai-chart-note">Revenue is estimated from enrolled students and activity fees. Expense data is not stored, so this is not net profit.</p>
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
