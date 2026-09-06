import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { ActivitiesAPI, CoachesAPI, StudentsAPI } from "../api/endpoints";
import Modal from "../components/Modal";

export default function Activities() {
  const [activities, setActivities] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState({ name: "", capacity: 20, monthly_fee: "0" });
  const [managing, setManaging] = useState(null);

  const load = () => {
    setLoading(true);
    ActivitiesAPI.list()
      .then((r) => setActivities(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load activities"))
      .finally(() => setLoading(false));
  };

  useEffect(load, []);

  const openCreate = () => {
    setEditing(null);
    setForm({ name: "", capacity: 20, monthly_fee: "0" });
    setShowForm(true);
  };

  const openEdit = (a) => {
    setEditing(a);
    setForm({ name: a.name, capacity: a.capacity, monthly_fee: String(a.monthly_fee) });
    setShowForm(true);
  };

  const submit = async (e) => {
    e.preventDefault();
    try {
      const payload = { name: form.name, capacity: Number(form.capacity), monthly_fee: form.monthly_fee };
      if (editing) {
        await ActivitiesAPI.update(editing.id, payload);
        toast.success("Activity updated");
      } else {
        await ActivitiesAPI.create(payload);
        toast.success("Activity created");
      }
      setShowForm(false);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Save failed");
    }
  };

  const remove = async (a) => {
    if (!confirm(`Delete activity "${a.name}"? This removes its classes too.`)) return;
    try {
      await ActivitiesAPI.remove(a.id);
      toast.success("Activity deleted");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Delete failed");
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>Activities</h1>
        <button className="btn btn-primary" onClick={openCreate}>
          + Add Activity
        </button>
      </div>

      <div className="card">
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : activities.length === 0 ? (
          <div className="empty-state">No activities yet.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Name</th>
                <th>Capacity</th>
                <th>Monthly Fee</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {activities.map((a) => (
                <tr key={a.id}>
                  <td>{a.name}</td>
                  <td>{a.capacity}</td>
                  <td>₹{a.monthly_fee}</td>
                  <td>
                    <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => setManaging(a)}>
                      Manage
                    </button>
                    <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => openEdit(a)}>
                      Edit
                    </button>
                    <button className="btn btn-danger" onClick={() => remove(a)}>
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
        <Modal title={editing ? "Edit Activity" : "Add Activity"} onClose={() => setShowForm(false)}>
          <form onSubmit={submit}>
            <div className="field">
              <label>Name</label>
              <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
            </div>
            <div className="field">
              <label>Capacity</label>
              <input type="number" min={0} value={form.capacity} onChange={(e) => setForm({ ...form, capacity: e.target.value })} required />
            </div>
            <div className="field">
              <label>Monthly Fee (₹)</label>
              <input type="number" min={0} step="0.01" value={form.monthly_fee} onChange={(e) => setForm({ ...form, monthly_fee: e.target.value })} required />
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

      {managing && <ActivityManageModal activity={managing} onClose={() => setManaging(null)} />}
    </div>
  );
}

function ActivityManageModal({ activity, onClose }) {
  const [tab, setTab] = useState("classes");
  const [classes, setClasses] = useState([]);
  const [roster, setRoster] = useState([]);
  const [coaches, setCoaches] = useState([]);
  const [students, setStudents] = useState([]);
  const [classForm, setClassForm] = useState({ coach_id: "", date: "", start_time: "", end_time: "" });
  const [enrollStudentId, setEnrollStudentId] = useState("");
  const [editingClass, setEditingClass] = useState(null);
  const [editClassForm, setEditClassForm] = useState({ coach_id: "", date: "", start_time: "", end_time: "" });

  const loadAll = () => {
    ActivitiesAPI.classes(activity.id).then((r) => setClasses(r.data));
    ActivitiesAPI.roster(activity.id).then((r) => setRoster(r.data));
    CoachesAPI.list().then((r) => setCoaches(r.data));
    StudentsAPI.list().then((r) => setStudents(r.data));
  };

  useEffect(loadAll, [activity.id]);

  const createClass = async (e) => {
    e.preventDefault();
    try {
      await ActivitiesAPI.createClass({ activity_id: activity.id, ...classForm, coach_id: Number(classForm.coach_id) });
      toast.success("Class scheduled");
      setClassForm({ coach_id: "", date: "", start_time: "", end_time: "" });
      loadAll();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to create class");
    }
  };

  const enroll = async (e) => {
    e.preventDefault();
    try {
      await ActivitiesAPI.enroll({ student_id: Number(enrollStudentId), activity_id: activity.id });
      toast.success("Student enrolled");
      setEnrollStudentId("");
      loadAll();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Enrollment failed");
    }
  };

  const unenroll = async (student) => {
    if (!confirm(`Remove ${student.name} from ${activity.name}?`)) return;
    try {
      await ActivitiesAPI.unenroll(student.enrollment_id);
      toast.success("Student removed from activity");
      loadAll();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to remove student");
    }
  };

  const openEditClass = (c) => {
    setEditingClass(c);
    setEditClassForm({ coach_id: c.coach_id, date: c.date, start_time: c.start_time, end_time: c.end_time });
  };

  const submitEditClass = async (e) => {
    e.preventDefault();
    try {
      await ActivitiesAPI.updateClass(editingClass.id, { ...editClassForm, coach_id: Number(editClassForm.coach_id) });
      toast.success("Class updated");
      setEditingClass(null);
      loadAll();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Update failed");
    }
  };

  const removeClass = async (c) => {
    if (!confirm(`Delete the class on ${c.date}? This also removes its attendance records.`)) return;
    try {
      await ActivitiesAPI.removeClass(c.id);
      toast.success("Class deleted");
      loadAll();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Delete failed");
    }
  };

  return (
    <>
    <Modal title={`Manage: ${activity.name}`} onClose={onClose}>
      <div className="tab-bar">
        <button className={tab === "classes" ? "active" : ""} onClick={() => setTab("classes")}>
          Classes
        </button>
        <button className={tab === "roster" ? "active" : ""} onClick={() => setTab("roster")}>
          Roster
        </button>
      </div>

      {tab === "classes" && (
        <div>
          <form onSubmit={createClass} className="form-grid" style={{ marginBottom: 16 }}>
            <div>
              <label>Coach</label>
              <select value={classForm.coach_id} onChange={(e) => setClassForm({ ...classForm, coach_id: e.target.value })} required>
                <option value="">Select coach</option>
                {coaches.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label>Date</label>
              <input type="date" value={classForm.date} onChange={(e) => setClassForm({ ...classForm, date: e.target.value })} required />
            </div>
            <div>
              <label>Start Time</label>
              <input type="time" value={classForm.start_time} onChange={(e) => setClassForm({ ...classForm, start_time: e.target.value })} required />
            </div>
            <div>
              <label>End Time</label>
              <input type="time" value={classForm.end_time} onChange={(e) => setClassForm({ ...classForm, end_time: e.target.value })} required />
            </div>
            <div style={{ alignSelf: "end" }}>
              <button className="btn btn-primary">Schedule Class</button>
            </div>
          </form>

          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Time</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {classes.map((c) => (
                <tr key={c.id}>
                  <td>{c.date}</td>
                  <td>
                    {c.start_time} - {c.end_time}
                  </td>
                  <td>
                    <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => openEditClass(c)}>
                      Edit
                    </button>
                    <button className="btn btn-danger" onClick={() => removeClass(c)}>
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {tab === "roster" && (
        <div>
          <form onSubmit={enroll} className="toolbar">
            <select value={enrollStudentId} onChange={(e) => setEnrollStudentId(e.target.value)} required style={{ maxWidth: 260 }}>
              <option value="">Select student to enroll</option>
              {students.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </select>
            <button className="btn btn-primary">Enroll</button>
          </form>
          <table>
            <thead>
              <tr>
                <th>Name</th>
                <th>Email</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {roster.map((s) => (
                <tr key={s.id}>
                  <td>{s.name}</td>
                  <td>{s.email}</td>
                  <td>
                    <button className="btn btn-danger" onClick={() => unenroll(s)}>
                      Remove
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Modal>

    {editingClass && (
      <Modal title="Edit Class" onClose={() => setEditingClass(null)}>
        <form onSubmit={submitEditClass}>
          <div className="field">
            <label>Coach</label>
            <select value={editClassForm.coach_id} onChange={(e) => setEditClassForm({ ...editClassForm, coach_id: e.target.value })} required>
              <option value="">Select coach</option>
              {coaches.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
          <div className="field">
            <label>Date</label>
            <input type="date" value={editClassForm.date} onChange={(e) => setEditClassForm({ ...editClassForm, date: e.target.value })} required />
          </div>
          <div className="form-grid">
            <div>
              <label>Start Time</label>
              <input type="time" value={editClassForm.start_time} onChange={(e) => setEditClassForm({ ...editClassForm, start_time: e.target.value })} required />
            </div>
            <div>
              <label>End Time</label>
              <input type="time" value={editClassForm.end_time} onChange={(e) => setEditClassForm({ ...editClassForm, end_time: e.target.value })} required />
            </div>
          </div>
          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={() => setEditingClass(null)}>
              Cancel
            </button>
            <button className="btn btn-primary">Save</button>
          </div>
        </form>
      </Modal>
    )}
    </>
  );
}
