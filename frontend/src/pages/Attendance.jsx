import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { AttendanceAPI, ActivitiesAPI, StudentsAPI } from "../api/endpoints";
import StatusBadge from "../components/StatusBadge";
import Modal from "../components/Modal";

export default function Attendance() {
  const [missing, setMissing] = useState([]);
  const [missingLoading, setMissingLoading] = useState(true);
  const [activities, setActivities] = useState([]);

  const [records, setRecords] = useState([]);
  const [recordsLoading, setRecordsLoading] = useState(true);
  const [filters, setFilters] = useState({ activity_id: "", status_filter: "", date_from: "", date_to: "" });

  const [manualForm, setManualForm] = useState({ activity_id: "", student_id: "", class_id: "", status: "PRESENT" });
  const [classes, setClasses] = useState([]);
  const [roster, setRoster] = useState([]);

  const [editing, setEditing] = useState(null); // record being edited
  const [editStatus, setEditStatus] = useState("PRESENT");

  const loadMissing = () => {
    setMissingLoading(true);
    AttendanceAPI.dailyMissing()
      .then((r) => setMissing(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load"))
      .finally(() => setMissingLoading(false));
  };

  const loadRecords = () => {
    setRecordsLoading(true);
    const params = {};
    if (filters.activity_id) params.activity_id = Number(filters.activity_id);
    if (filters.status_filter) params.status_filter = filters.status_filter;
    if (filters.date_from) params.date_from = filters.date_from;
    if (filters.date_to) params.date_to = filters.date_to;
    AttendanceAPI.list(params)
      .then((r) => setRecords(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load attendance records"))
      .finally(() => setRecordsLoading(false));
  };

  useEffect(() => {
    loadMissing();
    ActivitiesAPI.list().then((r) => setActivities(r.data));
  }, []);

  useEffect(() => {
    const t = setTimeout(loadRecords, 200);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filters]);

  useEffect(() => {
    if (!manualForm.activity_id) {
      setClasses([]);
      setRoster([]);
      return;
    }
    ActivitiesAPI.classes(manualForm.activity_id).then((r) => setClasses(r.data));
    ActivitiesAPI.roster(manualForm.activity_id).then((r) => setRoster(r.data));
  }, [manualForm.activity_id]);

  const submitManual = async (e) => {
    e.preventDefault();
    try {
      await AttendanceAPI.markManual({
        student_id: Number(manualForm.student_id),
        class_id: Number(manualForm.class_id),
        status: manualForm.status,
      });
      toast.success("Attendance recorded");
      setManualForm({ ...manualForm, student_id: "", class_id: "" });
      loadMissing();
      loadRecords();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to mark attendance");
    }
  };

  const openEdit = (r) => {
    setEditing(r);
    setEditStatus(r.status);
  };

  const submitEdit = async (e) => {
    e.preventDefault();
    try {
      await AttendanceAPI.update(editing.id, { status: editStatus });
      toast.success("Attendance updated");
      setEditing(null);
      loadRecords();
      loadMissing();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Update failed");
    }
  };

  const remove = async (r) => {
    if (!confirm(`Delete this attendance record for ${r.student_name}?`)) return;
    try {
      await AttendanceAPI.remove(r.id);
      toast.success("Attendance record deleted");
      loadRecords();
      loadMissing();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Delete failed");
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>Attendance</h1>
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Coaches Missing Attendance (Today)</h3>
        {missingLoading ? (
          <div className="empty-state">Loading...</div>
        ) : missing.length === 0 ? (
          <div className="empty-state">Nothing outstanding — every ended class today has attendance marked.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Coach</th>
                <th>Activity</th>
                <th>Date</th>
                <th>End Time</th>
              </tr>
            </thead>
            <tbody>
              {missing.map((m) => (
                <tr key={m.class_id}>
                  <td>{m.coach_name}</td>
                  <td>{m.activity_name}</td>
                  <td>{m.date}</td>
                  <td>{m.end_time}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Manual Attendance Entry (Admin)</h3>
        <p style={{ color: "var(--text-muted)", fontSize: "0.85rem", marginTop: -8 }}>
          Bypasses geofence and selfie requirements — use for correcting or backfilling records.
        </p>
        <form onSubmit={submitManual} className="form-grid">
          <div>
            <label>Activity</label>
            <select value={manualForm.activity_id} onChange={(e) => setManualForm({ ...manualForm, activity_id: e.target.value, class_id: "", student_id: "" })} required>
              <option value="">Select activity</option>
              {activities.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label>Class</label>
            <select value={manualForm.class_id} onChange={(e) => setManualForm({ ...manualForm, class_id: e.target.value })} required>
              <option value="">Select class</option>
              {classes.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.date} ({c.start_time}-{c.end_time})
                </option>
              ))}
            </select>
          </div>
          <div>
            <label>Student</label>
            <select value={manualForm.student_id} onChange={(e) => setManualForm({ ...manualForm, student_id: e.target.value })} required>
              <option value="">Select student</option>
              {roster.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label>Status</label>
            <select value={manualForm.status} onChange={(e) => setManualForm({ ...manualForm, status: e.target.value })}>
              <option value="PRESENT">Present</option>
              <option value="ABSENT">Absent</option>
              <option value="LEAVE">Leave</option>
            </select>
          </div>
          <div style={{ alignSelf: "end" }}>
            <button className="btn btn-primary">Record</button>
          </div>
        </form>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>All Attendance Records</h3>
        <div className="toolbar" style={{ marginBottom: 12 }}>
          <select value={filters.activity_id} onChange={(e) => setFilters({ ...filters, activity_id: e.target.value })}>
            <option value="">All activities</option>
            {activities.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name}
              </option>
            ))}
          </select>
          <select value={filters.status_filter} onChange={(e) => setFilters({ ...filters, status_filter: e.target.value })}>
            <option value="">All statuses</option>
            <option value="PRESENT">Present</option>
            <option value="ABSENT">Absent</option>
            <option value="LEAVE">Leave</option>
          </select>
          <input type="date" value={filters.date_from} onChange={(e) => setFilters({ ...filters, date_from: e.target.value })} />
          <input type="date" value={filters.date_to} onChange={(e) => setFilters({ ...filters, date_to: e.target.value })} />
        </div>

        {recordsLoading ? (
          <div className="empty-state">Loading...</div>
        ) : records.length === 0 ? (
          <div className="empty-state">No attendance records match these filters.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Student</th>
                <th>Activity</th>
                <th>Coach</th>
                <th>Status</th>
                <th>Marked</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {records.map((r) => (
                <tr key={r.id}>
                  <td>{r.class_date}</td>
                  <td>{r.student_name}</td>
                  <td>{r.activity_name}</td>
                  <td>{r.coach_name || "-"}</td>
                  <td>
                    <StatusBadge status={r.status} />
                  </td>
                  <td>{r.marked_manually ? "Manual" : "Coach"}</td>
                  <td>
                    <button className="btn btn-secondary" style={{ marginRight: 6 }} onClick={() => openEdit(r)}>
                      Edit
                    </button>
                    <button className="btn btn-danger" onClick={() => remove(r)}>
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {editing && (
        <Modal title={`Edit Attendance — ${editing.student_name}`} onClose={() => setEditing(null)}>
          <form onSubmit={submitEdit}>
            <div className="field">
              <label>Status</label>
              <select value={editStatus} onChange={(e) => setEditStatus(e.target.value)}>
                <option value="PRESENT">Present</option>
                <option value="ABSENT">Absent</option>
                <option value="LEAVE">Leave</option>
              </select>
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
