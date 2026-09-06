import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { StudentsAPI, ReportsAPI } from "../api/endpoints";
import Modal from "../components/Modal";
import StudentReportPanel from "../components/StudentReportPanel";
import SelfieCapture from "../components/SelfieCapture";

export default function Students() {
  const [students, setStudents] = useState([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState(null);
  const [viewingId, setViewingId] = useState(null);
  const [form, setForm] = useState({ name: "", email: "", phone: "", phone_secondary: "", password: "", additional_details: "" });
  const [profileFor, setProfileFor] = useState(null); // student object whose profile modal is open
  const [photoUrl, setPhotoUrl] = useState(null);
  const [photoLoading, setPhotoLoading] = useState(false);
  const [uploadFor, setUploadFor] = useState(null); // student object awaiting a new photo capture

  const load = () => {
    setLoading(true);
    StudentsAPI.list(search)
      .then((r) => setStudents(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load students"))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    const t = setTimeout(load, 250);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search]);

  const openCreate = () => {
    setEditing(null);
    setForm({ name: "", email: "", phone: "", phone_secondary: "", password: "", additional_details: "" });
    setShowForm(true);
  };

  const openEdit = (s) => {
    setEditing(s);
    setForm({ name: s.name, email: s.email, phone: s.phone || "", phone_secondary: s.phone_secondary || "", password: "", additional_details: "" });
    setShowForm(true);
  };

  const submit = async (e) => {
    e.preventDefault();
    try {
      if (editing) {
        const payload = { name: form.name, phone: form.phone, phone_secondary: form.phone_secondary };
        if (form.password) payload.password = form.password;
        await StudentsAPI.update(editing.id, payload);
        toast.success("Student updated");
      } else {
        const payload = { ...form };
        if (!payload.email) delete payload.email;
        if (!payload.password) delete payload.password;
        await StudentsAPI.create(payload);
        toast.success("Student created");
      }
      setShowForm(false);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Save failed");
    }
  };

  const toggleActive = async (s) => {
    try {
      await StudentsAPI.update(s.id, { is_active: !s.is_active });
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Update failed");
    }
  };

  const remove = async (s) => {
    if (!confirm(`Remove ${s.name}? This cannot be undone.`)) return;
    try {
      await StudentsAPI.remove(s.id);
      toast.success("Student removed");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Delete failed");
    }
  };

  const displayEmail = (email) => (email?.endsWith("@no-login.internal") ? "-" : email);

  const feeReminderMessage = () =>
    "Hi, this is VIMJ Academy.\n\n" +
    "This is a reminder that your fees are due by the 5th of this month.\n" +
    "Kindly pay as soon as possible via Cash or UPI Payment to 6361174605.\n\n" +
    "Thank you!";

  const copyFeeReminder = async (s) => {
    const message = feeReminderMessage();
    try {
      await navigator.clipboard.writeText(message);
      toast.success(`Fee reminder copied for ${s.name}`);
    } catch {
      toast.error("Failed to copy to clipboard");
    }
  };

  const openProfile = async (s) => {
    setProfileFor(s);
    setPhotoLoading(true);
    setPhotoUrl(null);
    try {
      const { data } = await StudentsAPI.photoBlob(s.id);
      setPhotoUrl(URL.createObjectURL(data));
    } catch {
      setPhotoUrl(null);
    } finally {
      setPhotoLoading(false);
    }
  };

  const uploadPhoto = async (base64) => {
    try {
      await StudentsAPI.uploadPhoto(uploadFor.id, base64);
      toast.success("Photo saved");
      if (profileFor && profileFor.id === uploadFor.id) openProfile(uploadFor);
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to save photo");
    } finally {
      setUploadFor(null);
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>Students</h1>
        <button className="btn btn-primary" onClick={openCreate}>
          + Add Student
        </button>
      </div>

      <div className="toolbar">
        <input placeholder="Search by name or email..." value={search} onChange={(e) => setSearch(e.target.value)} style={{ maxWidth: 320 }} />
      </div>

      <div className="card">
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : students.length === 0 ? (
          <div className="empty-state">No students found.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Name</th>
                <th>Email</th>
                <th>Phone</th>
                <th>Emergency Contact</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {students.map((s) => (
                <tr key={s.id}>
                  <td>
                    <button className="link-btn" onClick={() => setViewingId(s.id)}>
                      {s.name}
                    </button>
                  </td>
                  <td>{displayEmail(s.email)}</td>
                  <td>{s.phone || "-"}</td>
                  <td>{s.phone_secondary || "-"}</td>
                  <td>
                    <span className={`badge ${s.is_active ? "badge-present" : "badge-absent"}`}>{s.is_active ? "Active" : "Inactive"}</span>
                  </td>
                  <td>
                    <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => openProfile(s)}>
                      Profile
                    </button>
                    <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => openEdit(s)}>
                      Edit
                    </button>
                    <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => toggleActive(s)}>
                      {s.is_active ? "Deactivate" : "Activate"}
                    </button>
                    <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => copyFeeReminder(s)} title="Copy fee reminder message">
                      Copy Fee Reminder
                    </button>
                    <button className="btn btn-danger" onClick={() => remove(s)}>
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
        <Modal title={editing ? "Edit Student" : "Add Student"} onClose={() => setShowForm(false)}>
          <form onSubmit={submit}>
            <div className="field">
              <label>Name</label>
              <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
            </div>
            <div className="field">
              <label>Email (optional — students don't log in)</label>
              <input type="email" disabled={!!editing} value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
            </div>
            <div className="form-grid">
              <div>
                <label>Primary Phone</label>
                <input value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} placeholder="+91XXXXXXXXXX" required />
              </div>
              <div>
                <label>Secondary / Emergency Contact</label>
                <input
                  value={form.phone_secondary}
                  onChange={(e) => setForm({ ...form, phone_secondary: e.target.value })}
                  placeholder="+91XXXXXXXXXX"
                  required={!editing}
                />
              </div>
            </div>
            {!editing && (
              <div className="field">
                <label>Additional Details (optional)</label>
                <textarea rows={2} value={form.additional_details} onChange={(e) => setForm({ ...form, additional_details: e.target.value })} />
              </div>
            )}
            <div className="field">
              <label>{editing ? "New Password (optional)" : "Password (optional — students don't log in)"}</label>
              <input type="password" minLength={8} value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
            </div>
            <div className="modal-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>
                Cancel
              </button>
              <button className="btn btn-primary">{editing ? "Save" : "Create"}</button>
            </div>
          </form>
        </Modal>
      )}

      {viewingId && (
        <Modal title="Student Report" onClose={() => setViewingId(null)}>
          <StudentReportPanel studentId={viewingId} />
        </Modal>
      )}

      {profileFor && (
        <Modal title="Student Profile" onClose={() => setProfileFor(null)}>
          <div style={{ display: "flex", gap: 16, flexWrap: "wrap" }}>
            <div style={{ flexShrink: 0 }}>
              {photoLoading ? (
                <div style={{ width: 140, height: 140, borderRadius: 12, background: "var(--brand-light)" }} />
              ) : photoUrl ? (
                <img src={photoUrl} alt={profileFor.name} style={{ width: 140, height: 140, objectFit: "cover", borderRadius: 12 }} />
              ) : (
                <div
                  className="empty-state"
                  style={{ width: 140, height: 140, borderRadius: 12, background: "var(--brand-light)", display: "flex", alignItems: "center", justifyContent: "center", padding: 8 }}
                >
                  No photo
                </div>
              )}
              <button className="btn btn-secondary" style={{ marginTop: 8, width: 140 }} onClick={() => setUploadFor(profileFor)}>
                Upload Photo
              </button>
            </div>
            <div style={{ flex: 1, minWidth: 200 }}>
              <table>
                <tbody>
                  <tr>
                    <td>Student ID</td>
                    <td>#{profileFor.id}</td>
                  </tr>
                  <tr>
                    <td>Name</td>
                    <td>{profileFor.name}</td>
                  </tr>
                  <tr>
                    <td>Phone</td>
                    <td>{profileFor.phone || "-"}</td>
                  </tr>
                  <tr>
                    <td>Emergency Contact</td>
                    <td>{profileFor.phone_secondary || "-"}</td>
                  </tr>
                  <tr>
                    <td>Email</td>
                    <td>{displayEmail(profileFor.email)}</td>
                  </tr>
                  <tr>
                    <td>Status</td>
                    <td>
                      <span className={`badge ${profileFor.is_active ? "badge-present" : "badge-absent"}`}>
                        {profileFor.is_active ? "Active" : "Inactive"}
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </Modal>
      )}

      {uploadFor && (
        <SelfieCapture title={`Upload Photo — ${uploadFor.name}`} onClose={() => setUploadFor(null)} onCapture={uploadPhoto} />
      )}
    </div>
  );
}
