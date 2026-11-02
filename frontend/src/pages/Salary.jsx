import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { SalaryAPI, CoachesAPI } from "../api/endpoints";
import Modal from "../components/Modal";
import StatusBadge from "../components/StatusBadge";
import { blobErrorDetail, downloadBlob } from "../utils/download";

const MONTH_NAMES = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

export default function Salary() {
  const [salaries, setSalaries] = useState([]);
  const [coaches, setCoaches] = useState([]);
  const [coachesLoading, setCoachesLoading] = useState(true);
  const [coachLoadError, setCoachLoadError] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState(null);
  const [exporting, setExporting] = useState("");
  const [form, setForm] = useState({ coach_id: "", month: new Date().getMonth() + 1, year: new Date().getFullYear(), amount: "" });

  const load = () => {
    setLoading(true);
    SalaryAPI.list()
      .then((r) => setSalaries(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load salary records"))
      .finally(() => setLoading(false));
  };

  const loadCoaches = async () => {
    setCoachesLoading(true);
    setCoachLoadError("");
    try {
      const { data } = await CoachesAPI.list();
      setCoaches(data);
      if (!data.length) setCoachLoadError("Add an active coach before recording salary.");
    } catch (err) {
      setCoachLoadError(err.response?.data?.detail || "Could not load coaches. Retry before creating salary.");
    } finally {
      setCoachesLoading(false);
    }
  };

  useEffect(() => {
    load();
    loadCoaches();
  }, []);

  const openCreate = () => {
    setEditing(null);
    setForm({ coach_id: "", month: new Date().getMonth() + 1, year: new Date().getFullYear(), amount: "" });
    setShowForm(true);
  };

  const openEdit = (s) => {
    setEditing(s);
    setForm({ coach_id: s.coach_id, month: s.month, year: s.year, amount: s.amount });
    setShowForm(true);
  };

  const submit = async (e) => {
    e.preventDefault();
    setSaving(true);
    try {
      if (editing) {
        await SalaryAPI.update(editing.id, { month: Number(form.month), year: Number(form.year), amount: Number(form.amount) });
        toast.success("Salary record updated");
      } else {
        await SalaryAPI.create({ ...form, coach_id: Number(form.coach_id), month: Number(form.month), year: Number(form.year) });
        toast.success("Salary record created");
      }
      setShowForm(false);
      setEditing(null);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || `Failed to ${editing ? "update" : "create"} salary record`);
    } finally {
      setSaving(false);
    }
  };

  const remove = async (s) => {
    if (!window.confirm(`Delete the ${MONTH_NAMES[s.month]} ${s.year} salary record for ${s.coach_name}? This cannot be undone.`)) return;
    try {
      await SalaryAPI.remove(s.id);
      toast.success("Salary record deleted");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to delete salary record");
    }
  };

  const exportSalary = async (fmt) => {
    setExporting(fmt);
    try {
      const { data } = await SalaryAPI.export(fmt);
      const extension = fmt === "csv" ? "csv" : "pdf";
      downloadBlob(data, `salary_records.${extension}`, fmt === "csv" ? "text/csv" : "application/pdf");
      toast.success(`Salary ${extension.toUpperCase()} downloaded`);
    } catch (err) {
      toast.error((await blobErrorDetail(err)) || `Salary ${fmt.toUpperCase()} download failed`);
    } finally {
      setExporting("");
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>Coach Salary</h1>
        <div className="toolbar">
          <button className="btn btn-secondary" disabled={loading || salaries.length === 0 || !!exporting} onClick={() => exportSalary("pdf")}>
            {exporting === "pdf" ? "Preparing PDF..." : "Download PDF"}
          </button>
          <button className="btn btn-secondary" disabled={loading || salaries.length === 0 || !!exporting} onClick={() => exportSalary("csv")}>
            {exporting === "csv" ? "Preparing CSV..." : "Download CSV"}
          </button>
        </div>
        <button className="btn btn-primary" onClick={openCreate}>
          + Record Salary
        </button>
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
                <th>Coach</th>
                <th>Period</th>
                <th>Amount</th>
                <th>Notified</th>
                <th>Acknowledgement</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {salaries.map((s) => (
                <tr key={s.id}>
                  <td>{s.coach_name}</td>
                  <td>
                    {MONTH_NAMES[s.month]} {s.year}
                  </td>
                  <td>Rs {Number(s.amount).toLocaleString("en-IN", { minimumFractionDigits: 2 })}</td>
                  <td>{s.notified_at ? new Date(s.notified_at).toLocaleDateString() : "-"}</td>
                  <td>
                    {s.acknowledged_date ? (
                      <StatusBadge status="approved" />
                    ) : (
                      <StatusBadge status="pending" />
                    )}
                  </td>
                  <td>
                    <button
                      className="btn btn-secondary btn-sm"
                      disabled={!!s.acknowledged_date}
                      title={s.acknowledged_date ? "Already acknowledged by coach" : "Edit"}
                      onClick={() => openEdit(s)}
                    >
                      Edit
                    </button>{" "}
                    <button
                      className="btn btn-danger btn-sm"
                      disabled={!!s.acknowledged_date}
                      title={s.acknowledged_date ? "Already acknowledged by coach" : "Delete"}
                      onClick={() => remove(s)}
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {showForm && (
        <Modal
          title={editing ? "Edit Salary Record" : "Record Monthly Salary"}
          onClose={() => {
            setShowForm(false);
            setEditing(null);
          }}
        >
          <form onSubmit={submit}>
            <div className="field">
              <label>Coach</label>
              <select value={form.coach_id} onChange={(e) => setForm({ ...form, coach_id: e.target.value })} disabled={!!editing || coachesLoading || !!coachLoadError} required>
                <option value="">Select coach</option>
                {coaches.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
              {coachLoadError && <div role="alert" className="form-error">{coachLoadError} <button type="button" className="btn btn-secondary btn-sm" onClick={loadCoaches} disabled={coachesLoading}>Retry</button></div>}
            </div>
            <div className="form-grid">
              <div>
                <label>Month</label>
                <input type="number" min={1} max={12} value={form.month} onChange={(e) => setForm({ ...form, month: e.target.value })} required />
              </div>
              <div>
                <label>Year</label>
                <input type="number" min={2000} max={2200} value={form.year} onChange={(e) => setForm({ ...form, year: e.target.value })} required />
              </div>
            </div>
            <div className="field">
              <label>Amount (?)</label>
              <input type="number" min={0.01} step="0.01" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} required />
            </div>
            <div className="modal-actions">
              <button
                type="button"
                className="btn btn-secondary"
                onClick={() => {
                  setShowForm(false);
                  setEditing(null);
                }}
              >
                Cancel
              </button>
              <button className="btn btn-primary" disabled={saving || (!editing && (coachesLoading || coaches.length === 0))}>{saving ? "Saving..." : editing ? "Save" : "Create"}</button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
