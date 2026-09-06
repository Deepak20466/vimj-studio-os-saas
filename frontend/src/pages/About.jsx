import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { AcademyAPI } from "../api/endpoints";

const empty = { name: "", address: "", phone: "", email: "", description: "" };

export default function About() {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState(empty);

  useEffect(() => {
    AcademyAPI.get()
      .then((r) => setForm({ ...empty, ...r.data }))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load academy details"))
      .finally(() => setLoading(false));
  }, []);

  const submit = async (e) => {
    e.preventDefault();
    setSaving(true);
    try {
      const { data } = await AcademyAPI.update(form);
      setForm({ ...empty, ...data });
      toast.success("Academy details saved");
    } catch (err) {
      toast.error(err.response?.data?.detail || "Save failed");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>About</h1>
      </div>

      <div className="card" style={{ maxWidth: 640 }}>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: 0 }}>
          Academy details shown across the dashboard and available to coaches. Only admins can edit this.
        </p>
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : (
          <form onSubmit={submit}>
            <div className="field">
              <label>Academy Name</label>
              <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
            </div>
            <div className="field">
              <label>Address</label>
              <textarea rows={2} value={form.address || ""} onChange={(e) => setForm({ ...form, address: e.target.value })} />
            </div>
            <div className="form-grid">
              <div>
                <label>Phone</label>
                <input value={form.phone || ""} onChange={(e) => setForm({ ...form, phone: e.target.value })} />
              </div>
              <div>
                <label>Email</label>
                <input type="email" value={form.email || ""} onChange={(e) => setForm({ ...form, email: e.target.value })} />
              </div>
            </div>
            <div className="field">
              <label>Description</label>
              <textarea
                rows={4}
                value={form.description || ""}
                onChange={(e) => setForm({ ...form, description: e.target.value })}
                placeholder="A short description of the academy shown to staff."
              />
            </div>
            <div className="modal-actions" style={{ justifyContent: "flex-start" }}>
              <button className="btn btn-primary" disabled={saving}>
                {saving ? "Saving..." : "Save"}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
