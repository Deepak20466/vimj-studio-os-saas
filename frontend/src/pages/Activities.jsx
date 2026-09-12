import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { ActivitiesAPI, CoachesAPI, StudentsAPI, BatchesAPI, AttendanceAPI } from "../api/endpoints";
import Modal from "../components/Modal";

const todayStr = () => new Date().toISOString().slice(0, 10);
const STATUS_OPTIONS = ["PRESENT", "ABSENT", "LEAVE"];
const DAYS = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"];
const SESSION_PERIODS = ["MORNING", "AFTERNOON", "EVENING"];
const MONTHS = [
  { value: 1, label: "Jan" },
  { value: 2, label: "Feb" },
  { value: 3, label: "Mar" },
  { value: 4, label: "Apr" },
  { value: 5, label: "May" },
  { value: 6, label: "Jun" },
  { value: 7, label: "Jul" },
  { value: 8, label: "Aug" },
  { value: 9, label: "Sep" },
  { value: 10, label: "Oct" },
  { value: 11, label: "Nov" },
  { value: 12, label: "Dec" },
];
const ALL_MONTHS = MONTHS.map((m) => m.value);
const emptyBatchForm = {
  coach_id: "",
  location: "",
  session_period: "MORNING",
  start_time: "",
  end_time: "",
  days_of_week: [],
  active_months: ALL_MONTHS,
};

export default function Activities() {
  const [activities, setActivities] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState({ name: "", capacity: 20, monthly_fee: "0" });
  const [managing, setManaging] = useState(null);
  const [viewingSessions, setViewingSessions] = useState(null);

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
                  <td className="table-actions">
                    <button className="btn btn-secondary btn-sm" onClick={() => setManaging(a)}>
                      Manage
                    </button>
                    <button className="btn btn-secondary btn-sm" onClick={() => openEdit(a)}>
                      Edit
                    </button>
                    <button className="btn btn-secondary btn-sm" onClick={() => setViewingSessions(a)}>
                      Sessions
                    </button>
                    <button className="btn btn-danger btn-sm" onClick={() => remove(a)}>
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

      {viewingSessions && <SessionsModal activity={viewingSessions} onClose={() => setViewingSessions(null)} />}
    </div>
  );
}

