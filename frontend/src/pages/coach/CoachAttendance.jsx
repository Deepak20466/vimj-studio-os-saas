import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { useAuth } from "../../context/AuthContext";
import { CoachSelfAPI, AttendanceAPI } from "../../api/endpoints";
import StatusBadge from "../../components/StatusBadge";
import Modal from "../../components/Modal";

function todayStr() {
  return new Date().toISOString().slice(0, 10);
}

export default function CoachAttendance() {
  const { user } = useAuth();
  const [records, setRecords] = useState([]);
  const [loading, setLoading] = useState(true);
  const [dateFrom, setDateFrom] = useState(todayStr());
  const [dateTo, setDateTo] = useState(todayStr());
  const [busyId, setBusyId] = useState(null);
  const [selfieUrl, setSelfieUrl] = useState(null);

  const [myAttendance, setMyAttendance] = useState([]);
  const [myAttendanceLoading, setMyAttendanceLoading] = useState(true);

  const load = () => {
    setLoading(true);
    CoachSelfAPI.myStudentAttendance({ date_from: dateFrom, date_to: dateTo })
      .then((r) => setRecords(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load attendance"))
      .finally(() => setLoading(false));
  };

  useEffect(load, [dateFrom, dateTo]);

  useEffect(() => {
    setMyAttendanceLoading(true);
    CoachSelfAPI.myAttendance(user.id)
      .then((r) => setMyAttendance(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load your facility attendance"))
      .finally(() => setMyAttendanceLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const canEdit = (r) => String(r.class_date).slice(0, 10) === todayStr() && r.approval_status === "PENDING";

  const changeStatus = async (record, status) => {
    setBusyId(record.id);
    try {
      await CoachSelfAPI.updateStudentAttendance(record.id, { status });
      toast.success("Attendance updated");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Update failed");
    } finally {
      setBusyId(null);
    }
  };

  const remove = async (record) => {
    if (!confirm(`Remove the attendance record for ${record.student_name}?`)) return;
    setBusyId(record.id);
    try {
      await CoachSelfAPI.deleteStudentAttendance(record.id);
      toast.success("Attendance record deleted");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Delete failed");
    } finally {
      setBusyId(null);
    }
  };

  const viewSelfie = async (record) => {
    try {
      const { data } = await AttendanceAPI.selfieBlob(record.id);
      setSelfieUrl(URL.createObjectURL(data));
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to load selfie");
    }
  };

  const approvalBadge = (status) => {
    const cls = status === "APPROVED" ? "badge-paid" : status === "REJECTED" ? "badge-overdue" : "badge-unpaid";
    return <span className={`badge ${cls}`}>{status === "PENDING" ? "Awaiting Admin" : status}</span>;
  };

  return (
    <div>
      <div className="page-header">
        <h1>Attendance</h1>
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>My Facility Attendance</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -8 }}>
          Your own geofenced check-in/check-out history. This is an audit trail set only by Check In / Check Out on
          your Dashboard — it can't be edited here.
        </p>
        {myAttendanceLoading ? (
          <div className="empty-state">Loading...</div>
        ) : myAttendance.length === 0 ? (
          <div className="empty-state">No facility attendance recorded yet.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Entry</th>
                <th>Exit</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {myAttendance.map((a) => (
                <tr key={a.id}>
                  <td>{a.date}</td>
                  <td>{a.entry_time ? new Date(a.entry_time).toLocaleTimeString() : "-"}</td>
                  <td>{a.exit_time ? new Date(a.exit_time).toLocaleTimeString() : "-"}</td>
                  <td>
                    <StatusBadge status={a.status} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="page-header">
        <h1>Student Attendance</h1>
      </div>
      <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -12 }}>
        Once admin approves or rejects a record you marked, it locks and can no longer be changed from here.
      </p>

      <div className="card">
        <div className="toolbar" style={{ marginBottom: 12, display: "flex", gap: 12, alignItems: "center" }}>
          <div className="field" style={{ margin: 0 }}>
            <label>From</label>
            <input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
          </div>
          <div className="field" style={{ margin: 0 }}>
            <label>To</label>
            <input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
          </div>
        </div>

        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : records.length === 0 ? (
          <div className="empty-state">No attendance records marked in this range.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Student</th>
                <th>Activity</th>
                <th>Class Date</th>
                <th>Status</th>
                <th>Admin Review</th>
                <th>Marked At</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {records.map((r) => (
                <tr key={r.id}>
                  <td>{r.student_name}</td>
                  <td>{r.activity_name}</td>
                  <td>{r.class_date}</td>
                  <td>
                    <StatusBadge status={r.status} />
                  </td>
                  <td>{approvalBadge(r.approval_status)}</td>
                  <td>{new Date(r.timestamp).toLocaleString()}</td>
                  <td>
                    <div className="table-actions" style={{ flexWrap: "wrap" }}>
                      {r.has_selfie && (
                        <button className="btn btn-secondary btn-sm" onClick={() => viewSelfie(r)}>
                          View Photo
                        </button>
                      )}
                      {canEdit(r) ? (
                        <>
                          {["PRESENT", "ABSENT", "LEAVE"].filter((s) => s !== r.status).map((s) => (
                            <button
                              key={s}
                              className="btn btn-secondary btn-sm"
                              disabled={busyId === r.id}
                              onClick={() => changeStatus(r, s)}
                            >
                              Mark {s.charAt(0) + s.slice(1).toLowerCase()}
                            </button>
                          ))}
                          <button className="btn btn-danger btn-sm" disabled={busyId === r.id} onClick={() => remove(r)}>
                            Delete
                          </button>
                        </>
                      ) : (
                        <span style={{ fontSize: "0.8rem", color: "var(--text-muted)" }}>
                          {r.approval_status === "PENDING" ? "Locked (past class)" : "Locked (reviewed by admin)"}
                        </span>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {selfieUrl && (
        <Modal title="Attendance Photo" onClose={() => setSelfieUrl(null)}>
          <img src={selfieUrl} alt="Attendance selfie" style={{ width: "100%", borderRadius: 8 }} />
        </Modal>
      )}
    </div>
  );
}
