import { useEffect, useMemo, useState } from "react";
import toast from "react-hot-toast";
import { addMonths, eachDayOfInterval, endOfMonth, format, getDay, isToday, startOfMonth, subMonths } from "date-fns";
import { useAuth } from "../../context/AuthContext";
import { CoachSelfAPI, AttendanceAPI } from "../../api/endpoints";
import StatusBadge from "../../components/StatusBadge";
import Modal from "../../components/Modal";

const FACILITY_DOT_COLOR = { PRESENT: "var(--success)", ABSENT: "var(--danger)", NOT_CONFIRM: "var(--info)" };
const STUDENT_DOT_COLOR = { PRESENT: "var(--success)", ABSENT: "var(--danger)", LEAVE: "var(--warning)", NOT_CONFIRM: "var(--info)" };
const WEEKDAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function dateKey(d) {
  return format(d, "yyyy-MM-dd");
}

export default function CoachAttendance() {
  const { user } = useAuth();
  const [viewDate, setViewDate] = useState(startOfMonth(new Date()));
  const [selectedDate, setSelectedDate] = useState(dateKey(new Date()));
  const [monthRecords, setMonthRecords] = useState([]);
  const [monthLoading, setMonthLoading] = useState(true);
  const [facilityAll, setFacilityAll] = useState([]);
  const [facilityLoading, setFacilityLoading] = useState(true);
  const [selfieUrl, setSelfieUrl] = useState(null);

  useEffect(() => {
    setFacilityLoading(true);
    CoachSelfAPI.myAttendance(user.id)
      .then((r) => setFacilityAll(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load your facility attendance"))
      .finally(() => setFacilityLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    setMonthLoading(true);
    CoachSelfAPI.myStudentAttendance({
      date_from: dateKey(startOfMonth(viewDate)),
      date_to: dateKey(endOfMonth(viewDate)),
    })
      .then((r) => setMonthRecords(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load attendance"))
      .finally(() => setMonthLoading(false));
  }, [viewDate]);

  const facilityByDate = useMemo(() => {
    const map = {};
    for (const a of facilityAll) map[String(a.date).slice(0, 10)] = a;
    return map;
  }, [facilityAll]);

  const studentByDate = useMemo(() => {
    const map = {};
    for (const r of monthRecords) {
      (map[r.class_date] ||= []).push(r);
    }
    return map;
  }, [monthRecords]);

  const days = useMemo(
    () => eachDayOfInterval({ start: startOfMonth(viewDate), end: endOfMonth(viewDate) }),
    [viewDate]
  );
  const leadingBlanks = getDay(startOfMonth(viewDate));

  const goMonth = (delta) => {
    setViewDate((d) => (delta > 0 ? addMonths(d, 1) : subMonths(d, 1)));
    setSelectedDate(null);
  };

  const goToday = () => {
    setViewDate(startOfMonth(new Date()));
    setSelectedDate(dateKey(new Date()));
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

  const selectedFacility = selectedDate ? facilityByDate[selectedDate] : null;
  const selectedStudentRecords = selectedDate ? studentByDate[selectedDate] || [] : [];

  return (
    <div>
      <div className="page-header">
        <h1>Attendance</h1>
      </div>

      <div className="card">
        <div className="cal-header">
          <button className="btn btn-secondary btn-sm" onClick={() => goMonth(-1)}>
            ← Prev
          </button>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <h3 style={{ margin: 0 }}>{format(viewDate, "MMMM yyyy")}</h3>
            <button className="btn btn-secondary btn-sm" onClick={goToday}>
              Today
            </button>
          </div>
          <button className="btn btn-secondary btn-sm" onClick={() => goMonth(1)}>
            Next →
          </button>
        </div>

        {(monthLoading || facilityLoading) && <div className="empty-state">Loading...</div>}

        <div className="cal-grid">
          {WEEKDAY_LABELS.map((d) => (
            <div key={d} className="cal-dow">
              {d}
            </div>
          ))}
          {Array.from({ length: leadingBlanks }).map((_, i) => (
            <div key={`blank-${i}`} className="cal-cell cal-empty" />
          ))}
          {days.map((day) => {
            const key = dateKey(day);
            const facility = facilityByDate[key];
            const students = studentByDate[key] || [];
            const statusesPresent = [...new Set(students.map((s) => s.status))];
            return (
              <div
                key={key}
                className={`cal-cell${isToday(day) ? " cal-today" : ""}${selectedDate === key ? " cal-selected" : ""}`}
                onClick={() => setSelectedDate(key)}
              >
                <span className="cal-daynum">{format(day, "d")}</span>
                <div className="cal-dots">
                  {facility && (
                    <span
                      className="cal-dot"
                      style={{ background: FACILITY_DOT_COLOR[facility.status] || "var(--text-muted)" }}
                      title={`Facility: ${facility.status}`}
                    />
                  )}
                  {statusesPresent.map((st) => (
                    <span key={st} className="cal-dot" style={{ background: STUDENT_DOT_COLOR[st] || "var(--text-muted)" }} title={st} />
                  ))}
                </div>
                {students.length > 0 && (
                  <span className="cal-count">
                    {students.length} student{students.length > 1 ? "s" : ""}
                  </span>
                )}
              </div>
            );
          })}
        </div>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>
          {selectedDate ? format(new Date(`${selectedDate}T00:00:00`), "EEEE, MMM d, yyyy") : "Attendance for the day"}
        </h3>

        {!selectedDate ? (
          <div className="empty-state">Click a day on the calendar above to view its attendance.</div>
        ) : (
          <>
            <div style={{ marginBottom: 16 }}>
              <h4 style={{ margin: "0 0 8px" }}>My Facility Attendance</h4>
              {selectedFacility ? (
                <div className="table-actions">
                  <StatusBadge status={selectedFacility.status} />
                  <span style={{ fontSize: "0.85rem", color: "var(--text-muted)" }}>
                    Marked at {selectedFacility.entry_time ? new Date(selectedFacility.entry_time).toLocaleTimeString() : "-"} — locked
                  </span>
                </div>
              ) : (
                <p style={{ color: "var(--text-muted)", fontSize: "0.85rem", margin: 0 }}>No facility attendance marked on this date.</p>
              )}
            </div>

            <div>
              <h4 style={{ margin: "0 0 8px" }}>Student Attendance</h4>
              {selectedStudentRecords.length === 0 ? (
                <p style={{ color: "var(--text-muted)", fontSize: "0.85rem", margin: 0 }}>No student attendance marked on this date.</p>
              ) : (
                <table>
                  <thead>
                    <tr>
                      <th>Student</th>
                      <th>Activity</th>
                      <th>Status</th>
                      <th>Admin Review</th>
                      <th>Marked At</th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    {selectedStudentRecords.map((r) => (
                      <tr key={r.id}>
                        <td>{r.student_name}</td>
                        <td>{r.activity_name}</td>
                        <td>
                          <StatusBadge status={r.status} />
                        </td>
                        <td>{approvalBadge(r.approval_status)}</td>
                        <td>{new Date(r.timestamp).toLocaleString()}</td>
                        <td>
                          {r.has_selfie ? (
                            <button className="btn btn-secondary btn-sm" onClick={() => viewSelfie(r)}>
                              View Photo
                            </button>
                          ) : (
                            <span style={{ fontSize: "0.8rem", color: "var(--text-muted)" }}>Locked</span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          </>
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
