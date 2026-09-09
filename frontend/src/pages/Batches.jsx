import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { BatchesAPI, ActivitiesAPI, CoachesAPI, SwapAPI } from "../api/endpoints";
import Modal from "../components/Modal";

const DAYS = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"];
const SESSIONS = ["MORNING", "AFTERNOON", "EVENING"];
const MONTHS = [
  { value: 1, label: "Jan" },
  { value: 2, label: "Feb" },
  { value: 3, label: "Mar" },
  { value: 4, label: "Apr" },
  { value: 5, label: "May" },
  { value: 6, label: "Jun" },
  { value: 7, label: "Jul" },
  { value: 8, label: "Aug" },
  { value: 9, label: "Sep" },
  { value: 10, label: "Oct" },
  { value: 11, label: "Nov" },
  { value: 12, label: "Dec" },
];
const ALL_MONTHS = MONTHS.map((m) => m.value);

const emptyForm = {
  activity_id: "",
  coach_id: "",
  location: "",
  session_period: "MORNING",
  start_time: "",
  end_time: "",
  days_of_week: [],
  active_months: ALL_MONTHS,
};

const todayStr = () => new Date().toISOString().slice(0, 10);

const emptyReassign = { original_coach_id: "", batch_id: "", date: todayStr(), covering_coach_id: "", reason: "" };

