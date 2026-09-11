import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { FeesAPI, StudentsAPI, ReceiptsAPI, FeeRemindersAPI } from "../api/endpoints";
import Modal from "../components/Modal";
import StatusBadge from "../components/StatusBadge";
import { downloadBlob, blobErrorDetail } from "../utils/download";

export default function Fees() {
  const [fees, setFees] = useState([]);
  const [students, setStudents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [unpaidOnly, setUnpaidOnly] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState({ student_id: "", month: new Date().getMonth() + 1, year: new Date().getFullYear(), amount: "", due_date: "" });
  const [editForm, setEditForm] = useState({ amount: "", balance_amount: "", due_date: "", status: "UNPAID" });

  const [receipts, setReceipts] = useState([]);
  const [approvedReceipts, setApprovedReceipts] = useState([]);
  const [receiptsLoading, setReceiptsLoading] = useState(true);
  const [receiptBusyId, setReceiptBusyId] = useState(null);

  const loadReceipts = () => {
    setReceiptsLoading(true);
    Promise.all([ReceiptsAPI.pending(), ReceiptsAPI.list()])
      .then(([pendingRes, allRes]) => {
        setReceipts(pendingRes.data);
        setApprovedReceipts(allRes.data.filter((r) => r.status === "APPROVED"));
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load receipts"))
      .finally(() => setReceiptsLoading(false));
  };

  useEffect(loadReceipts, []);

  const downloadReceiptPdf = async (receipt) => {
    try {
      const res = await ReceiptsAPI.pdf(receipt.id);
      downloadBlob(res.data, `receipt_${receipt.id}.pdf`);
    } catch (err) {
      toast.error((await blobErrorDetail(err)) || "Failed to download receipt");
      if (err.response?.status === 404) loadReceipts();
    }
  };

  const [reminderDrafts, setReminderDrafts] = useState([]);
  const [remindersLoading, setRemindersLoading] = useState(true);
  const [reminderBusyId, setReminderBusyId] = useState(null);

  const loadReminderDrafts = () => {
    setRemindersLoading(true);
    FeeRemindersAPI.pending()
      .then((r) => setReminderDrafts(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load pending fee reminders"))
      .finally(() => setRemindersLoading(false));
  };

  useEffect(loadReminderDrafts, []);

  const decideReminder = async (draft, approve) => {
    setReminderBusyId(draft.id);
    try {
      if (approve) {
        await FeeRemindersAPI.approve(draft.id);
        toast.success("Reminder approved and sent to the student");
      } else {
        const note = prompt("Reason for rejecting (optional):") || "";
        await FeeRemindersAPI.reject(draft.id, note);
        toast.success("Reminder rejected");
      }
      loadReminderDrafts();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Action failed");
    } finally {
      setReminderBusyId(null);
    }
  };

  const copyMessage = async (message) => {
    try {
      await navigator.clipboard.writeText(message);
      toast.success("Message copied — paste it into WhatsApp");
    } catch {
      toast.error("Couldn't copy automatically — select and copy the text manually");
    }
  };

  const decideReceipt = async (receipt, approve) => {
    setReceiptBusyId(receipt.id);
    try {
      if (approve) {
        await ReceiptsAPI.approve(receipt.id);
        toast.success("Receipt approved — fee marked paid");
      } else {
        const note = prompt("Reason for rejecting (optional):") || "";
        await ReceiptsAPI.reject(receipt.id, note);
        toast.success("Receipt rejected");
      }
      loadReceipts();
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Action failed");
    } finally {
      setReceiptBusyId(null);
    }
  };

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

  const downloadReceipt = async (fee) => {
    try {
      const res = await FeesAPI.receiptPdf(fee.id);
      downloadBlob(res.data, `receipt_${fee.id}.pdf`);
    } catch (err) {
      toast.error((await blobErrorDetail(err)) || "Failed to download receipt");
      if (err.response?.status === 404) load();
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

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Pending Fee Receipts (from Coaches)</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -8 }}>
          A coach recorded a fee as collected — approve to mark it paid and notify the student, or reject with a reason.
        </p>
        {receiptsLoading ? (
          <div className="empty-state">Loading...</div>
        ) : receipts.length === 0 ? (
          <div className="empty-state">No receipts awaiting approval.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Student</th>
                <th>Coach</th>
                <th>Period</th>
                <th>Amount</th>
                <th>Mode</th>
                <th>Note</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {receipts.map((r) => (
                <tr key={r.id}>
                  <td>{r.student_name}</td>
                  <td>{r.coach_name}</td>
                  <td>
                    {r.month}/{r.year}
                  </td>
                  <td>₹{r.amount}</td>
                  <td>{r.payment_mode}</td>
                  <td>{r.note || "-"}</td>
                  <td className="table-actions">
                    <button className="btn btn-primary btn-sm" disabled={receiptBusyId === r.id} onClick={() => decideReceipt(r, true)}>
                      Approve
                    </button>
                    <button className="btn btn-danger btn-sm" disabled={receiptBusyId === r.id} onClick={() => decideReceipt(r, false)}>
                      Reject
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Approved Fee Receipts</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -8 }}>
          Download the PDF receipt once a coach's fee collection has been approved. Share it with the student
          manually (WhatsApp, email, or print).
        </p>
        {receiptsLoading ? (
          <div className="empty-state">Loading...</div>
        ) : approvedReceipts.length === 0 ? (
          <div className="empty-state">No approved receipts yet.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Student</th>
                <th>Coach</th>
                <th>Period</th>
                <th>Amount</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {approvedReceipts.map((r) => (
                <tr key={r.id}>
                  <td>{r.student_name}</td>
                  <td>{r.coach_name}</td>
                  <td>
                    {r.month}/{r.year}
                  </td>
                  <td>₹{r.amount}</td>
                  <td className="table-actions">
                    <button className="btn btn-primary btn-sm" onClick={() => downloadReceiptPdf(r)}>
                      Receipt (PDF)
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Pending Fee Reminder Drafts (from Coaches)</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -8 }}>
          A coach drafted a fee reminder message — approve to send it automatically, or reject with a reason. Once
          approved, the text can also be copied to paste into WhatsApp manually.
        </p>
        {remindersLoading ? (
          <div className="empty-state">Loading...</div>
        ) : reminderDrafts.length === 0 ? (
          <div className="empty-state">No fee reminders awaiting approval.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Student</th>
                <th>Coach</th>
                <th>Period</th>
                <th>Message</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {reminderDrafts.map((d) => (
                <tr key={d.id}>
                  <td>{d.student_name}</td>
                  <td>{d.coach_name}</td>
                  <td>
                    {d.month}/{d.year}
                  </td>
                  <td style={{ maxWidth: 320, whiteSpace: "pre-wrap", fontSize: "0.8rem" }}>{d.message}</td>
                  <td className="table-actions">
                    <button className="btn btn-secondary btn-sm" onClick={() => copyMessage(d.message)}>
                      Copy
                    </button>
                    <button className="btn btn-primary btn-sm" disabled={reminderBusyId === d.id} onClick={() => decideReminder(d, true)}>
                      Approve &amp; Send
                    </button>
                    <button className="btn btn-danger btn-sm" disabled={reminderBusyId === d.id} onClick={() => decideReminder(d, false)}>
                      Reject
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
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
                  <td className="table-actions">
                    {f.status !== "PAID" ? (
                      <>
                        <button className="btn btn-secondary btn-sm" onClick={() => remind(f)}>
                          Remind
                        </button>
                        <button className="btn btn-primary btn-sm" onClick={() => markPaid(f)}>
                          Mark Paid
                        </button>
                      </>
                    ) : (
                      <button className="btn btn-primary btn-sm" onClick={() => downloadReceipt(f)}>
                        Receipt (PDF)
                      </button>
                    )}
                    <button className="btn btn-secondary btn-sm" onClick={() => openEdit(f)}>
                      Edit
                    </button>
                    <button className="btn btn-danger btn-sm" onClick={() => remove(f)}>
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
