import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { CoachSelfAPI, ActivitiesAPI } from "../../api/endpoints";
import { getCurrentPosition } from "../../utils/geo";
import Modal from "../../components/Modal";
import SelfieCapture from "../../components/SelfieCapture";

function todayStr() {
  return new Date().toISOString().slice(0, 10);
}

export default function CoachClasses() {
  const [date, setDate] = useState(todayStr());
  const [classes, setClasses] = useState([]);
  const [activityNames, setActivityNames] = useState({});
  const [loading, setLoading] = useState(true);
  const [rosterFor, setRosterFor] = useState(null); // class object
  const [roster, setRoster] = useState([]);
  const [rosterLoading, setRosterLoading] = useState(false);
  const [done, setDone] = useState({}); // studentId -> status marked this session
  const [pendingPresent, setPendingPresent] = useState(null); // student object awaiting selfie
  const [markingId, setMarkingId] = useState(null);

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
    setRosterLoading(true);
    ActivitiesAPI.roster(cls.activity_id)
      .then((r) => setRoster(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load roster"))
      .finally(() => setRosterLoading(false));
  };

  const submitAttendance = async (studentId, status, selfieBase64) => {
    setMarkingId(studentId);
    try {
      const { lat, lng } = await getCurrentPosition();
      await CoachSelfAPI.markAttendance({
        student_id: studentId,
        class_id: rosterFor.id,
        status,
        location_lat: lat,
        location_lng: lng,
        selfie_base64: selfieBase64 || undefined,
      });
      toast.success(`Marked ${status.toLowerCase()}`);
      setDone((d) => ({ ...d, [studentId]: status }));
    } catch (err) {
      toast.error(err.response?.data?.detail || err.message || "Failed to mark attendance");
    } finally {
      setMarkingId(null);
    }
  };

  const handleMark = (student, status) => {
    if (status === "PRESENT") {
      setPendingPresent(student);
      return;
    }
    submitAttendance(student.id, status);
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
                  <td>
                    <button className="btn btn-primary" onClick={() => openRoster(c)}>
                      Mark Attendance
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {rosterFor && (
        <Modal title={`Mark Attendance — ${activityNames[rosterFor.activity_id] || ""}`} onClose={() => setRosterFor(null)}>
          {rosterLoading ? (
            <div className="empty-state">Loading roster...</div>
          ) : roster.length === 0 ? (
            <div className="empty-state">No students enrolled in this activity.</div>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>Student</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {roster.map((s) => (
                  <tr key={s.id}>
                    <td>{s.name}</td>
                    <td>
                      {done[s.id] ? (
                        <span className={`badge badge-${done[s.id].toLowerCase()}`}>{done[s.id]}</span>
                      ) : (
                        <div style={{ display: "flex", gap: 6 }}>
                          <button
                            className="btn btn-primary"
                            disabled={markingId === s.id}
                            onClick={() => handleMark(s, "PRESENT")}
                          >
                            Present
                          </button>
                          <button
                            className="btn btn-secondary"
                            disabled={markingId === s.id}
                            onClick={() => handleMark(s, "ABSENT")}
                          >
                            Absent
                          </button>
                          <button
                            className="btn btn-secondary"
                            disabled={markingId === s.id}
                            onClick={() => handleMark(s, "LEAVE")}
                          >
                            Leave
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

      {pendingPresent && (
        <SelfieCapture
          onClose={() => setPendingPresent(null)}
          onCapture={(base64) => {
            const student = pendingPresent;
            setPendingPresent(null);
            submitAttendance(student.id, "PRESENT", base64);
          }}
        />
      )}
    </div>
  );
}
