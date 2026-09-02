import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { FeesAPI, StudentsAPI } from "../api/endpoints";
import Modal from "../components/Modal";
import StatusBadge from "../components/StatusBadge";

export default function Fees() {
  const [fees, setFees] = useState([]);
  const [students, setStudents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ student_id: "", month: new Date().getMonth() + 1, year: new Date().getFullYear(), amount: "", due_date: "" });

  const load = () => {
    setLoading(true);
    FeesAPI.unpaid()
      .then((r) => setFees(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load fees"))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
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

  const studentName = (id) => students.find((s) => s.id === id)?.name || `#${id}`;

  return (
    <div>
      <div className="page-header">
        <h1>Fees</h1>
        <button className="btn btn-primary" onClick={() => setShowForm(true)}>
          + Add Fee Record
        </button>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Unpaid / Overdue Fees</h3>
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : fees.length === 0 ? (
          <div className="empty-state">No outstanding fees. Everyone is paid up.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Student</th>
                <th>Period</th>
                <th>Amount</th>
                <th>Due Date</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {fees.map((f) => (
                <tr key={f.id}>
                  <td>{studentName(f.student_id)}</td>
                  <td>
                    {f.month}/{f.year}
                  </td>
                  <td>₹{f.amount}</td>
                  <td>{f.due_date}</td>
                  <td>
                    <StatusBadge status={f.status} />
                  </td>
                  <td>
                    <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => remind(f)}>
                      Send Reminder
                    </button>
                    <button className="btn btn-primary" onClick={() => markPaid(f)}>
                      Mark Paid
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
    </div>
  );
}
