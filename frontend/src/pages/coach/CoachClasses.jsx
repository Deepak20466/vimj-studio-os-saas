import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { CoachSelfAPI, ActivitiesAPI, ComplianceAPI } from "../../api/endpoints";
import { getCurrentPosition } from "../../utils/geo";
import Modal from "../../components/Modal";
import SelfieCapture from "../../components/SelfieCapture";

function todayStr() {
  return new Date().toISOString().slice(0, 10);
}

const LATE_MARK_MINUTES = 10;

function classHasEnded(cls) {
  return new Date(`${cls.date}T${cls.end_time}`) < new Date();
}

function isLikelyLate(cls) {
  const end = new Date(`${cls.date}T${cls.end_time}`);
  return new Date() > new Date(end.getTime() + LATE_MARK_MINUTES * 60000);
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
  const [lateReason, setLateReason] = useState("");
  const [skipReasonFor, setSkipReasonFor] = useState(null); // class object
  const [skipReasonText, setSkipReasonText] = useState("");
  const [photoFor, setPhotoFor] = useState(null); // class object
  const [photosByClass, setPhotosByClass] = useState({}); // classId -> [blobUrl, ...]

  const load = () => {
    setLoading(true);
    Promise.all([CoachSelfAPI.myClasses(date), ActivitiesAPI.list()])
      .then(([classesRes, activitiesRes]) => {
        setClasses(classesRes.data);
        setActivityNames(Object.fromEntries(activitiesRes.data.map((a) => [a.id, a.name])));
        classesRes.data.filter(classHasEnded).forEach((c) => loadClassPhotos(c.id));
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load classes"))
      .finally(() => setLoading(false));
  };

  useEffect(load, [date]);

  const loadClassPhotos = async (classId) => {
    try {
      const { data: photos } = await ComplianceAPI.classPhotos(classId);
      const blobs = await Promise.all(photos.map((p) => ComplianceAPI.classPhotoBlob(p.id)));
      setPhotosByClass((prev) => ({ ...prev, [classId]: blobs.map((b) => URL.createObjectURL(b.data)) }));
    } catch {
      // non-fatal — the Batch Photo button still works without a preview
    }
  };

  const openRoster = (cls) => {
    setRosterFor(cls);
    setDone({});
    setLateReason("");
    setRosterLoading(true);
    Promise.all([ActivitiesAPI.roster(cls.activity_id), CoachSelfAPI.myStudentAttendance({ class_id: cls.id })])
      .then(([rosterRes, attendanceRes]) => {
        setRoster(rosterRes.data);
        const existing = Object.fromEntries(
          attendanceRes.data.map((a) => [a.student_id, { status: a.status, id: a.id }])
        );
        setDone(existing);
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load roster"))
      .finally(() => setRosterLoading(false));
  };

  const submitAttendance = async (studentId, status, selfieBase64) => {
    setMarkingId(studentId);
    try {
      const { lat, lng } = await getCurrentPosition();
      const { data } = await CoachSelfAPI.markAttendance({
        student_id: studentId,
        class_id: rosterFor.id,
        status,
        location_lat: lat,
        location_lng: lng,
        selfie_base64: selfieBase64 || undefined,
        late_reason: isLikelyLate(rosterFor) ? lateReason || undefined : undefined,
      });
      toast.success(`Marked ${status.toLowerCase()}`);
      setDone((d) => ({ ...d, [studentId]: { status, id: data.id } }));
    } catch (err) {
      toast.error(err.response?.data?.detail || err.message || "Failed to mark attendance");
    } finally {
      setMarkingId(null);
    }
  };

  const editAttendance = async (studentId, newStatus) => {
    const record = done[studentId];
    if (!record) return;
    setMarkingId(studentId);
    try {
      await CoachSelfAPI.updateStudentAttendance(record.id, { status: newStatus });
      toast.success(`Updated to ${newStatus.toLowerCase()}`);
      setDone((d) => ({ ...d, [studentId]: { ...record, status: newStatus } }));
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to update attendance");
    } finally {
      setMarkingId(null);
    }
  };

  const deleteAttendance = async (studentId) => {
    const record = done[studentId];
    if (!record) return;
    if (!confirm("Delete this attendance record?")) return;
    setMarkingId(studentId);
    try {
      await CoachSelfAPI.deleteStudentAttendance(record.id);
      toast.success("Attendance record deleted");
      setDone((d) => {
        const next = { ...d };
        delete next[studentId];
        return next;
      });
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to delete attendance");
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

  const openSkipReason = (cls) => {
    setSkipReasonFor(cls);
    setSkipReasonText("");
  };

  const submitSkipReason = async (e) => {
    e.preventDefault();
    try {
      await ComplianceAPI.classNotConducted(skipReasonFor.id, skipReasonText);
      toast.success("Reported to admin");
      setSkipReasonFor(null);
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to submit reason");
    }
  };

  const capturePhoto = async (base64) => {
    const classId = photoFor.id;
    try {
      await ComplianceAPI.uploadClassPhoto(classId, base64);
      toast.success("Photo saved");
      loadClassPhotos(classId);
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to save photo");
    } finally {
      setPhotoFor(null);
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
                      <>
                        <button className="btn btn-secondary btn-sm" onClick={() => setPhotoFor(c)}>
                          Batch Photo
                        </button>
                        <button className="btn btn-danger btn-sm" onClick={() => openSkipReason(c)}>
                          Not Conducted
                        </button>
                        {photosByClass[c.id]?.length > 0 && (
                          <span style={{ display: "inline-flex", gap: 4, verticalAlign: "middle" }}>
                            {photosByClass[c.id].map((url, i) => (
                              <img key={i} src={url} alt="Batch" style={{ width: 32, height: 32, objectFit: "cover", borderRadius: 6 }} />
                            ))}
                          </span>
                        )}
                      </>
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
          {isLikelyLate(rosterFor) && (
            <div className="field">
              <label>This class ended over {LATE_MARK_MINUTES} min ago — reason for late attendance</label>
              <textarea rows={2} value={lateReason} onChange={(e) => setLateReason(e.target.value)} placeholder="e.g. traffic delay, facility access issue..." />
            </div>
          )}
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
                        <div className="table-actions">
                          <span className={`badge badge-${done[s.id].status.toLowerCase()}`}>{done[s.id].status}</span>
                          <select
                            value={done[s.id].status}
                            disabled={markingId === s.id}
                            onChange={(e) => editAttendance(s.id, e.target.value)}
                            style={{ width: "auto", padding: "4px 8px" }}
                          >
                            <option value="PRESENT">Present</option>
                            <option value="ABSENT">Absent</option>
                            <option value="LEAVE">Leave</option>
                          </select>
                          <button className="btn btn-danger btn-sm" disabled={markingId === s.id} onClick={() => deleteAttendance(s.id)}>
                            Delete
                          </button>
                        </div>
                      ) : (
                        <div className="table-actions">
                          <button
                            className="btn btn-primary btn-sm"
                            disabled={markingId === s.id}
                            onClick={() => handleMark(s, "PRESENT")}
                          >
                            Present
                          </button>
                          <button
                            className="btn btn-secondary btn-sm"
                            disabled={markingId === s.id}
                            onClick={() => handleMark(s, "ABSENT")}
                          >
                            Absent
                          </button>
                          <button
                            className="btn btn-secondary btn-sm"
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

      {skipReasonFor && (
        <Modal title="Class Not Conducted" onClose={() => setSkipReasonFor(null)}>
          <form onSubmit={submitSkipReason}>
            <div className="field">
              <label>Reason</label>
              <textarea rows={3} value={skipReasonText} onChange={(e) => setSkipReasonText(e.target.value)} required />
            </div>
            <div className="modal-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setSkipReasonFor(null)}>
                Cancel
              </button>
              <button className="btn btn-primary">Report to Admin</button>
            </div>
          </form>
        </Modal>
      )}

      {photoFor && (
        <SelfieCapture
          title={`Batch Photo — ${activityNames[photoFor.activity_id] || ""}`}
          onClose={() => setPhotoFor(null)}
          onCapture={capturePhoto}
        />
      )}
    </div>
  );
}
