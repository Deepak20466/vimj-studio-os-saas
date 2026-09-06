import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { useAuth } from "../../context/AuthContext";
import { FeeRemindersAPI, CoachSelfAPI, ActivitiesAPI } from "../../api/endpoints";
import Modal from "../../components/Modal";
import StatusBadge from "../../components/StatusBadge";

export default function CoachFeeReminders() {
  const { user } = useAuth();
  const [drafts, setDrafts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [students, setStudents] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ student_id: "", month: new Date().getMonth() + 1, year: new Date().getFullYear(), message: "" });

  const load = () => {
    setLoading(true);
    FeeRemindersAPI.my()
      .then((r) => setDrafts(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load fee reminders"))
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
    setForm({ student_id: "", month: new Date().getMonth() + 1, year: new Date().getFullYear(), message: "" });
    setShowForm(true);
  };

  const submit = async (e) => {
    e.preventDefault();
    try {
      await FeeRemindersAPI.create({
        student_id: Number(form.student_id),
        month: Number(form.month),
        year: Number(form.year),
        message: form.message || undefined,
      });
      toast.success("Fee reminder submitted for admin approval");
      setShowForm(false);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to submit fee reminder");
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

  const statusFor = (d) => (d.status === "APPROVED" ? "approved" : d.status === "REJECTED" ? "rejected" : "pending");

  return (
    <div>
      <div className="page-header">
        <h1>Fee Reminders</h1>
        <button className="btn btn-primary" onClick={openCreate}>
          + New Reminder
        </button>
      </div>

      <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -8 }}>
        Draft a fee reminder for a student. Once admin approves it, it's sent automatically and you can also copy the
        text to paste into WhatsApp yourself.
      </p>

      <div className="card">
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : drafts.length === 0 ? (
          <div className="empty-state">No fee reminders drafted yet.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Period</th>
                <th>Message</th>
                <th>Status</th>
                <th>Note</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {drafts.map((d) => (
                <tr key={d.id}>
                  <td>
                    {d.month}/{d.year}
                  </td>
                  <td style={{ maxWidth: 320, whiteSpace: "pre-wrap", fontSize: "0.8rem" }}>{d.message}</td>
                  <td>
                    <StatusBadge status={statusFor(d)} />
                  </td>
                  <td>{d.decision_note || "-"}</td>
                  <td>
                    {d.status === "APPROVED" && (
                      <button className="btn btn-secondary" onClick={() => copyMessage(d.message)}>
                        Copy
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {showForm && (
        <Modal title="New Fee Reminder" onClose={() => setShowForm(false)}>
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
              <label>Custom Message (optional)</label>
              <textarea
                rows={4}
                value={form.message}
                onChange={(e) => setForm({ ...form, message: e.target.value })}
                placeholder="Leave blank to auto-generate from the student's fee record for this period."
              />
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
