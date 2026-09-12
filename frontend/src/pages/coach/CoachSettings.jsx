import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { AuthAPI, ResetAPI } from "../../api/endpoints";
import { useTheme } from "../../context/ThemeContext";
import { useAuth } from "../../context/AuthContext";
import Modal from "../../components/Modal";
import { IconSun, IconMoon } from "../../components/icons";

export default function CoachSettings() {
  const { theme, toggleTheme } = useTheme();
  const { updateUser } = useAuth();

  const [me, setMe] = useState(null);
  const [form, setForm] = useState({ name: "", phone: "", email: "", current_password: "", new_password: "" });
  const [saving, setSaving] = useState(false);

  const [showReset, setShowReset] = useState(false);
  const [resetConfirmText, setResetConfirmText] = useState("");
  const [resetting, setResetting] = useState(false);

  useEffect(() => {
    AuthAPI.me()
      .then((r) => {
        setMe(r.data);
        setForm((f) => ({ ...f, name: r.data.name, phone: r.data.phone || "", email: r.data.email }));
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load your account"));
  }, []);

  const submit = async (e) => {
    e.preventDefault();
    if (!form.current_password) {
      toast.error("Enter your current password to confirm changes");
      return;
    }
    setSaving(true);
    try {
      const payload = { current_password: form.current_password };
      if (form.name && form.name !== me.name) payload.name = form.name;
      if (form.phone !== (me.phone || "")) payload.phone = form.phone;
      if (form.email && form.email !== me.email) payload.email = form.email;
      if (form.new_password) payload.new_password = form.new_password;
      const { data } = await AuthAPI.updateMe(payload);
      setMe(data);
      updateUser({ name: data.name });
      setForm({ name: data.name, phone: data.phone || "", email: data.email, current_password: "", new_password: "" });
      toast.success("Profile updated");
    } catch (err) {
      toast.error(err.response?.data?.detail || "Update failed");
    } finally {
      setSaving(false);
    }
  };

  const submitReset = async () => {
    if (resetConfirmText.trim().toUpperCase() !== "RESET") return;
    setResetting(true);
    try {
      const { data } = await ResetAPI.mine();
      toast.success(data.detail || "Your data has been reset");
      setShowReset(false);
      setResetConfirmText("");
    } catch (err) {
      toast.error(err.response?.data?.detail || "Reset failed");
    } finally {
      setResetting(false);
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>Settings</h1>
      </div>

      <div className="card" style={{ maxWidth: 640, marginBottom: 24 }}>
        <h3 style={{ marginTop: 0 }}>My Profile</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)" }}>
          Update your name, phone, login email, or password.
        </p>
        {!me ? (
          <div className="empty-state">Loading...</div>
        ) : (
          <form onSubmit={submit}>
            <div className="form-grid">
              <div>
                <label>Name</label>
                <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
              </div>
              <div>
                <label>Phone</label>
                <input value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} placeholder="+91XXXXXXXXXX" />
              </div>
            </div>
            <div className="field">
              <label>Login Email (User ID)</label>
              <input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} required />
            </div>
            <div className="field">
              <label>New Password (optional)</label>
              <input
                type="password"
                minLength={8}
                value={form.new_password}
                onChange={(e) => setForm({ ...form, new_password: e.target.value })}
                placeholder="Leave blank to keep current password"
              />
            </div>
            <div className="field">
              <label>Current Password (required to confirm)</label>
              <input
                type="password"
                value={form.current_password}
                onChange={(e) => setForm({ ...form, current_password: e.target.value })}
                required
              />
            </div>
            <div className="modal-actions" style={{ justifyContent: "flex-start" }}>
              <button className="btn btn-primary" disabled={saving}>
                {saving ? "Saving..." : "Save Changes"}
              </button>
            </div>
          </form>
        )}
      </div>

      <div className="card" style={{ maxWidth: 640, marginBottom: 24 }}>
        <h3 style={{ marginTop: 0 }}>Appearance</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -8 }}>
          Switch between light and dark mode. This also changes the icon in the top bar.
        </p>
        <button className="btn btn-secondary" onClick={toggleTheme}>
          {theme === "dark" ? <IconSun /> : <IconMoon />}
          <span style={{ marginLeft: 8 }}>Switch to {theme === "dark" ? "Light" : "Dark"} Mode</span>
        </button>
      </div>

      <div className="card" style={{ maxWidth: 640, borderColor: "var(--danger)" }}>
        <h3 style={{ marginTop: 0, color: "var(--danger)" }}>Danger Zone</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)" }}>
          Reset your own attendance and leave history back to a clean slate. This never affects
          other coaches or any fee/receipt record. This cannot be undone.
        </p>
        <button className="btn btn-danger" onClick={() => setShowReset(true)}>
          Reset My Data
        </button>
      </div>

      {showReset && (
        <Modal title="Reset My Data?" onClose={() => setShowReset(false)}>
          <p>
            This permanently erases <strong>your own</strong> attendance and leave history. Other
            coaches, students, fees, and receipts are never touched. This cannot be undone.
          </p>
          <div className="field">
            <label>
              Type <strong>RESET</strong> to confirm
            </label>
            <input value={resetConfirmText} onChange={(e) => setResetConfirmText(e.target.value)} autoFocus />
          </div>
          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={() => setShowReset(false)}>
              Cancel
            </button>
            <button
              className="btn btn-danger"
              disabled={resetting || resetConfirmText.trim().toUpperCase() !== "RESET"}
              onClick={submitReset}
            >
              {resetting ? "Resetting..." : "Reset My Data"}
            </button>
          </div>
        </Modal>
      )}
    </div>
  );
}