export default function Batches() {
  const [batches, setBatches] = useState([]);
  const [activities, setActivities] = useState([]);
  const [coaches, setCoaches] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(emptyForm);
  const [generatingFor, setGeneratingFor] = useState(null);
  const [genRange, setGenRange] = useState({ start_date: "", end_date: "" });

  const [coverage, setCoverage] = useState(null);
  const [coverageLoading, setCoverageLoading] = useState(true);
  const [coverageDate, setCoverageDate] = useState(todayStr());

  const [showReassign, setShowReassign] = useState(false);
  const [reassignForm, setReassignForm] = useState(emptyReassign);
  const [recentSwaps, setRecentSwaps] = useState([]);
  const [pendingSwaps, setPendingSwaps] = useState([]);
  const [swapBusyId, setSwapBusyId] = useState(null);

  const loadRecentSwaps = () => {
    SwapAPI.recent()
      .then((r) => setRecentSwaps(r.data))
      .catch(() => {});
  };

  const loadPendingSwaps = () => {
    SwapAPI.pending()
      .then((r) => setPendingSwaps(r.data))
      .catch(() => {});
  };

  const approveSwap = async (s) => {
    setSwapBusyId(s.id);
    try {
      await SwapAPI.approve(s.id);
      toast.success("Swap approved");
      loadPendingSwaps();
      loadRecentSwaps();
      loadCoverage();
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Approve failed");
    } finally {
      setSwapBusyId(null);
    }
  };

  const rejectSwap = async (s) => {
    setSwapBusyId(s.id);
    try {
      await SwapAPI.reject(s.id);
      toast.success("Swap rejected");
      loadPendingSwaps();
      loadRecentSwaps();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Reject failed");
    } finally {
      setSwapBusyId(null);
    }
  };

  const loadCoverage = () => {
    setCoverageLoading(true);
    BatchesAPI.coverage(coverageDate)
      .then((r) => setCoverage(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load coverage"))
      .finally(() => setCoverageLoading(false));
  };

  useEffect(() => {
    loadCoverage();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [coverageDate]);

  const load = () => {
    setLoading(true);
    BatchesAPI.list()
      .then((r) => setBatches(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load batches"))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
    loadRecentSwaps();
    loadPendingSwaps();
    ActivitiesAPI.list().then((r) => setActivities(r.data));
    CoachesAPI.list().then((r) => setCoaches(r.data));
  }, []);

  const monthsLabel = (months) =>
    !months || months.length === 12 ? "All year" : months.map((m) => MONTHS.find((x) => x.value === m)?.label || m).join(", ");

  const activityName = (id) => activities.find((a) => a.id === id)?.name || `#${id}`;
  const coachName = (id) => coaches.find((c) => c.id === id)?.name || (id ? `#${id}` : "Unassigned");

  const openCreate = () => {
    setEditing(null);
    setForm(emptyForm);
    setShowForm(true);
  };

  const openEdit = (b) => {
    setEditing(b);
    setForm({
      activity_id: b.activity_id,
      coach_id: b.coach_id || "",
      location: b.location,
      session_period: b.session_period,
      start_time: b.start_time,
      end_time: b.end_time,
      days_of_week: b.days_of_week,
      active_months: b.active_months && b.active_months.length ? b.active_months : ALL_MONTHS,
    });
    setShowForm(true);
  };

  const toggleDay = (day) => {
    setForm((f) => ({
      ...f,
      days_of_week: f.days_of_week.includes(day) ? f.days_of_week.filter((d) => d !== day) : [...f.days_of_week, day],
    }));
  };

  const toggleMonth = (month) => {
    setForm((f) => ({
      ...f,
      active_months: f.active_months.includes(month) ? f.active_months.filter((m) => m !== month) : [...f.active_months, month].sort((a, b) => a - b),
    }));
  };

  const submit = async (e) => {
    e.preventDefault();
    if (form.days_of_week.length === 0) {
      toast.error("Select at least one day");
      return;
    }
    if (form.active_months.length === 0) {
      toast.error("Select at least one month");
      return;
    }
    try {
      const payload = {
        ...form,
        activity_id: Number(form.activity_id),
        coach_id: form.coach_id ? Number(form.coach_id) : null,
      };
      if (editing) {
        await BatchesAPI.update(editing.id, payload);
        toast.success("Batch updated");
      } else {
        await BatchesAPI.create(payload);
        toast.success("Batch created");
      }
      setShowForm(false);
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Save failed");
    }
  };

  const remove = async (b) => {
    if (!confirm(`Delete this batch (${activityName(b.activity_id)} @ ${b.location})?`)) return;
    try {
      await BatchesAPI.remove(b.id);
      toast.success("Batch deleted");
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Delete failed");
    }
  };

  const openGenerate = (b) => {
    setGeneratingFor(b);
    setGenRange({ start_date: "", end_date: "" });
  };

  const submitGenerate = async (e) => {
    e.preventDefault();
    try {
      const { data } = await BatchesAPI.generateSessions(generatingFor.id, genRange);
      toast.success(data.detail);
      setGeneratingFor(null);
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to generate sessions");
    }
  };

  const openReassign = () => {
    setReassignForm(emptyReassign);
    setShowReassign(true);
  };

  const batchesForOriginalCoach = batches.filter((b) => b.coach_id === Number(reassignForm.original_coach_id));
  const selectedReassignBatch = batches.find((b) => b.id === Number(reassignForm.batch_id));

  const submitReassign = async (e) => {
    e.preventDefault();
    try {
      await SwapAPI.adminAssign({
        original_coach_id: Number(reassignForm.original_coach_id),
        covering_coach_id: Number(reassignForm.covering_coach_id),
        batch_id: Number(reassignForm.batch_id),
        date: reassignForm.date,
        reason: reassignForm.reason,
      });
      toast.success("Coach reassigned for that date");
      setShowReassign(false);
      loadCoverage();
      loadRecentSwaps();
      load();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Reassignment failed");
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>Batches</h1>
        <div style={{ display: "flex", gap: 8 }}>
          <button className="btn btn-secondary" onClick={openReassign}>
            Reassign Coach
          </button>
          <button className="btn btn-primary" onClick={openCreate}>
            + Add Batch
          </button>
        </div>
      </div>

      <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -8 }}>
        A batch is a recurring weekly schedule (activity, location, session, time, days, active months, coach). Once
        set, it keeps applying automatically every day going forward — a system job rolls each batch's dated classes
        30 days ahead every night, so you don't need to regenerate manually. Only the months you tick under "Months"
        are used; edit the batch any time to change the time, days, or months and it takes effect from then on. Use
        "Generate Sessions" only if you want to backfill sessions immediately instead of waiting for the nightly job.
        Use "Reassign Coach" above to hand a batch to a substitute for a specific date (even one not generated yet),
        or the "Reassign" action on the Attendance page once a class is already showing as missing.
      </p>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Coverage</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -8 }}>
          Which slots aren't taken, and who runs which activity.
        </p>
        <div className="toolbar" style={{ marginBottom: 12 }}>
          <label style={{ display: "flex", alignItems: "center", gap: 6, fontSize: "0.85rem" }}>
            Check date
            <input type="date" value={coverageDate} onChange={(e) => setCoverageDate(e.target.value)} />
          </label>
        </div>
        {coverageLoading ? (
          <div className="empty-state">Loading...</div>
        ) : !coverage ? (
          <div className="empty-state">Failed to load coverage.</div>
        ) : (
          <>
            <h4 style={{ marginBottom: 6 }}>Batches with no coach assigned</h4>
            {coverage.unassigned_batches.length === 0 ? (
              <div className="empty-state">Every active batch has a coach assigned.</div>
            ) : (
              <ul style={{ margin: "0 0 16px", paddingLeft: 18 }}>
                {coverage.unassigned_batches.map((b) => (
                  <li key={b.id} style={{ fontSize: "0.85rem" }}>
                    {activityName(b.activity_id)} — {b.location} ({b.session_period}, {b.start_time}-{b.end_time})
                  </li>
                ))}
              </ul>
            )}

            <h4 style={{ marginBottom: 6 }}>Scheduled today but no session generated yet</h4>
            {coverage.batches_not_generated_today.length === 0 ? (
              <div className="empty-state">Nothing outstanding for {coverageDate}.</div>
            ) : (
              <ul style={{ margin: "0 0 16px", paddingLeft: 18 }}>
                {coverage.batches_not_generated_today.map((b) => (
                  <li key={b.id} style={{ fontSize: "0.85rem" }}>
                    {activityName(b.activity_id)} — {b.location} ({coachName(b.coach_id)}, {b.start_time}-{b.end_time})
                  </li>
                ))}
              </ul>
            )}

            <h4 style={{ marginBottom: 6 }}>Who takes which activity</h4>
            {coverage.activity_coach_map.length === 0 ? (
              <div className="empty-state">No coach-assigned batches yet.</div>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>Activity</th>
                    <th>Coaches</th>
                  </tr>
                </thead>
                <tbody>
                  {coverage.activity_coach_map.map((a) => (
                    <tr key={a.activity_id}>
                      <td>{a.activity_name}</td>
                      <td>{a.coaches.map((c) => `${c.coach_name} (${c.batch_count})`).join(", ")}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </>
        )}
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Pending Swap Requests</h3>
        <p style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: -8 }}>
          Coaches asking another coach to cover their class — approve or reject to decide.
        </p>
        {pendingSwaps.length === 0 ? (
          <div className="empty-state">No pending swap requests.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Class</th>
                <th>Requesting Coach</th>
                <th>Covering Coach</th>
                <th>Reason</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {pendingSwaps.map((s) => (
                <tr key={s.id}>
                  <td>{s.date}</td>
                  <td>Class #{s.class_id}</td>
                  <td>{coachName(s.original_coach_id)}</td>
                  <td>{coachName(s.covering_coach_id)}</td>
                  <td>{s.reason || "-"}</td>
                  <td className="table-actions">
                    <button className="btn btn-primary btn-sm" disabled={swapBusyId === s.id} onClick={() => approveSwap(s)}>
                      Approve
                    </button>
                    <button className="btn btn-danger btn-sm" disabled={swapBusyId === s.id} onClick={() => rejectSwap(s)}>
                      Reject
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Recent Reassignments</h3>
        {recentSwaps.length === 0 ? (
          <div className="empty-state">No reassignments yet.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Activity</th>
                <th>Original Coach</th>
                <th>Covering Coach</th>
                <th>Status</th>
                <th>Reason</th>
              </tr>
            </thead>
            <tbody>
              {recentSwaps.map((s) => (
                <tr key={s.id}>
                  <td>{s.date}</td>
                  <td>{s.activity_name}</td>
                  <td>{s.original_coach_name}</td>
                  <td>{s.covering_coach_name}</td>
                  <td>
                    <span className={`badge badge-${s.status === "APPROVED" ? "approved" : s.status === "REJECTED" ? "rejected" : "pending"}`}>
                      {s.status}
                    </span>
                  </td>
                  <td>{s.reason || "-"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="card">
        {loading ? (
          <div className="empty-state">Loading...</div>
        ) : batches.length === 0 ? (
          <div className="empty-state">No batches yet. Create one to schedule a recurring weekly class.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Activity</th>
                <th>Location</th>
                <th>Session</th>
                <th>Time</th>
                <th>Days</th>
                <th>Months</th>
                <th>Coach</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {batches.map((b) => (
                <tr key={b.id}>
                  <td>{activityName(b.activity_id)}</td>
                  <td>{b.location}</td>
                  <td>{b.session_period}</td>
                  <td>
                    {b.start_time} - {b.end_time}
                  </td>
                  <td>{b.days_of_week.join(", ")}</td>
                  <td>{monthsLabel(b.active_months)}</td>
                  <td>{coachName(b.coach_id)}</td>
                  <td className="table-actions">
                    <button className="btn btn-secondary btn-sm" onClick={() => openGenerate(b)}>
                      Generate Sessions
                    </button>
                    <button className="btn btn-secondary btn-sm" onClick={() => openEdit(b)}>
                      Edit
                    </button>
                    <button className="btn btn-danger btn-sm" onClick={() => remove(b)}>
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {showForm && (
        <Modal title={editing ? "Edit Batch" : "Add Batch"} onClose={() => setShowForm(false)}>
          <form onSubmit={submit}>
            <div className="field">
              <label>Activity</label>
              <select value={form.activity_id} onChange={(e) => setForm({ ...form, activity_id: e.target.value })} required>
                <option value="">Select activity</option>
                {activities.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="field">
              <label>Location</label>
              <input value={form.location} onChange={(e) => setForm({ ...form, location: e.target.value })} placeholder="e.g. Indiranagar" required />
            </div>
            <div className="form-grid">
              <div>
                <label>Session</label>
                <select value={form.session_period} onChange={(e) => setForm({ ...form, session_period: e.target.value })}>
                  {SESSIONS.map((s) => (
                    <option key={s} value={s}>
                      {s.charAt(0) + s.slice(1).toLowerCase()}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label>Coach</label>
                <select value={form.coach_id} onChange={(e) => setForm({ ...form, coach_id: e.target.value })}>
                  <option value="">Unassigned</option>
                  {coaches.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            <div className="form-grid">
              <div>
                <label>Start Time</label>
                <input type="time" value={form.start_time} onChange={(e) => setForm({ ...form, start_time: e.target.value })} required />
              </div>
              <div>
                <label>End Time</label>
                <input type="time" value={form.end_time} onChange={(e) => setForm({ ...form, end_time: e.target.value })} required />
              </div>
            </div>
            <div className="field">
              <label>Days</label>
              <div className="btn-group">
                {DAYS.map((d) => (
                  <button
                    type="button"
                    key={d}
                    className={`btn btn-sm btn-toggle ${form.days_of_week.includes(d) ? "btn-primary" : "btn-secondary"}`}
                    onClick={() => toggleDay(d)}
                  >
                    {d}
                  </button>
                ))}
              </div>
            </div>
            <div className="field">
              <label>Months</label>
              <p style={{ fontSize: "0.78rem", color: "var(--text-muted)", margin: "0 0 6px" }}>
                Choose which months this schedule is active in (e.g. pick just September onward). Sessions keep
                auto-generating in those months every year until you change this.
              </p>
              <div className="btn-group">
                {MONTHS.map((m) => (
                  <button
                    type="button"
                    key={m.value}
                    className={`btn btn-sm btn-toggle ${form.active_months.includes(m.value) ? "btn-primary" : "btn-secondary"}`}
                    onClick={() => toggleMonth(m.value)}
                  >
                    {m.label}
                  </button>
                ))}
              </div>
            </div>
            <div className="modal-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>
                Cancel
              </button>
              <button className="btn btn-primary">{editing ? "Save" : "Create"}</button>
            </div>
          </form>
        </Modal>
      )}

      {generatingFor && (
        <Modal title={`Generate Sessions — ${activityName(generatingFor.activity_id)}`} onClose={() => setGeneratingFor(null)}>
          <form onSubmit={submitGenerate}>
            <p style={{ fontSize: "0.85rem", color: "var(--text-muted)" }}>
              Creates one dated class per matching day ({generatingFor.days_of_week.join(", ")}) in this range.
            </p>
            <div className="form-grid">
              <div>
                <label>Start Date</label>
                <input type="date" value={genRange.start_date} onChange={(e) => setGenRange({ ...genRange, start_date: e.target.value })} required />
              </div>
              <div>
                <label>End Date</label>
                <input type="date" value={genRange.end_date} onChange={(e) => setGenRange({ ...genRange, end_date: e.target.value })} required />
              </div>
            </div>
            <div className="modal-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setGeneratingFor(null)}>
                Cancel
              </button>
              <button className="btn btn-primary">Generate</button>
            </div>
          </form>
        </Modal>
      )}

      {showReassign && (
        <Modal title="Reassign Coach" onClose={() => setShowReassign(false)}>
          <form onSubmit={submitReassign}>
            <div className="field">
              <label>Original / Assigned Coach</label>
              <select
                value={reassignForm.original_coach_id}
                onChange={(e) => setReassignForm({ ...reassignForm, original_coach_id: e.target.value, batch_id: "" })}
                required
              >
                <option value="">Select coach</option>
                {coaches.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="field">
              <label>Batch</label>
              <select
                value={reassignForm.batch_id}
                onChange={(e) => setReassignForm({ ...reassignForm, batch_id: e.target.value })}
                required
                disabled={!reassignForm.original_coach_id}
              >
                <option value="">Select batch</option>
                {batchesForOriginalCoach.map((b) => (
                  <option key={b.id} value={b.id}>
                    {activityName(b.activity_id)} — {b.location} ({b.session_period}, {b.start_time}-{b.end_time})
                  </option>
                ))}
              </select>
              {selectedReassignBatch && (
                <p style={{ fontSize: "0.78rem", color: "var(--text-muted)", margin: "4px 0 0" }}>
                  Activity: {activityName(selectedReassignBatch.activity_id)} · Session: {selectedReassignBatch.session_period} · Time:{" "}
                  {selectedReassignBatch.start_time}-{selectedReassignBatch.end_time}
                </p>
              )}
            </div>
            <div className="field">
              <label>Date</label>
              <input type="date" value={reassignForm.date} onChange={(e) => setReassignForm({ ...reassignForm, date: e.target.value })} required />
            </div>
            <div className="field">
              <label>Substitute Coach</label>
              <select
                value={reassignForm.covering_coach_id}
                onChange={(e) => setReassignForm({ ...reassignForm, covering_coach_id: e.target.value })}
                required
              >
                <option value="">Select coach</option>
                {coaches.filter((c) => c.id !== Number(reassignForm.original_coach_id)).map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="field">
              <label>Reason for substitution</label>
              <textarea rows={3} value={reassignForm.reason} onChange={(e) => setReassignForm({ ...reassignForm, reason: e.target.value })} required />
            </div>
            <div className="modal-actions">
              <button type="button" className="btn btn-secondary" onClick={() => setShowReassign(false)}>
                Cancel
              </button>
              <button className="btn btn-primary">Reassign</button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
