import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { useAuth } from "../../context/AuthContext";
import { CoachSelfAPI, ActivitiesAPI, StudentsAPI } from "../../api/endpoints";
import Modal from "../../components/Modal";
import SelfieCapture from "../../components/SelfieCapture";

export default function CoachStudents() {
  const { user } = useAuth();
  const [activities, setActivities] = useState([]);
  const [rosterByActivity, setRosterByActivity] = useState({});
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ name: "", email: "", phone: "", phone_secondary: "", password: "", activity_id: "" });
  const [photoFor, setPhotoFor] = useState(null); // student object
  const [editing, setEditing] = useState(null); // student object
  const [editForm, setEditForm] = useState({ name: "", phone: "", phone_secondary: "" });

  const load = () => {
    setLoading(true);
    CoachSelfAPI.myActivities(user.id)
      .then(async (r) => {
        setActivities(r.data);
        const entries = await Promise.all(
          r.data.map((a) => ActivitiesAPI.roster(a.activity_id).then((res) => [a.activity_id, res.data]))
        );
        setRosterByActivity(Object.fromEntries(entries));
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load your students"))
      .finally(() => setLoading(false));
  };

  useEffect(load, []);

  const openCreate = () => {
    setForm({ name: "", email: "", phone: "", phone_secondary: "", password: "", activity_id: activities[0]?.activity_id || "" });
    setShowForm(true);
  };

  const submit = async (e) => {
    e.preventDefault();
    try {
      const payload = { ...form, activity_id: Number(form.activity_id) };
      if (!payload.email) delete payload.email;
      if (!payload.password) delete payload.password;
      await StudentsAPI.create(payload);
      toast.success("Student added");
      setShowForm(false);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to add student");
    }
  };

  const displayEmail = (email) => (email?.endsWith("@no-login.internal") ? "-" : email);

  const feeReminderMessage =
    "Hi this is VIMJ Studio and it is an reminder for fee payment is pending for the sos month and kindly pay as before the deadline of 5th of every month as cash or upi number - 6361174605  to Mahesh Sir.  Thank you";

  const copyFeeReminder = async () => {
    try {
      await navigator.clipboard.writeText(feeReminderMessage);
      toast.success("Message copied — paste it into WhatsApp/SMS");
    } catch {
      toast.error("Couldn't copy automatically — select and copy the text manually");
    }
  };

  const openEdit = (student) => {
    setEditing(student);
    setEditForm({ name: student.name, phone: student.phone || "", phone_secondary: student.phone_secondary || "" });
  };

  const submitEdit = async (e) => {
    e.preventDefault();
    try {
      await StudentsAPI.update(editing.id, editForm);
      toast.success("Student updated");
      setEditing(null);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to update student");
    }
  };

  const removeStudent = async (student) => {
    if (!confirm(`Remove ${student.name}? This deletes their attendance and fee history too.`)) return;
    try {
      await StudentsAPI.remove(student.id);
      toast.success("Student removed");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to remove student");
    }
  };

  const uploadPhoto = async (base64) => {
    try {
      await StudentsAPI.uploadPhoto(photoFor.id, base64);
      toast.success("Photo saved");
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to save photo");
    } finally {
      setPhotoFor(null);
    }
  };

  if (loading) return <div className="empty-state">Loading...</div>;

  return (
    <div>
      <div className="page-header">
        <h1>My Students</h1>
        {activities.length > 0 && (
          <button className="btn btn-primary" onClick={openCreate}>
            + Add Student
          </button>
        )}
      </div>

      {activities.length === 0 ? (
        <div className="empty-state">You aren't assigned to any activity yet — ask an admin to assign one.</div>
      ) : (
        activities.map((a) => (
          <div className="card" key={a.activity_id} style={{ marginBottom: 16 }}>
            <h3 style={{ marginTop: 0 }}>{a.activity_name}</h3>
            {(rosterByActivity[a.activity_id] || []).length === 0 ? (
              <div className="empty-state">No students enrolled yet.</div>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Email</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {rosterByActivity[a.activity_id].map((s) => (
                    <tr key={s.id}>
                      <td>{s.name}</td>
                      <td>{displayEmail(s.email)}</td>
                      <td>
                        <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={copyFeeReminder} title="Copy fee reminder message">
                          Copy
                        </button>
                        <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => setPhotoFor(s)}>
                          Capture Photo
                        </button>
                        <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => openEdit(s)}>
                          Edit
                        </button>
                        <button className="btn btn-danger" onClick={() => removeStudent(s)}>
                          Delete
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        ))
      )}

      {showForm && (
        <Modal title="Add Student" onClose={() => setShowForm(false)}>
          <form onSubmit={submit}>
            <div className="field">
              <label>Activity</label>
              <select value={form.activity_id} onChange={(e) => setForm({ ...form, activity_id: e.target.value })} required>
                {activities.map((a) => (
                  <option key={a.activity_id} value={a.activity_id}>
                    {a.activity_name}
                  </option>
                ))}
              </select>
            </div>
            <div className="field">
              <label>Name</label>
              <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
            </div>
            <div className="field">
              <label>Email (optional — students don't log in)</label>
              <input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
            </div>
            <div className="form-grid">
              <div>
                <label>Primary Phone</label>
                <input value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} required />
              </div>
              <div>
                <label>Emergency Contact</label>
                <input value={form.phone_secondary} onChange={(e) => setForm({ ...form, phone_secondary: e.target.value })} required />
              </div>
            </div>
            <div className="field">
              <label>Password (optional — students don't log in)</label>
              <input type="password" minLength={8} value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
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

      {photoFor && (
        <SelfieCapture title={`Photo — ${photoFor.name}`} onClose={() => setPhotoFor(null)} onCapture={uploadPhoto} />
      )}

      {editing && (
        <Modal title={`Edit Student — ${editing.name}`} onClose={() => setEditing(null)}>
          <form onSubmit={submitEdit}>
            <div className="field">
              <label>Name</label>
              <input value={editForm.name} onChange={(e) => setEditForm({ ...editForm, name: e.target.value })} required />
            </div>
            <div className="form-grid">
              <div>
                <label>Primary Phone</label>
                <input value={editForm.phone} onChange={(e) => setEditForm({ ...editForm, phone: e.target.value })} required />
              </div>
              <div>
                <label>Emergency Contact</label>
                <input
                  value={editForm.phone_secondary}
                  onChange={(e) => setEditForm({ ...editForm, phone_secondary: e.target.value })}
                  required
                />
              </div>
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
