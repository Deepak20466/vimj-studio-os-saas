import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { AttendanceAPI, ActivitiesAPI, StudentsAPI, CoachesAPI } from "../api/endpoints";
import StatusBadge from "../components/StatusBadge";
import Modal from "../components/Modal";

const todayStr = () => new Date().toISOString().slice(0, 10);

export default function Attendance() {
  const [missing, setMissing] = useState([]);
  const [missingLoading, setMissingLoading] = useState(true);
  const [activities, setActivities] = useState([]);
  const [coaches, setCoaches] = useState([]);

  const [records, setRecords] = useState([]);
  const [recordsLoading, setRecordsLoading] = useState(true);
  const [filters, setFilters] = useState({ activity_id: "", status_filter: "", approval_status: "", date_from: "", date_to: "" });

  const [manualForm, setManualForm] = useState({ activity_id: "", student_id: "", class_id: "", status: "PRESENT" });
  const [classes, setClasses] = useState([]);
  const [roster, setRoster] = useState([]);

  const [editing, setEditing] = useState(null); // record being edited
  const [editStatus, setEditStatus] = useState("PRESENT");

  const [selfieFor, setSelfieFor] = useState(null); // record whose selfie is shown
  const [selfieUrl, setSelfieUrl] = useState(null);
  const [selfieLoading, setSelfieLoading] = useState(false);
  const [approvalBusyId, setApprovalBusyId] = useState(null);

  // --- Coach attendance (separate CRUD) ---
  const [coachRecords, setCoachRecords] = useState([]);
  const [coachRecordsLoading, setCoachRecordsLoading] = useState(true);
  const [coachFilters, setCoachFilters] = useState({ coach_id: "", date_from: "", date_to: "" });
  const [coachManualForm, setCoachManualForm] = useState({ coach_id: "", date: todayStr(), entry_time: "", exit_time: "", status: "PRESENT" });
  const [editingCoach, setEditingCoach] = useState(null);
  const [editCoachForm, setEditCoachForm] = useState({ entry_time: "", exit_time: "", status: "PRESENT" });

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
    if (filters.approval_status) params.approval_status = filters.approval_status;
    if (filters.date_from) params.date_from = filters.date_from;
    if (filters.date_to) params.date_to = filters.date_to;
    AttendanceAPI.list(params)
      .then((r) => setRecords(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load attendance records"))
      .finally(() => setRecordsLoading(false));
  };

  const loadCoachRecords = () => {
    setCoachRecordsLoading(true);
    const params = {};
    if (coachFilters.coach_id) params.coach_id = Number(coachFilters.coach_id);
    if (coachFilters.date_from) params.date_from = coachFilters.date_from;
    if (coachFilters.date_to) params.date_to = coachFilters.date_to;
    AttendanceAPI.coachList(params)
      .then((r) => setCoachRecords(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load coach attendance records"))
      .finally(() => setCoachRecordsLoading(false));
  };

  useEffect(() => {
    loadMissing();
    ActivitiesAPI.list().then((r) => setActivities(r.data));
    CoachesAPI.list().then((r) => setCoaches(r.data));
  }, []);

  useEffect(() => {
    const t = setTimeout(loadRecords, 200);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filters]);

  useEffect(() => {
    const t = setTimeout(loadCoachRecords, 200);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [coachFilters]);

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
      if (err.response?.status === 404) {
        // Already gone (deleted elsewhere, or a duplicate click raced this same
        // request) — refresh instead of leaving a stale row with a dead-end error.
        toast("Already deleted — refreshing list");
        loadRecords();
        loadMissing();
        return;
      }
      toast.error(err.response?.data?.detail || "Delete failed");
    }
  };

  const viewSelfie = async (r) => {
    setSelfieFor(r);
    setSelfieUrl(null);
    setSelfieLoading(true);
    try {
      const { data } = await AttendanceAPI.selfieBlob(r.id);
      setSelfieUrl(URL.createObjectURL(data));
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to load selfie");
    } finally {
      setSelfieLoading(false);
    }
  };

  const closeSelfie = () => {
    setSelfieFor(null);
    setSelfieUrl(null);
  };

  const decideApproval = async (r, approve) => {
    setApprovalBusyId(r.id);
    try {
      if (approve) {
        await AttendanceAPI.approve(r.id, null);
        toast.success("Attendance approved and locked");
      } else {
        const note = prompt("Reason for rejecting (optional):") || "";
        await AttendanceAPI.reject(r.id, note);
        toast.success("Attendance rejected and locked");
      }
      loadRecords();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Action failed");
    } finally {
      setApprovalBusyId(null);
    }
  };

  const coachName = (id) => coaches.find((c) => c.id === id)?.name || (id ? `#${id}` : "-");

  const submitCoachManual = async (e) => {
    e.preventDefault();
    try {
      await AttendanceAPI.coachCreateManual({
        coach_id: Number(coachManualForm.coach_id),
        date: coachManualForm.date,
        entry_time: coachManualForm.entry_time || null,
        exit_time: coachManualForm.exit_time || null,
        status: coachManualForm.status,
      });
      toast.success("Coach attendance recorded");
      setCoachManualForm({ ...coachManualForm, coach_id: "", entry_time: "", exit_time: "" });
      loadCoachRecords();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to record coach attendance");
    }
  };

  const openEditCoach = (r) => {
    setEditingCoach(r);
    setEditCoachForm({
      entry_time: r.entry_time ? r.entry_time.slice(11, 16) : "",
      exit_time: r.exit_time ? r.exit_time.slice(11, 16) : "",
      status: r.status,
    });
  };

  const submitEditCoach = async (e) => {
    e.preventDefault();
    try {
      await AttendanceAPI.coachUpdate(editingCoach.id, {
        entry_time: editCoachForm.entry_time || null,
        exit_time: editCoachForm.exit_time || null,
        status: editCoachForm.status,
      });
      toast.success("Coach attendance updated");
      setEditingCoach(null);
      loadCoachRecords();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Update failed");
    }
  };

  const removeCoachRecord = async (r) => {
    if (!confirm(`Delete this attendance record for ${coachName(r.coach_id)} on ${r.date}?`)) return;
    try {
      await AttendanceAPI.coachRemove(r.id);
      toast.success("Coach attendance record deleted");
      loadCoachRecords();
    } catch (err) {
      if (err.response?.status === 404) {
        toast("Already deleted — refreshing list");
        loadCoachRecords();
        return;
      }
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

      <h2 style={{ marginBottom: 8 }}>Student Attendance</h2>

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

      <div className="card" style={{ marginBottom: 24 }}>
        <h3 style={{ marginTop: 0 }}>All Student Attendance Records</h3>
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
          <select value={filters.approval_status} onChange={(e) => setFilters({ ...filters, approval_status: e.target.value })}>
            <option value="">All review states</option>
            <option value="PENDING">Awaiting Admin Review</option>
            <option value="APPROVED">Approved</option>
            <option value="REJECTED">Rejected</option>
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
                <th>Admin Review</th>
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
                    <span
                      className={`badge ${r.approval_status === "APPROVED" ? "badge-paid" : r.approval_status === "REJECTED" ? "badge-overdue" : "badge-unpaid"}`}
                    >
                      {r.approval_status}
                    </span>
                  </td>
                  <td className="table-actions" style={{ flexWrap: "wrap" }}>
                    {r.has_selfie && (
                      <button className="btn btn-secondary btn-sm" onClick={() => viewSelfie(r)}>
                        View Selfie
                      </button>
                    )}
                    {r.approval_status === "PENDING" && !r.marked_manually && (
                      <>
                        <button
                          className="btn btn-primary btn-sm"
                          disabled={approvalBusyId === r.id}
                          onClick={() => decideApproval(r, true)}
                        >
                          Approve
                        </button>
                        <button
                          className="btn btn-danger btn-sm"
                          disabled={approvalBusyId === r.id}
                          onClick={() => decideApproval(r, false)}
                        >
                          Reject
                        </button>
                      </>
                    )}
                    <button className="btn btn-secondary btn-sm" onClick={() => openEdit(r)}>
                      Edit
                    </button>
                    <button className="btn btn-danger btn-sm" onClick={() => remove(r)}>
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <h2 style={{ marginBottom: 8 }}>Coach Attendance</h2>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Manual Facility Attendance Entry (Admin)</h3>
        <p style={{ color: "var(--text-muted)", fontSize: "0.85rem", marginTop: -8 }}>
          Record or backfill a coach's facility entry/exit directly — bypasses geofencing.
        </p>
        <form onSubmit={submitCoachManual} className="form-grid">
          <div>
            <label>Coach</label>
            <select value={coachManualForm.coach_id} onChange={(e) => setCoachManualForm({ ...coachManualForm, coach_id: e.target.value })} required>
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
            <input type="date" value={coachManualForm.date} onChange={(e) => setCoachManualForm({ ...coachManualForm, date: e.target.value })} required />
          </div>
          <div>
            <label>Entry Time</label>
            <input type="time" value={coachManualForm.entry_time} onChange={(e) => setCoachManualForm({ ...coachManualForm, entry_time: e.target.value })} />
          </div>
          <div>
            <label>Exit Time</label>
            <input type="time" value={coachManualForm.exit_time} onChange={(e) => setCoachManualForm({ ...coachManualForm, exit_time: e.target.value })} />
          </div>
          <div>
            <label>Status</label>
            <select value={coachManualForm.status} onChange={(e) => setCoachManualForm({ ...coachManualForm, status: e.target.value })}>
              <option value="PRESENT">Present</option>
              <option value="ABSENT">Absent</option>
              <option value="LEAVE">Leave</option>
              <option value="INCOMPLETE">Incomplete</option>
            </select>
          </div>
          <div style={{ alignSelf: "end" }}>
            <button className="btn btn-primary">Record</button>
          </div>
        </form>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>All Coach Attendance Records</h3>
        <div className="toolbar" style={{ marginBottom: 12 }}>
          <select value={coachFilters.coach_id} onChange={(e) => setCoachFilters({ ...coachFilters, coach_id: e.target.value })}>
            <option value="">All coaches</option>
            {coaches.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
          <input type="date" value={coachFilters.date_from} onChange={(e) => setCoachFilters({ ...coachFilters, date_from: e.target.value })} />
          <input type="date" value={coachFilters.date_to} onChange={(e) => setCoachFilters({ ...coachFilters, date_to: e.target.value })} />
        </div>

        {coachRecordsLoading ? (
          <div className="empty-state">Loading...</div>
        ) : coachRecords.length === 0 ? (
          <div className="empty-state">No coach attendance records match these filters.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Coach</th>
                <th>Entry</th>
                <th>Exit</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {coachRecords.map((r) => (
                <tr key={r.id}>
                  <td>{r.date}</td>
                  <td>{r.coach_name}</td>
                  <td>{r.entry_time ? r.entry_time.slice(11, 16) : "-"}</td>
                  <td>{r.exit_time ? r.exit_time.slice(11, 16) : "-"}</td>
                  <td>
                    <StatusBadge status={r.status} />
                  </td>
                  <td className="table-actions">
                    <button className="btn btn-secondary btn-sm" onClick={() => openEditCoach(r)}>
                      Edit
                    </button>
                    <button className="btn btn-danger btn-sm" onClick={() => removeCoachRecord(r)}>
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

      {editingCoach && (
        <Modal title={`Edit Coach Attendance — ${coachName(editingCoach.coach_id)}`} onClose={() => setEditingCoach(null)}>
          <form onSubmit={submitEditCoach}>
            <div className="form-grid">
              <div>
                <label>Entry Time</label>
                <input type="time" value={editCoachForm.entry_time} onChange={(e) => setEditCoachForm({ ...editCoachForm, entry_time: e.target.value })} />
              </div>
              <div>
                <label>Exit Time</label>
                <input type="time" value={editCoachForm.exit_time} onChange={(e) => setEditCoachForm({ ...editCoachForm, exit_time: e.target.value })} />
              </div>
            </div>
            <div className="field">
              <label>Status</label>
              <select value={editCoachForm.status} onChange={(e) => setEditCoachForm({ ...editCoachForm, status: e.target.value })}>
                <option value="PRESENT">Present</option>
                <option value="ABSENT">Absent</option>
                <option value="LEAVE">Leave</option>
                <option value="INCOMPLETE">Incomplete</option>
              </select>
            </div>
            <div className="modal-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setEditingCoach(null)}>
                Cancel
              </button>
              <button className="btn btn-primary">Save</button>
            </div>
          </form>
        </Modal>
      )}

      {selfieFor && (
        <Modal title={`Selfie — ${selfieFor.student_name}`} onClose={closeSelfie}>
          {selfieLoading ? (
            <div className="empty-state">Loading...</div>
          ) : selfieUrl ? (
            <img src={selfieUrl} alt={`${selfieFor.student_name} selfie`} style={{ width: "100%", maxWidth: 360, display: "block", margin: "0 auto", borderRadius: 8 }} />
          ) : (
            <div className="empty-state">Selfie not available.</div>
          )}
        </Modal>
      )}
    </div>
  );
}
