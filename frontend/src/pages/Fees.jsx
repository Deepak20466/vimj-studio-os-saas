import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { FeesAPI, StudentsAPI } from "../api/endpoints";
import Modal from "../components/Modal";
import StatusBadge from "../components/StatusBadge";

export default function Fees() {
  const [fees, setFees] = useState([]);
  const [students, setStudents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [unpaidOnly, setUnpaidOnly] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState({ student_id: "", month: new Date().getMonth() + 1, year: new Date().getFullYear(), amount: "", due_date: "" });
  const [editForm, setEditForm] = useState({ amount: "", balance_amount: "", due_date: "", status: "UNPAID" });

  const load = () => {
    setLoading(true);
    const request = unpaidOnly ? FeesAPI.unpaid() : FeesAPI.list();
    request
      .then((r) => setFees(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load fees"))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [unpaidOnly]);

  useEffect(() => {
    StudentsAPI.list().then((r) => setStudents(r.data));
  }, []);

  const markPaid = async (fee) => {
    try {
      await FeesAPI.markPaid(fee.id);
      toast.success("Marked as paid");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed");
    }
  };

  const remind = async (fee) => {
    try {
      await FeesAPI.remind(fee.id);
      toast.success("Reminder sent");
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to send reminder");
    }
  };

  const createFee = async (e) => {
    e.preventDefault();
    try {
      await FeesAPI.create({ ...form, student_id: Number(form.student_id), month: Number(form.month), year: Number(form.year) });
      toast.success("Fee record created");
      setShowForm(false);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to create fee");
    }
  };

  const openEdit = (fee) => {
    setEditing(fee);
    setEditForm({ amount: String(fee.amount), balance_amount: String(fee.balance_amount), due_date: fee.due_date, status: fee.status });
  };

  const submitEdit = async (e) => {
    e.preventDefault();
    try {
      await FeesAPI.update(editing.id, { ...editForm, amount: Number(editForm.amount), balance_amount: Number(editForm.balance_amount) });
      toast.success("Fee record updated");
      setEditing(null);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Update failed");
    }
  };

  const regenerateBalance = () => {
    setEditForm((f) => ({ ...f, balance_amount: f.amount }));
  };

  const remove = async (fee) => {
    const name = fee.student_name || `#${fee.student_id}`;
    if (!confirm(`Delete the ${fee.month}/${fee.year} fee record for ${name}?`)) return;
    try {
      await FeesAPI.remove(fee.id);
      toast.success("Fee record deleted");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Delete failed");
    }
  };

  const studentName = (fee) => fee.student_name || students.find((s) => s.id === fee.student_id)?.name || `#${fee.student_id}`;

  return (
    <div>
      <div className="page-header">
        <h1>Fees</h1>
        <button className="btn btn-primary" onClick={() => setShowForm(true)}>
          + Add Fee Record
        </button>
      </div>

      <div className="card">
        <div className="toolbar" style={{ marginBottom: 12 }}>
          <label style={{ display: "flex", alignItems: "center", gap: 6, fontSize: "0.85rem" }}>
            <input type="checkbox" checked={unpaidOnly} onChange={(e) => setUnpaidOnly(e.target.checked)} />
            Show unpaid/overdue only
          </label>
        </div>
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : fees.length === 0 ? (
          <div className="empty-state">{unpaidOnly ? "No outstanding fees. Everyone is paid up." : "No fee records yet."}</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Student</th>
                <th>Period</th>
                <th>Amount</th>
                <th>Balance</th>
                <th>Due Date</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {fees.map((f) => (
                <tr key={f.id}>
                  <td>{studentName(f)}</td>
                  <td>
                    {f.month}/{f.year}
                  </td>
                  <td>₹{f.amount}</td>
                  <td>
                    {Number(f.balance_amount) > 0 ? (
                      <span style={{ color: "var(--danger)", fontWeight: 600 }}>₹{f.balance_amount}</span>
                    ) : (
                      <span style={{ color: "var(--success)" }}>₹0</span>
                    )}
                  </td>
                  <td>{f.due_date}</td>
                  <td>
                    <StatusBadge status={f.status} />
                  </td>
                  <td>
                    {f.status !== "PAID" && (
                      <>
                        <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => remind(f)}>
                          Remind
                        </button>
                        <button className="btn btn-primary" style={{ marginRight: 6 }} onClick={() => markPaid(f)}>
                          Mark Paid
                        </button>
                      </>
                    )}
                    <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => openEdit(f)}>
                      Edit
                    </button>
                    <button className="btn btn-danger" onClick={() => remove(f)}>
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
        <Modal title="Add Fee Record" onClose={() => setShowForm(false)}>
          <form onSubmit={createFee}>
            <div className="field">
              <label>Student</label>
              <select value={form.student_id} onChange={(e) => setForm({ ...form, student_id: e.target.value })} required>
                <option value="">Select student</option>
                {students.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="form-grid">
              <div>
                <label>Month</label>
                <input type="number" min={1} max={12} value={form.month} onChange={(e) => setForm({ ...form, month: e.target.value })} required />
              </div>
              <div>
                <label>Year</label>
                <input type="number" value={form.year} onChange={(e) => setForm({ ...form, year: e.target.value })} required />
              </div>
            </div>
            <div className="field">
              <label>Amount (₹)</label>
              <input type="number" min={0} step="0.01" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} required />
            </div>
            <div className="field">
              <label>Due Date</label>
              <input type="date" value={form.due_date} onChange={(e) => setForm({ ...form, due_date: e.target.value })} required />
            </div>
            <div className="modal-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>
                Cancel
              </button>
              <button className="btn btn-primary">Create</button>
            </div>
          </form>
        </Modal>
      )}

      {editing && (
        <Modal title={`Edit Fee — ${studentName(editing)}`} onClose={() => setEditing(null)}>
          <form onSubmit={submitEdit}>
            <div className="field">
              <label>Amount (₹)</label>
              <input type="number" min={0} step="0.01" value={editForm.amount} onChange={(e) => setEditForm({ ...editForm, amount: e.target.value })} required />
            </div>
            <div className="field">
              <label>Balance Amount (₹)</label>
              <div style={{ display: "flex", gap: 8 }}>
                <input
                  type="number"
                  min={0}
                  step="0.01"
                  value={editForm.balance_amount}
                  onChange={(e) => setEditForm({ ...editForm, balance_amount: e.target.value })}
                  required
                  style={{ flex: 1 }}
                />
                <button type="button" className="btn btn-secondary" onClick={regenerateBalance}>
                  Generate
                </button>
              </div>
              <p style={{ fontSize: "0.78rem", color: "var(--text-muted)", margin: "4px 0 0" }}>
                Outstanding amount still owed. "Generate" resets it to the full fee amount. Setting it to 0 marks the fee as paid.
              </p>
            </div>
            <div className="field">
              <label>Due Date</label>
              <input type="date" value={editForm.due_date} onChange={(e) => setEditForm({ ...editForm, due_date: e.target.value })} required />
            </div>
            <div className="field">
              <label>Status</label>
              <select value={editForm.status} onChange={(e) => setEditForm({ ...editForm, status: e.target.value })}>
                <option value="UNPAID">Unpaid</option>
                <option value="OVERDUE">Overdue</option>
                <option value="PAID">Paid</option>
              </select>
            </div>
            <div className="modal-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setEditing(null)}>
                Cancel
              </button>
              <button className="btn btn-primary">Save</button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
