import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { StudentsAPI, ReportsAPI } from "../api/endpoints";
import Modal from "../components/Modal";
import StudentReportPanel from "../components/StudentReportPanel";

export default function Students() {
  const [students, setStudents] = useState([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState(null);
  const [viewingId, setViewingId] = useState(null);
  const [form, setForm] = useState({ name: "", email: "", phone: "", password: "" });

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
    setForm({ name: "", email: "", phone: "", password: "" });
    setShowForm(true);
  };

  const openEdit = (s) => {
    setEditing(s);
    setForm({ name: s.name, email: s.email, phone: s.phone || "", password: "" });
    setShowForm(true);
  };

  const submit = async (e) => {
    e.preventDefault();
    try {
      if (editing) {
        const payload = { name: form.name, phone: form.phone };
        if (form.password) payload.password = form.password;
        await StudentsAPI.update(editing.id, payload);
        toast.success("Student updated");
      } else {
        await StudentsAPI.create(form);
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
                  <td>{s.email}</td>
                  <td>{s.phone || "-"}</td>
                  <td>
                    <span className={`badge ${s.is_active ? "badge-present" : "badge-absent"}`}>{s.is_active ? "Active" : "Inactive"}</span>
                  </td>
                  <td>
                    <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => openEdit(s)}>
                      Edit
                    </button>
                    <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => toggleActive(s)}>
                      {s.is_active ? "Deactivate" : "Activate"}
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
              <label>Email</label>
              <input type="email" disabled={!!editing} value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} required />
            </div>
            <div className="field">
              <label>Phone</label>
              <input value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} placeholder="+91XXXXXXXXXX" />
            </div>
            <div className="field">
              <label>{editing ? "New Password (optional)" : "Password"}</label>
              <input type="password" minLength={8} value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} required={!editing} />
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
    </div>
  );
}
