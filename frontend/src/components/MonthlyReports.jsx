import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { ReportsAPI } from "../api/endpoints";
import { downloadBlob, blobErrorDetail } from "../utils/download";
export default function MonthlyReports() {
  const now = new Date();
  const [period, setPeriod] = useState(`${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [year, month] = period.split("-").map(Number);
  useEffect(() => {
    if (!month || !year) return;
    let active = true;
    setData(null); setLoading(true);
    ReportsAPI.summary({ month, year }).then(r => { if (active) setData(r.data); }).catch(() => { if (active) toast.error("Failed to load reports"); }).finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [month, year]);
  const pdf = async kind => {
    try { const r = await ReportsAPI.pdf({ month, year, kind }); downloadBlob(r.data, `${kind}_${period}.pdf`, "application/pdf"); }
    catch (err) { toast.error((await blobErrorDetail(err)) || "Report download failed"); }
  };
  return <div className="card"><h2>Monthly Reports &amp; Overall Revenue</h2>
    <div className="toolbar"><input aria-label="Report month" type="month" value={period} onChange={e => setPeriod(e.target.value)} />
    <button className="btn btn-secondary" onClick={() => { const d = new Date(year, month - 2, 1); setPeriod(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`); }} disabled={!period}>Previous Month</button>
    {[['students', 'Student Attendance PDF'], ['attendance', 'Activity Attendance PDF'], ['revenue', 'Activity & Overall Revenue PDF']].map(([kind, label]) => <button key={kind} className="btn btn-primary" disabled={!data || loading} onClick={() => pdf(kind)}>{label}</button>)}</div>
    {loading && <p>Loading reports...</p>}
    {data && <><p><strong>Overall revenue: Rs {Number(data.total_revenue).toFixed(2)}</strong> (includes products: Rs {Number(data.product_revenue).toFixed(2)})</p><p>{data.revenue_basis}</p>
    <table><thead><tr><th>Activity</th><th>Present</th><th>Absent</th><th>Leave</th><th>Not Confirm</th><th>Revenue</th></tr></thead><tbody>{data.activities.map(a => <tr key={a.activity}><td>{a.activity}</td><td>{a.present}</td><td>{a.absent}</td><td>{a.leave}</td><td>{a.not_confirm}</td><td>Rs {Number(a.revenue).toFixed(2)}</td></tr>)}<tr><td>Unassigned revenue</td><td colSpan={5}>Rs {Number(data.unassigned_revenue).toFixed(2)}</td></tr></tbody></table></>}
  </div>;
}
