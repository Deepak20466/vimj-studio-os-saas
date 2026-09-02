import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { AttendanceAPI, ActivitiesAPI, StudentsAPI } from "../api/endpoints";

export default function Attendance() {
  const [missing, setMissing] = useState([]);
  const [loading, setLoading] = useState(true);
  const [activities, setActivities] = useState([]);
  const [manualForm, setManualForm] = useState({ activity_id: "", student_id: "", class_id: "", status: "PRESENT" });
  const [classes, setClasses] = useState([]);
  const [roster, setRoster] = useState([]);

  const loadMissing = () => {
    setLoading(true);
    AttendanceAPI.dailyMissing()
      .then((r) => setMissing(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load"))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    loadMissing();
    ActivitiesAPI.list().then((r) => setActivities(r.data));
  }, []);

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
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to mark attendance");
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>Attendance</h1>
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Coaches Missing Attendance (Today)</h3>
        {loading ? (
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

      <div className="card">
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
    </div>
  );
}
