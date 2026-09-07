import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { CoachesAPI, ActivitiesAPI } from "../api/endpoints";
import Modal from "../components/Modal";
import CoachReportPanel from "../components/CoachReportPanel";

export default function Coaches() {
  const [coaches, setCoaches] = useState([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState(null);
  const [viewingId, setViewingId] = useState(null);
  const [form, setForm] = useState({ name: "", email: "", phone: "", password: "" });
  const [managingActivitiesFor, setManagingActivitiesFor] = useState(null);
  const [allActivities, setAllActivities] = useState([]);
  const [selectedActivityIds, setSelectedActivityIds] = useState([]);
  const [activitiesSaving, setActivitiesSaving] = useState(false);

  const load = () => {
    setLoading(true);
    CoachesAPI.list(search)
      .then((r) => setCoaches(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load coaches"))
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

  const openEdit = (c) => {
    setEditing(c);
    setForm({ name: c.name, email: c.email, phone: c.phone || "", password: "" });
    setShowForm(true);
  };

  const submit = async (e) => {
    e.preventDefault();
    try {
      if (editing) {
        const payload = { name: form.name, phone: form.phone };
        if (form.email && form.email !== editing.email) payload.email = form.email;
        if (form.password) payload.password = form.password;
        await CoachesAPI.update(editing.id, payload);
        toast.success("Coach updated");
      } else {
        await CoachesAPI.create(form);
        toast.success("Coach created");
      }
      setShowForm(false);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Save failed");
    }
  };

  const toggleActive = async (c) => {
    try {
      await CoachesAPI.update(c.id, { is_active: !c.is_active });
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Update failed");
    }
  };

  const remove = async (c) => {
    if (!confirm(`Remove ${c.name}? This cannot be undone.`)) return;
    try {
      await CoachesAPI.remove(c.id);
      toast.success("Coach removed");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Delete failed");
    }
  };

  const openActivities = async (c) => {
    setManagingActivitiesFor(c);
    try {
      const [all, mine] = await Promise.all([ActivitiesAPI.list(), CoachesAPI.getActivities(c.id)]);
      setAllActivities(all.data);
      setSelectedActivityIds(mine.data.map((a) => a.activity_id));
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to load activities");
    }
  };

  const toggleActivity = (id) => {
    setSelectedActivityIds((ids) => (ids.includes(id) ? ids.filter((i) => i !== id) : [...ids, id]));
  };

  const saveActivities = async () => {
    setActivitiesSaving(true);
    try {
      await CoachesAPI.setActivities(managingActivitiesFor.id, selectedActivityIds);
      toast.success("Activities updated");
      setManagingActivitiesFor(null);
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to save activities");
    } finally {
      setActivitiesSaving(false);
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>Coaches</h1>
        <button className="btn btn-primary" onClick={openCreate}>
          + Add Coach
        </button>
      </div>

      <div className="toolbar">
        <input placeholder="Search by name or email..." value={search} onChange={(e) => setSearch(e.target.value)} style={{ maxWidth: 320 }} />
      </div>

      <div className="card">
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : coaches.length === 0 ? (
          <div className="empty-state">No coaches found.</div>
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
              {coaches.map((c) => (
                <tr key={c.id}>
                  <td>
                    <button className="link-btn" onClick={() => setViewingId(c.id)}>
                      {c.name}
                    </button>
                  </td>
                  <td>{c.email}</td>
                  <td>{c.phone || "-"}</td>
                  <td>
                    <span className={`badge ${c.is_active ? "badge-present" : "badge-absent"}`}>{c.is_active ? "Active" : "Inactive"}</span>
                  </td>
                  <td className="table-actions">
                    <button className="btn btn-secondary btn-sm" onClick={() => openActivities(c)}>
                      Activities
                    </button>
                    <button className="btn btn-secondary btn-sm" onClick={() => openEdit(c)}>
                      Edit
                    </button>
                    <button className="btn btn-secondary btn-sm" onClick={() => toggleActive(c)}>
                      {c.is_active ? "Deactivate" : "Activate"}
                    </button>
                    <button className="btn btn-danger btn-sm" onClick={() => remove(c)}>
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
        <Modal title={editing ? "Edit Coach" : "Add Coach"} onClose={() => setShowForm(false)}>
          <form onSubmit={submit}>
            <div className="field">
              <label>Name</label>
              <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
            </div>
            <div className="field">
              <label>Email</label>
              <input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} required />
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
        <Modal title="Coach Report" onClose={() => setViewingId(null)}>
          <CoachReportPanel coachId={viewingId} />
        </Modal>
      )}

      {managingActivitiesFor && (
        <Modal title={`Assigned Activities — ${managingActivitiesFor.name}`} onClose={() => setManagingActivitiesFor(null)}>
          <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -8 }}>
            Controls which activities this coach can be assigned to batches for, and which activities they may add
            students under.
          </p>
          {allActivities.length === 0 ? (
            <div className="empty-state">No activities exist yet.</div>
          ) : (
            <div style={{ display: "flex", flexDirection: "column", gap: 8, marginBottom: 16 }}>
              {allActivities.map((a) => (
                <label key={a.id} style={{ display: "flex", alignItems: "center", gap: 8, fontSize: "0.88rem" }}>
                  <input type="checkbox" checked={selectedActivityIds.includes(a.id)} onChange={() => toggleActivity(a.id)} />
                  {a.name}
                </label>
              ))}
            </div>
          )}
          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={() => setManagingActivitiesFor(null)}>
              Cancel
            </button>
            <button className="btn btn-primary" disabled={activitiesSaving} onClick={saveActivities}>
              {activitiesSaving ? "Saving..." : "Save"}
            </button>
          </div>
        </Modal>
      )}
    </div>
  );
}
