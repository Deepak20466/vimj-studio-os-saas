import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { useAuth } from "../../context/AuthContext";
import { ReceiptsAPI, CoachSelfAPI, ActivitiesAPI } from "../../api/endpoints";
import Modal from "../../components/Modal";
import StatusBadge from "../../components/StatusBadge";
import { downloadBlob } from "../../utils/download";

export default function CoachReceipts() {
  const { user } = useAuth();
  const [receipts, setReceipts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [students, setStudents] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({
    student_id: "",
    amount: "",
    month: new Date().getMonth() + 1,
    year: new Date().getFullYear(),
    payment_mode: "CASH",
    note: "",
  });

  const load = () => {
    setLoading(true);
    ReceiptsAPI.my()
      .then((r) => setReceipts(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load receipts"))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
    CoachSelfAPI.myActivities(user.id)
      .then((r) => Promise.all(r.data.map((a) => ActivitiesAPI.roster(a.activity_id))))
      .then((results) => {
        const all = results.flatMap((r) => r.data);
        const unique = Object.values(Object.fromEntries(all.map((s) => [s.id, s])));
        setStudents(unique);
      })
      .catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const openCreate = () => {
    setForm({ student_id: "", amount: "", month: new Date().getMonth() + 1, year: new Date().getFullYear(), payment_mode: "CASH", note: "" });
    setShowForm(true);
  };

  const submit = async (e) => {
    e.preventDefault();
    try {
      await ReceiptsAPI.create({
        ...form,
        student_id: Number(form.student_id),
        amount: Number(form.amount),
        month: Number(form.month),
        year: Number(form.year),
      });
      toast.success("Receipt submitted for admin approval");
      setShowForm(false);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to submit receipt");
    }
  };

  const statusFor = (r) => (r.status === "APPROVED" ? "approved" : r.status === "REJECTED" ? "rejected" : "pending");

  const downloadReceipt = async (receipt) => {
    try {
      const res = await ReceiptsAPI.pdf(receipt.id);
      downloadBlob(res.data, `receipt_${receipt.id}.pdf`);
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to download receipt");
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>Fee Receipts</h1>
        <button className="btn btn-primary" onClick={openCreate}>
          + New Receipt
        </button>
      </div>

      <div className="card">
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : receipts.length === 0 ? (
          <div className="empty-state">No receipts submitted yet.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Period</th>
                <th>Amount</th>
                <th>Mode</th>
                <th>Status</th>
                <th>Note</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {receipts.map((r) => (
                <tr key={r.id}>
                  <td>
                    {r.month}/{r.year}
                  </td>
                  <td>₹{r.amount}</td>
                  <td>{r.payment_mode}</td>
                  <td>
                    <StatusBadge status={statusFor(r)} />
                  </td>
                  <td>{r.decision_note || "-"}</td>
                  <td>
                    {r.status === "APPROVED" ? (
                      <button className="btn btn-primary" onClick={() => downloadReceipt(r)}>
                        Receipt (PDF)
                      </button>
                    ) : (
                      "-"
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {showForm && (
        <Modal title="New Fee Receipt" onClose={() => setShowForm(false)}>
          <form onSubmit={submit}>
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
              <label>Payment Mode</label>
              <select value={form.payment_mode} onChange={(e) => setForm({ ...form, payment_mode: e.target.value })}>
                <option value="CASH">Cash</option>
                <option value="UPI">UPI</option>
                <option value="CARD">Card</option>
                <option value="BANK_TRANSFER">Bank Transfer</option>
              </select>
            </div>
            <div className="field">
              <label>Note (optional)</label>
              <textarea rows={2} value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} />
            </div>
            <div className="modal-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>
                Cancel
              </button>
              <button className="btn btn-primary">Submit for Approval</button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
