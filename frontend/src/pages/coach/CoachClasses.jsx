import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { CoachSelfAPI, ActivitiesAPI, AttendanceAPI } from "../../api/endpoints";
import Modal from "../../components/Modal";

function todayStr() {
  return new Date().toISOString().slice(0, 10);
}

function classHasEnded(cls) {
  return new Date(`${cls.date}T${cls.end_time}`) < new Date();
}

const STATUS_LABELS = { PRESENT: "Present", ABSENT: "Absent", LEAVE: "Leave", NOT_CONFIRM: "Not Confirm" };

export default function CoachClasses() {
  const [date, setDate] = useState(todayStr());
  const [classes, setClasses] = useState([]);
  const [activityNames, setActivityNames] = useState({});
  const [loading, setLoading] = useState(true);
  const [rosterFor, setRosterFor] = useState(null); // class object
  const [roster, setRoster] = useState([]);
  const [rosterLoading, setRosterLoading] = useState(false);
  const [done, setDone] = useState({}); // studentId -> {status, id, approval_status, has_selfie}
  const [pending, setPending] = useState({}); // studentId -> status staged, not yet submitted
  const [markingId, setMarkingId] = useState(null);
  const [selfieUrl, setSelfieUrl] = useState(null);

  const load = () => {
    setLoading(true);
    Promise.all([CoachSelfAPI.myClasses(date), ActivitiesAPI.list()])
      .then(([classesRes, activitiesRes]) => {
        setClasses(classesRes.data);
        setActivityNames(Object.fromEntries(activitiesRes.data.map((a) => [a.id, a.name])));
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load classes"))
      .finally(() => setLoading(false));
  };

  useEffect(load, [date]);

  const openRoster = (cls) => {
    setRosterFor(cls);
    setDone({});
    setPending({});
    setRosterLoading(true);
    Promise.all([ActivitiesAPI.roster(cls.activity_id), CoachSelfAPI.myStudentAttendance({ class_id: cls.id })])
      .then(([rosterRes, attendanceRes]) => {
        setRoster(rosterRes.data);
        const existing = Object.fromEntries(
          attendanceRes.data.map((a) => [
            a.student_id,
            { status: a.status, id: a.id, approval_status: a.approval_status, has_selfie: a.has_selfie },
          ])
        );
        setDone(existing);
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load roster"))
      .finally(() => setRosterLoading(false));
  };

  const handleMark = async (studentId, status) => {
    setMarkingId(studentId);
    try {
      const { data } = await CoachSelfAPI.markAttendance({
        student_id: studentId,
        class_id: rosterFor.id,
        status,
      });
      toast.success(`Marked ${STATUS_LABELS[status]} — submitted, awaiting admin`);
      setDone((d) => ({
        ...d,
        [studentId]: { status, id: data.id, approval_status: data.approval_status, has_selfie: data.has_selfie },
      }));
      setPending((p) => {
        const next = { ...p };
        delete next[studentId];
        return next;
      });
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to mark attendance");
    } finally {
      setMarkingId(null);
    }
  };

  const selectPending = (studentId, status) => {
    setPending((p) => ({ ...p, [studentId]: status }));
  };

  const viewSelfie = async (record) => {
    try {
      const { data } = await AttendanceAPI.selfieBlob(record.id);
      setSelfieUrl(URL.createObjectURL(data));
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to load selfie");
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>My Classes</h1>
        <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
      </div>

      <div className="card">
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : classes.length === 0 ? (
          <div className="empty-state">No classes on this date.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Activity</th>
                <th>Start</th>
                <th>End</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {classes.map((c) => (
                <tr key={c.id}>
                  <td>{activityNames[c.activity_id] || c.activity_id}</td>
                  <td>{c.start_time}</td>
                  <td>{c.end_time}</td>
                  <td className="table-actions">
                    <button className="btn btn-primary btn-sm" onClick={() => openRoster(c)}>
                      Mark Attendance
                    </button>
                    {classHasEnded(c) && (
                      <span style={{ fontSize: "0.8rem", color: "var(--text-muted)" }}>Class ended</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {rosterFor && (
        <Modal title={`Mark Attendance — ${activityNames[rosterFor.activity_id] || ""}`} onClose={() => setRosterFor(null)}>
          <p style={{ fontSize: "0.82rem", color: "var(--text-muted)", marginTop: -8 }}>
            Manual entry — no location or photo needed. Pick a status, change it as many times as you like, then
            press Submit to lock it in. Once submitted, only admin can correct it.
          </p>
          {rosterLoading ? (
            <div className="empty-state">Loading roster...</div>
          ) : roster.length === 0 ? (
            <div className="empty-state">No students enrolled in this activity.</div>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>Student</th>
                  <th>Fee</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {roster.map((s) => (
                  <tr key={s.id}>
                    <td>{s.name}</td>
                    <td>
                      <span className={`badge ${s.fee_status === "PAID" ? "badge-paid" : s.fee_status === "OVERDUE" ? "badge-overdue" : "badge-unpaid"}`}>
                        {s.fee_status}
                      </span>
                    </td>
                    <td>
                      {done[s.id] ? (
                        <div className="table-actions" style={{ flexWrap: "wrap" }}>
                          <span className={`badge badge-${done[s.id].status.toLowerCase()}`}>{STATUS_LABELS[done[s.id].status]}</span>
                          <span
                            className={`badge ${done[s.id].approval_status === "APPROVED" ? "badge-paid" : done[s.id].approval_status === "REJECTED" ? "badge-overdue" : "badge-unpaid"}`}
                            title="Admin review status"
                          >
                            {done[s.id].approval_status === "PENDING" ? "Awaiting Admin" : done[s.id].approval_status}
                          </span>
                          {done[s.id].has_selfie && (
                            <button className="btn btn-secondary btn-sm" onClick={() => viewSelfie(done[s.id])}>
                              View Photo
                            </button>
                          )}
                          <span style={{ fontSize: "0.8rem", color: "var(--text-muted)" }}>Locked</span>
                        </div>
                      ) : (
                        <div className="table-actions" style={{ flexWrap: "wrap" }}>
                          {Object.keys(STATUS_LABELS).map((st) => (
                            <button
                              key={st}
                              className={pending[s.id] === st ? "btn btn-primary btn-sm" : "btn btn-secondary btn-sm"}
                              disabled={markingId === s.id}
                              onClick={() => selectPending(s.id, st)}
                            >
                              {STATUS_LABELS[st]}
                            </button>
                          ))}
                          <button
                            className="btn btn-primary btn-sm"
                            disabled={!pending[s.id] || markingId === s.id}
                            onClick={() => handleMark(s.id, pending[s.id])}
                          >
                            {markingId === s.id ? "Submitting..." : "Submit"}
                          </button>
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Modal>
      )}

      {selfieUrl && (
        <Modal title="Attendance Photo" onClose={() => setSelfieUrl(null)}>
          <img src={selfieUrl} alt="Attendance selfie" style={{ width: "100%", borderRadius: 8 }} />
        </Modal>
      )}
    </div>
  );
}
