import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { AuthAPI, CoachesAPI, ResetAPI, AcademyAPI } from "../api/endpoints";
import Modal from "../components/Modal";

const emptyCoachForm = { name: "", email: "", phone: "", password: "" };
const emptyCredForm = { email: "", password: "" };

export default function Settings() {
  // --- Admin's own account ---
  const [me, setMe] = useState(null);
  const [accountForm, setAccountForm] = useState({ email: "", current_password: "", new_password: "" });
  const [accountSaving, setAccountSaving] = useState(false);

  // --- Academy profile ---
  const [academy, setAcademy] = useState(null);
  const [academyForm, setAcademyForm] = useState({ name: "", address: "", phone: "", email: "", description: "" });
  const [academySaving, setAcademySaving] = useState(false);

  // --- Coach accounts ---
  const [coaches, setCoaches] = useState([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [showAddForm, setShowAddForm] = useState(false);
  const [addForm, setAddForm] = useState(emptyCoachForm);
  const [addSaving, setAddSaving] = useState(false);
  const [credCoach, setCredCoach] = useState(null);
  const [credForm, setCredForm] = useState(emptyCredForm);
  const [credSaving, setCredSaving] = useState(false);

  // --- Danger zone: full data reset ---
  const [showReset, setShowReset] = useState(false);
  const [resetConfirmText, setResetConfirmText] = useState("");
  const [resetting, setResetting] = useState(false);

  useEffect(() => {
    AuthAPI.me()
      .then((r) => {
        setMe(r.data);
        setAccountForm((f) => ({ ...f, email: r.data.email }));
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load your account"));
  }, []);

  useEffect(() => {
    AcademyAPI.get()
      .then((r) => {
        setAcademy(r.data);
        setAcademyForm({
          name: r.data.name || "",
          address: r.data.address || "",
          phone: r.data.phone || "",
          email: r.data.email || "",
          description: r.data.description || "",
        });
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load academy profile"));
  }, []);

  const submitAcademy = async (e) => {
    e.preventDefault();
    setAcademySaving(true);
    try {
      const { data } = await AcademyAPI.update(academyForm);
      setAcademy(data);
      toast.success("Academy profile updated");
    } catch (err) {
      toast.error(err.response?.data?.detail || "Update failed");
    } finally {
      setAcademySaving(false);
    }
  };

  const loadCoaches = () => {
    setLoading(true);
    CoachesAPI.list(search)
      .then((r) => setCoaches(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load coaches"))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    const t = setTimeout(loadCoaches, 250);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search]);

  const submitAccount = async (e) => {
    e.preventDefault();
    if (!accountForm.current_password) {
      toast.error("Enter your current password to confirm changes");
      return;
    }
    setAccountSaving(true);
    try {
      const payload = { current_password: accountForm.current_password };
      if (accountForm.email && accountForm.email !== me.email) payload.email = accountForm.email;
      if (accountForm.new_password) payload.new_password = accountForm.new_password;
      const { data } = await AuthAPI.updateMe(payload);
      setMe(data);
      setAccountForm({ email: data.email, current_password: "", new_password: "" });
      toast.success("Account updated");
    } catch (err) {
      toast.error(err.response?.data?.detail || "Update failed");
    } finally {
      setAccountSaving(false);
    }
  };

  const openAdd = () => {
    setAddForm(emptyCoachForm);
    setShowAddForm(true);
  };

  const submitAdd = async (e) => {
    e.preventDefault();
    setAddSaving(true);
    try {
      await CoachesAPI.create(addForm);
      toast.success("Coach created");
      setShowAddForm(false);
      loadCoaches();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to create coach");
    } finally {
      setAddSaving(false);
    }
  };

  const toggleCoachActive = async (c) => {
    try {
      await CoachesAPI.update(c.id, { is_active: !c.is_active });
      loadCoaches();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Update failed");
    }
  };

  const openCred = (c) => {
    setCredCoach(c);
    setCredForm({ email: c.email, password: "" });
  };

  const submitCred = async (e) => {
    e.preventDefault();
    setCredSaving(true);
    try {
      const payload = {};
      if (credForm.email && credForm.email !== credCoach.email) payload.email = credForm.email;
      if (credForm.password) payload.password = credForm.password;
      if (Object.keys(payload).length === 0) {
        toast.error("Change the user ID or password before saving");
        setCredSaving(false);
        return;
      }
      await CoachesAPI.update(credCoach.id, payload);
      toast.success("Coach credentials updated");
      setCredCoach(null);
      loadCoaches();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Update failed");
    } finally {
      setCredSaving(false);
    }
  };

  const openReset = () => {
    setResetConfirmText("");
    setShowReset(true);
  };

  const submitReset = async () => {
    if (resetConfirmText.trim().toUpperCase() !== "RESET") return;
    setResetting(true);
    try {
      const { data } = await ResetAPI.all();
      toast.success(data.detail || "All data has been reset");
      setShowReset(false);
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
        <h3 style={{ marginTop: 0 }}>My Account</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)" }}>
          Change your own admin login email or password.
        </p>
        {!me ? (
          <div className="empty-state">Loading...</div>
        ) : (
          <form onSubmit={submitAccount}>
            <div className="field">
              <label>Login Email (User ID)</label>
              <input
                type="email"
                value={accountForm.email}
                onChange={(e) => setAccountForm({ ...accountForm, email: e.target.value })}
                required
              />
            </div>
            <div className="field">
              <label>New Password (optional)</label>
              <input
                type="password"
                minLength={8}
                value={accountForm.new_password}
                onChange={(e) => setAccountForm({ ...accountForm, new_password: e.target.value })}
                placeholder="Leave blank to keep current password"
              />
            </div>
            <div className="field">
              <label>Current Password (required to confirm)</label>
              <input
                type="password"
                value={accountForm.current_password}
                onChange={(e) => setAccountForm({ ...accountForm, current_password: e.target.value })}
                required
              />
            </div>
            <div className="modal-actions" style={{ justifyContent: "flex-start" }}>
              <button className="btn btn-primary" disabled={accountSaving}>
                {accountSaving ? "Saving..." : "Save Changes"}
              </button>
            </div>
          </form>
        )}
      </div>

      <div className="card" style={{ maxWidth: 640, marginBottom: 24 }}>
        <h3 style={{ marginTop: 0 }}>Academy Profile</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)" }}>
          Shown on generated fee receipts and available to coaches.
        </p>
        {!academy ? (
          <div className="empty-state">Loading...</div>
        ) : (
          <form onSubmit={submitAcademy}>
            <div className="field">
              <label>Academy Name</label>
              <input value={academyForm.name} onChange={(e) => setAcademyForm({ ...academyForm, name: e.target.value })} required />
            </div>
            <div className="form-grid">
              <div>
                <label>Phone</label>
                <input value={academyForm.phone} onChange={(e) => setAcademyForm({ ...academyForm, phone: e.target.value })} placeholder="+91XXXXXXXXXX" />
              </div>
              <div>
                <label>Email</label>
                <input type="email" value={academyForm.email} onChange={(e) => setAcademyForm({ ...academyForm, email: e.target.value })} />
              </div>
            </div>
            <div className="field">
              <label>Address</label>
              <input value={academyForm.address} onChange={(e) => setAcademyForm({ ...academyForm, address: e.target.value })} />
            </div>
            <div className="field">
              <label>Description</label>
              <textarea rows={2} value={academyForm.description} onChange={(e) => setAcademyForm({ ...academyForm, description: e.target.value })} />
            </div>
            <div className="modal-actions" style={{ justifyContent: "flex-start" }}>
              <button className="btn btn-primary" disabled={academySaving}>
                {academySaving ? "Saving..." : "Save Changes"}
              </button>
            </div>
          </form>
        )}
      </div>

      <div className="page-header">
        <h3 style={{ margin: 0 }}>Coach Accounts</h3>
        <button className="btn btn-primary" onClick={openAdd}>
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
                <th>User ID (Email)</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {coaches.map((c) => (
                <tr key={c.id}>
                  <td>{c.name}</td>
                  <td>{c.email}</td>
                  <td>
                    <span className={`badge ${c.is_active ? "badge-present" : "badge-absent"}`}>{c.is_active ? "Active" : "Inactive"}</span>
                  </td>
                  <td className="table-actions">
                    <button className="btn btn-secondary btn-sm" onClick={() => openCred(c)}>
                      Change User ID / Password
                    </button>
                    <button className="btn btn-secondary btn-sm" onClick={() => toggleCoachActive(c)}>
                      {c.is_active ? "Deactivate" : "Activate"}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="card" style={{ maxWidth: 640, marginTop: 24, borderColor: "var(--danger)" }}>
        <h3 style={{ marginTop: 0, color: "var(--danger)" }}>Danger Zone</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)" }}>
          Reset all attendance, fee, and notification history back to a clean slate. Users,
          students, coaches, activities, and batches are kept — only records/history are erased.
          This cannot be undone.
        </p>
        <button className="btn btn-danger" onClick={openReset}>
          Reset All Data
        </button>
      </div>

      {showAddForm && (
        <Modal title="Add Coach" onClose={() => setShowAddForm(false)}>
          <form onSubmit={submitAdd}>
            <div className="field">
              <label>Name</label>
              <input value={addForm.name} onChange={(e) => setAddForm({ ...addForm, name: e.target.value })} required />
            </div>
            <div className="field">
              <label>Login Email (User ID)</label>
              <input type="email" value={addForm.email} onChange={(e) => setAddForm({ ...addForm, email: e.target.value })} required />
            </div>
            <div className="field">
              <label>Phone</label>
              <input value={addForm.phone} onChange={(e) => setAddForm({ ...addForm, phone: e.target.value })} placeholder="+91XXXXXXXXXX" />
            </div>
            <div className="field">
              <label>Password</label>
              <input type="password" minLength={8} value={addForm.password} onChange={(e) => setAddForm({ ...addForm, password: e.target.value })} required />
            </div>
            <div className="modal-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setShowAddForm(false)}>
                Cancel
              </button>
              <button className="btn btn-primary" disabled={addSaving}>
                {addSaving ? "Creating..." : "Create"}
              </button>
            </div>
          </form>
        </Modal>
      )}

      {credCoach && (
        <Modal title={`Change Credentials — ${credCoach.name}`} onClose={() => setCredCoach(null)}>
          <form onSubmit={submitCred}>
            <div className="field">
              <label>Login Email (User ID)</label>
              <input type="email" value={credForm.email} onChange={(e) => setCredForm({ ...credForm, email: e.target.value })} required />
            </div>
            <div className="field">
              <label>New Password (optional)</label>
              <input
                type="password"
                minLength={8}
                value={credForm.password}
                onChange={(e) => setCredForm({ ...credForm, password: e.target.value })}
                placeholder="Leave blank to keep current password"
              />
            </div>
            <div className="modal-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setCredCoach(null)}>
                Cancel
              </button>
              <button className="btn btn-primary" disabled={credSaving}>
                {credSaving ? "Saving..." : "Save"}
              </button>
            </div>
          </form>
        </Modal>
      )}

      {showReset && (
        <Modal title="Reset All Data?" onClose={() => setShowReset(false)}>
          <p>
            This permanently erases <strong>all</strong> attendance, fee, and notification
            records for every student and coach. Users, activities, and batches are kept so the
            app keeps working right after. This cannot be undone.
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
              {resetting ? "Resetting..." : "Reset All Data"}
            </button>
          </div>
        </Modal>
      )}
    </div>
  );
}