function SessionsModal({ activity, onClose }) {
  const [batches, setBatches] = useState([]);
  const [coaches, setCoaches] = useState([]);
  const [loading, setLoading] = useState(true);
  const [viewingBatch, setViewingBatch] = useState(null);
  const [showForm, setShowForm] = useState(false);
  const [editingBatch, setEditingBatch] = useState(null);

  const load = () => {
    setLoading(true);
    BatchesAPI.list(activity.id)
      .then((r) => setBatches(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load sessions"))
      .finally(() => setLoading(false));
  };

  useEffect(load, [activity.id]);
  useEffect(() => {
    CoachesAPI.list().then((r) => setCoaches(r.data));
  }, []);

  const sessionLabel = (s) => s.charAt(0) + s.slice(1).toLowerCase();
  const coachName = (id) => coaches.find((c) => c.id === id)?.name || (id ? `#${id}` : "Unassigned");

  const openCreate = () => {
    setEditingBatch(null);
    setShowForm(true);
  };

  const openEdit = (b) => {
    setEditingBatch(b);
    setShowForm(true);
  };

  const removeBatch = async (b) => {
    if (!confirm(`Delete this session (${sessionLabel(b.session_period)}, ${b.start_time}-${b.end_time})? This also removes its generated classes and attendance.`)) return;
    try {
      await BatchesAPI.remove(b.id);
      toast.success("Session deleted");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Delete failed");
    }
  };

  return (
    <>
      <Modal title={`Sessions: ${activity.name}`} onClose={onClose}>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -4 }}>
          Every recurring slot (e.g. Morning 8:00 AM, Evening 5:00 PM) scheduled for this activity. Open Roster on a
          slot to see who's present/absent and fee status for that specific timing.
        </p>
        <div className="toolbar" style={{ justifyContent: "flex-end", marginBottom: 12 }}>
          <button className="btn btn-primary" onClick={openCreate}>
            + Add Session
          </button>
        </div>
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : batches.length === 0 ? (
          <div className="empty-state">No sessions scheduled yet for this activity. Add one above.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Session</th>
                <th>Time</th>
                <th>Days</th>
                <th>Location</th>
                <th>Coach</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {batches.map((b) => (
                <tr key={b.id}>
                  <td>{sessionLabel(b.session_period)}</td>
                  <td>
                    {b.start_time} - {b.end_time}
                  </td>
                  <td>{b.days_of_week.join(", ")}</td>
                  <td>{b.location}</td>
                  <td>{coachName(b.coach_id)}</td>
                  <td className="table-actions">
                    <button className="btn btn-secondary btn-sm" onClick={() => setViewingBatch(b)}>
                      Roster
                    </button>
                    <button className="btn btn-secondary btn-sm" onClick={() => openEdit(b)}>
                      Edit
                    </button>
                    <button className="btn btn-danger btn-sm" onClick={() => removeBatch(b)}>
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Modal>

      {showForm && (
        <SessionFormModal
          activity={activity}
          coaches={coaches}
          editing={editingBatch}
          onClose={() => setShowForm(false)}
          onSaved={() => {
            setShowForm(false);
            load();
          }}
        />
      )}

      {viewingBatch && (
        <SessionRosterModal activity={activity} batch={viewingBatch} onClose={() => setViewingBatch(null)} />
      )}
    </>
  );
}

function SessionFormModal({ activity, coaches, editing, onClose, onSaved }) {
  const [form, setForm] = useState(
    editing
      ? {
          coach_id: editing.coach_id || "",
          location: editing.location,
          session_period: editing.session_period,
          start_time: editing.start_time,
          end_time: editing.end_time,
          days_of_week: editing.days_of_week,
          active_months: editing.active_months && editing.active_months.length ? editing.active_months : ALL_MONTHS,
        }
      : emptyBatchForm
  );

  const toggleDay = (day) => {
    setForm((f) => ({
      ...f,
      days_of_week: f.days_of_week.includes(day) ? f.days_of_week.filter((d) => d !== day) : [...f.days_of_week, day],
    }));
  };

  const toggleMonth = (month) => {
    setForm((f) => ({
      ...f,
      active_months: f.active_months.includes(month)
        ? f.active_months.filter((m) => m !== month)
        : [...f.active_months, month].sort((a, b) => a - b),
    }));
  };

  const submit = async (e) => {
    e.preventDefault();
    if (form.days_of_week.length === 0) {
      toast.error("Select at least one day");
      return;
    }
    if (form.active_months.length === 0) {
      toast.error("Select at least one month");
      return;
    }
    try {
      const payload = {
        ...form,
        activity_id: activity.id,
        coach_id: form.coach_id ? Number(form.coach_id) : null,
      };
      if (editing) {
        await BatchesAPI.update(editing.id, payload);
        toast.success("Session updated");
      } else {
        await BatchesAPI.create(payload);
        toast.success("Session created");
      }
      onSaved();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Save failed");
    }
  };

  return (
    <Modal title={editing ? "Edit Session" : `Add Session: ${activity.name}`} onClose={onClose}>
      <form onSubmit={submit}>
        <div className="field">
          <label>Location</label>
          <input value={form.location} onChange={(e) => setForm({ ...form, location: e.target.value })} placeholder="e.g. Indiranagar" required />
        </div>
        <div className="form-grid">
          <div>
            <label>Session</label>
            <select value={form.session_period} onChange={(e) => setForm({ ...form, session_period: e.target.value })}>
              {SESSION_PERIODS.map((s) => (
                <option key={s} value={s}>
                  {s.charAt(0) + s.slice(1).toLowerCase()}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label>Coach</label>
            <select value={form.coach_id} onChange={(e) => setForm({ ...form, coach_id: e.target.value })}>
              <option value="">Unassigned</option>
              {coaches.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
        </div>
        <div className="form-grid">
          <div>
            <label>Start Time</label>
            <input type="time" value={form.start_time} onChange={(e) => setForm({ ...form, start_time: e.target.value })} required />
          </div>
          <div>
            <label>End Time</label>
            <input type="time" value={form.end_time} onChange={(e) => setForm({ ...form, end_time: e.target.value })} required />
          </div>
        </div>
        <div className="field">
          <label>Days</label>
          <div className="btn-group">
            {DAYS.map((d) => (
              <button
                type="button"
                key={d}
                className={`btn btn-sm btn-toggle ${form.days_of_week.includes(d) ? "btn-primary" : "btn-secondary"}`}
                onClick={() => toggleDay(d)}
              >
                {d}
              </button>
            ))}
          </div>
        </div>
        <div className="field">
          <label>Months</label>
          <div className="btn-group">
            {MONTHS.map((m) => (
              <button
                type="button"
                key={m.value}
                className={`btn btn-sm btn-toggle ${form.active_months.includes(m.value) ? "btn-primary" : "btn-secondary"}`}
                onClick={() => toggleMonth(m.value)}
              >
                {m.label}
              </button>
            ))}
          </div>
        </div>
        <div className="modal-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>
            Cancel
          </button>
          <button className="btn btn-primary">{editing ? "Save" : "Create"}</button>
        </div>
      </form>
    </Modal>
  );
}

function SessionRosterModal({ activity, batch, onClose }) {
  const [classDate, setClassDate] = useState(todayStr());
  const [roster, setRoster] = useState(null);
  const [loading, setLoading] = useState(true);
  const [updatingId, setUpdatingId] = useState(null);

  const load = () => {
    setLoading(true);
    BatchesAPI.roster(batch.id, classDate)
      .then((r) => setRoster(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load session roster"))
      .finally(() => setLoading(false));
  };

  useEffect(load, [batch.id, classDate]);

  const sessionLabel = (s) => s.charAt(0) + s.slice(1).toLowerCase();

  const setStatus = async (studentId, status) => {
    if (!roster?.class_id) {
      toast.error("No class session exists for this date yet. Generate sessions for this batch first.");
      return;
    }
    setUpdatingId(studentId);
    try {
      await AttendanceAPI.markManual({ class_id: roster.class_id, student_id: studentId, status });
      toast.success("Attendance updated");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to update attendance");
    } finally {
      setUpdatingId(null);
    }
  };

  return (
    <Modal
      title={`${activity.name} — ${sessionLabel(batch.session_period)} (${batch.start_time}-${batch.end_time})`}
      onClose={onClose}
    >
      <div className="toolbar" style={{ marginBottom: 12 }}>
        <label style={{ display: "flex", alignItems: "center", gap: 6, fontSize: "0.85rem" }}>
          Date
          <input type="date" value={classDate} onChange={(e) => setClassDate(e.target.value)} />
        </label>
      </div>

      {loading || !roster ? (
        <div className="empty-state">Loading...</div>
      ) : (
        <>
          {!roster.class_id && (
            <p style={{ fontSize: "0.8rem", color: "var(--text-muted)" }}>
              No class session was generated for this batch on {classDate}. Marking is disabled until one exists.
            </p>
          )}
          <div style={{ display: "flex", gap: 16, marginBottom: 12, fontSize: "0.85rem" }}>
            <span>Present: <strong>{roster.present_count}</strong></span>
            <span>Absent/Leave: <strong>{roster.absent_count}</strong></span>
            <span>Unmarked: <strong>{roster.unmarked_count}</strong></span>
          </div>

          {roster.students.length === 0 ? (
            <div className="empty-state">No students enrolled in this activity yet.</div>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>Student</th>
                  <th>Attendance</th>
                  <th>Fee (this month)</th>
                  <th>Edit</th>
                </tr>
              </thead>
              <tbody>
                {roster.students.map((s) => (
                  <tr key={s.student_id}>
                    <td>{s.student_name}</td>
                    <td>
                      <span
                        className={`badge badge-${
                          s.attendance_status === "PRESENT"
                            ? "approved"
                            : s.attendance_status === "UNMARKED"
                            ? "pending"
                            : "rejected"
                        }`}
                      >
                        {s.attendance_status}
                      </span>
                    </td>
                    <td>
                      {s.attendance_status === "PRESENT" ? (
                        <span className={`badge badge-${s.fee_status === "PAID" ? "approved" : "rejected"}`}>
                          {s.fee_status || "UNPAID"}
                        </span>
                      ) : (
                        "-"
                      )}
                    </td>
                    <td>
                      <div style={{ display: "flex", gap: 4, flexWrap: "wrap" }}>
                        {STATUS_OPTIONS.map((opt) => (
                          <button
                            key={opt}
                            type="button"
                            className={s.attendance_status === opt ? "btn btn-primary" : "btn btn-secondary"}
                            disabled={updatingId === s.student_id || !roster.class_id}
                            onClick={() => setStatus(s.student_id, opt)}
                          >
                            {opt.charAt(0) + opt.slice(1).toLowerCase()}
                          </button>
                        ))}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </>
      )}
    </Modal>
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
                  <td className="table-actions">
                    <button className="btn btn-secondary btn-sm" onClick={() => openEditClass(c)}>
                      Edit
                    </button>
                    <button className="btn btn-danger btn-sm" onClick={() => removeClass(c)}>
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
                  <td className="table-actions">
                    <button className="btn btn-danger btn-sm" onClick={() => unenroll(s)}>
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
