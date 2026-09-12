import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { useAuth } from "../../context/AuthContext";
import { CoachSelfAPI, ActivitiesAPI } from "../../api/endpoints";

const POLL_MS = 30000;
const STATUS_LABELS = { PRESENT: "Present", ABSENT: "Absent", NOT_CONFIRM: "Not Confirm" };

function todayStr() {
  return new Date().toISOString().slice(0, 10);
}

export default function CoachDashboard() {
  const { user } = useAuth();
  const [classes, setClasses] = useState([]);
  const [activityNames, setActivityNames] = useState({});
  const [summaries, setSummaries] = useState({}); // class_id -> {enrolled_count, marked_count, fee_paid_count, fee_unpaid_count}
  const [todayAttendance, setTodayAttendance] = useState(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [pendingStatus, setPendingStatus] = useState(null);

  const load = (silent) => {
    if (!silent) setLoading(true);
    Promise.all([CoachSelfAPI.myClasses(todayStr()), CoachSelfAPI.myAttendance(user.id), ActivitiesAPI.list()])
      .then(([classesRes, attendanceRes, activitiesRes]) => {
        setClasses(classesRes.data);
        const today = attendanceRes.data.find((a) => String(a.date).slice(0, 10) === todayStr());
        setTodayAttendance(today || null);
        setActivityNames(Object.fromEntries(activitiesRes.data.map((a) => [a.id, a.name])));
        Promise.all(classesRes.data.map((c) => CoachSelfAPI.classSummary(c.id).then((r) => [c.id, r.data])))
          .then((pairs) => setSummaries(Object.fromEntries(pairs)))
          .catch(() => {});
      })
      .catch((err) => {
        if (!silent) toast.error(err.response?.data?.detail || "Failed to load dashboard");
      })
      .finally(() => {
        if (!silent) setLoading(false);
      });
  };

  useEffect(() => {
    load(false);
    // Admin-scheduled classes and reassignments should show up here without a manual refresh.
    const interval = setInterval(() => load(true), POLL_MS);
    return () => clearInterval(interval);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const submitMyAttendance = async () => {
    if (!pendingStatus) return;
    setBusy(true);
    try {
      await CoachSelfAPI.coachMark({ status: pendingStatus });
      toast.success(`Marked ${STATUS_LABELS[pendingStatus]} — submitted, awaiting admin`);
      setPendingStatus(null);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || err.message || "Failed to mark attendance");
    } finally {
      setBusy(false);
    }
  };

  if (loading) return <div className="empty-state">Loading...</div>;

  return (
    <div>
      <div className="page-header">
        <h1>Welcome, {user?.name}</h1>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>My Attendance Today</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -8 }}>
          Manual entry — no location needed. Pick a status below, change it as many times as you like, then press
          Submit to lock it in. Once submitted, only admin can correct it.
        </p>
        {todayAttendance ? (
          <div className="table-actions">
            <span className={`badge badge-${todayAttendance.status.toLowerCase()}`}>{STATUS_LABELS[todayAttendance.status] || todayAttendance.status}</span>
            <span style={{ fontSize: "0.85rem", color: "var(--text-muted)" }}>Marked for today — locked</span>
          </div>
        ) : (
          <div>
            <div className="table-actions" style={{ marginBottom: 10 }}>
              {Object.keys(STATUS_LABELS).map((st) => (
                <button
                  key={st}
                  className={pendingStatus === st ? "btn btn-primary" : "btn btn-secondary"}
                  disabled={busy}
                  onClick={() => setPendingStatus(st)}
                >
                  {STATUS_LABELS[st]}
                </button>
              ))}
            </div>
            <button className="btn btn-primary" disabled={busy || !pendingStatus} onClick={submitMyAttendance}>
              {busy ? "Submitting..." : "Submit"}
            </button>
            {pendingStatus && (
              <p style={{ fontSize: "0.8rem", color: "var(--text-muted)", margin: "8px 0 0" }}>
                Selected: {STATUS_LABELS[pendingStatus]} — change it above anytime before you press Submit.
              </p>
            )}
          </div>
        )}
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Today's Classes</h3>
        {classes.length === 0 ? (
          <div className="empty-state">No classes scheduled for you today.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Activity</th>
                <th>Start</th>
                <th>End</th>
                <th>Students</th>
                <th>Marked</th>
                <th>Fees Paid / Unpaid</th>
              </tr>
            </thead>
            <tbody>
              {classes.map((c) => {
                const s = summaries[c.id];
                return (
                  <tr key={c.id}>
                    <td>{activityNames[c.activity_id] || c.activity_id}</td>
                    <td>{c.start_time}</td>
                    <td>{c.end_time}</td>
                    <td>{s ? s.enrolled_count : "-"}</td>
                    <td>{s ? s.marked_count : "-"}</td>
                    <td>
                      {s ? (
                        <>
                          <span className="badge badge-paid">{s.fee_paid_count}</span>{" "}
                          <span className="badge badge-unpaid">{s.fee_unpaid_count}</span>
                        </>
                      ) : (
                        "-"
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
        <p style={{ marginTop: 12, fontSize: "0.85rem", color: "var(--text-muted)" }}>
          Go to the Classes tab to mark student attendance.
        </p>
      </div>
    </div>
  );
}
