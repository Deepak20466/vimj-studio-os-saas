import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { useAuth } from "../../context/AuthContext";
import { CoachSelfAPI, ActivitiesAPI } from "../../api/endpoints";
import { getCurrentPosition } from "../../utils/geo";

const POLL_MS = 30000;

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

  const checkIn = async () => {
    setBusy(true);
    try {
      const { lat, lng } = await getCurrentPosition();
      await CoachSelfAPI.coachEntry({ location_lat: lat, location_lng: lng });
      toast.success("Checked in");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || err.message || "Check-in failed");
    } finally {
      setBusy(false);
    }
  };

  const checkOut = async () => {
    setBusy(true);
    try {
      const { lat, lng } = await getCurrentPosition();
      await CoachSelfAPI.coachExit({ location_lat: lat, location_lng: lng });
      toast.success("Checked out");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || err.message || "Check-out failed");
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
        <h3 style={{ marginTop: 0 }}>Facility Check-in</h3>
        {todayAttendance?.exit_time ? (
          <div className="empty-state">You've completed check-in and check-out for today.</div>
        ) : todayAttendance?.entry_time ? (
          <>
            <p>Checked in at {new Date(todayAttendance.entry_time).toLocaleTimeString()}.</p>
            <button className="btn btn-primary" disabled={busy} onClick={checkOut}>
              {busy ? "Working..." : "Check Out"}
            </button>
          </>
        ) : (
          <button className="btn btn-primary" disabled={busy} onClick={checkIn}>
            {busy ? "Working..." : "Check In"}
          </button>
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
