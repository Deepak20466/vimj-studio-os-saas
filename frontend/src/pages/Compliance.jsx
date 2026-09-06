import { useEffect, useState } from "react";
import toast from "react-hot-toast";
import { ComplianceAPI, ActivitiesAPI } from "../api/endpoints";
import Modal from "../components/Modal";

const STATE_LABELS = {
  SUBMITTED: "Submitted",
  PENDING: "Pending",
  DELAYED: "Delayed (awaiting approval)",
  NOT_CONDUCTED: "Not Conducted",
  LATE_APPROVED: "Late — Approved",
  LATE_REJECTED: "Late — Rejected",
};

const STATE_BADGE = {
  SUBMITTED: "approved",
  PENDING: "pending",
  DELAYED: "pending",
  NOT_CONDUCTED: "rejected",
  LATE_APPROVED: "approved",
  LATE_REJECTED: "rejected",
};

function todayStr() {
  return new Date().toISOString().slice(0, 10);
}

function daysAgoStr(n) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d.toISOString().slice(0, 10);
}

export default function Compliance() {
  const [activities, setActivities] = useState([]);
  const [filters, setFilters] = useState({ date_from: daysAgoStr(7), date_to: todayStr(), activity_id: "" });
  const [summary, setSummary] = useState(null);
  const [loading, setLoading] = useState(true);

  const [pendingLate, setPendingLate] = useState([]);
  const [pendingLoading, setPendingLoading] = useState(true);
  const [busyId, setBusyId] = useState(null);

  const [photosFor, setPhotosFor] = useState(null); // class_id
  const [photoUrls, setPhotoUrls] = useState([]);
  const [photosLoading, setPhotosLoading] = useState(false);

  const loadSummary = () => {
    setLoading(true);
    const params = {};
    if (filters.date_from) params.date_from = filters.date_from;
    if (filters.date_to) params.date_to = filters.date_to;
    if (filters.activity_id) params.activity_id = Number(filters.activity_id);
    ComplianceAPI.summary(params)
      .then((r) => setSummary(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load compliance summary"))
      .finally(() => setLoading(false));
  };

  const loadPending = () => {
    setPendingLoading(true);
    ComplianceAPI.pendingLate()
      .then((r) => setPendingLate(r.data))
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load pending approvals"))
      .finally(() => setPendingLoading(false));
  };

  useEffect(() => {
    ActivitiesAPI.list().then((r) => setActivities(r.data));
    loadPending();
  }, []);

  useEffect(() => {
    const t = setTimeout(loadSummary, 150);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filters]);

  const viewPhotos = async (classId) => {
    setPhotosFor(classId);
    setPhotoUrls([]);
    setPhotosLoading(true);
    try {
      const { data: photos } = await ComplianceAPI.classPhotos(classId);
      const blobs = await Promise.all(photos.map((p) => ComplianceAPI.classPhotoBlob(p.id)));
      setPhotoUrls(blobs.map((b) => URL.createObjectURL(b.data)));
    } catch (err) {
      toast.error(err.response?.data?.detail || "Failed to load photos");
    } finally {
      setPhotosLoading(false);
    }
  };

  const decide = async (submission, approve) => {
    setBusyId(submission.id);
    try {
      if (approve) {
        await ComplianceAPI.approveLate(submission.id);
        toast.success("Late attendance approved");
      } else {
        const note = prompt("Reason for rejecting (optional):") || "";
        await ComplianceAPI.rejectLate(submission.id, note);
        toast.success("Late attendance rejected");
      }
      loadPending();
      loadSummary();
    } catch (err) {
      toast.error(err.response?.data?.detail || "Action failed");
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div>
      <div className="page-header">
        <h1>Attendance Compliance</h1>
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Pending Late-Attendance Approvals</h3>
        {pendingLoading ? (
          <div className="empty-state">Loading...</div>
        ) : pendingLate.length === 0 ? (
          <div className="empty-state">Nothing awaiting approval.</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Coach</th>
                <th>Activity</th>
                <th>Class Date</th>
                <th>Reason</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {pendingLate.map((p) => (
                <tr key={p.id}>
                  <td>{p.coach_name}</td>
                  <td>{p.activity_name}</td>
                  <td>{p.class_date}</td>
                  <td>{p.late_reason || "-"}</td>
                  <td>
                    <button className="btn btn-primary" style={{ marginRight: 6 }} disabled={busyId === p.id} onClick={() => decide(p, true)}>
                      Approve
                    </button>
                    <button className="btn btn-danger" disabled={busyId === p.id} onClick={() => decide(p, false)}>
                      Reject
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Compliance Overview</h3>
        <div className="toolbar">
          <select value={filters.activity_id} onChange={(e) => setFilters({ ...filters, activity_id: e.target.value })}>
            <option value="">All activities</option>
            {activities.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name}
              </option>
            ))}
          </select>
          <input type="date" value={filters.date_from} onChange={(e) => setFilters({ ...filters, date_from: e.target.value })} />
          <input type="date" value={filters.date_to} onChange={(e) => setFilters({ ...filters, date_to: e.target.value })} />
        </div>

        {loading || !summary ? (
          <div className="empty-state">Loading...</div>
        ) : (
          <>
            <div className="stat-grid">
              <div className="stat-card">
                <div className="stat-label">Submitted</div>
                <div className="stat-value">{summary.submitted}</div>
              </div>
              <div className="stat-card">
                <div className="stat-label">Pending</div>
                <div className="stat-value">{summary.pending}</div>
              </div>
              <div className="stat-card">
                <div className="stat-label">Delayed</div>
                <div className="stat-value">{summary.delayed}</div>
              </div>
              <div className="stat-card">
                <div className="stat-label">Not Conducted</div>
                <div className="stat-value">{summary.not_conducted}</div>
              </div>
            </div>

            {summary.rows.length === 0 ? (
              <div className="empty-state">No scheduled classes in this range.</div>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>Date</th>
                    <th>Activity</th>
                    <th>Coach</th>
                    <th>End Time</th>
                    <th>State</th>
                    <th>Note</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {summary.rows.map((r) => (
                    <tr key={r.class_id}>
                      <td>{r.class_date}</td>
                      <td>{r.activity_name}</td>
                      <td>{r.coach_name}</td>
                      <td>{r.end_time}</td>
                      <td>
                        <span className={`badge badge-${STATE_BADGE[r.state] || "pending"}`}>{STATE_LABELS[r.state] || r.state}</span>
                      </td>
                      <td style={{ fontSize: "0.82rem", color: "var(--text-muted)" }}>{r.skip_reason || r.late_reason || "-"}</td>
                      <td>
                        <button className="btn btn-secondary" onClick={() => viewPhotos(r.class_id)}>
                          Photos
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </>
        )}
      </div>

      {photosFor && (
        <Modal title="Batch/Session Photos" onClose={() => setPhotosFor(null)}>
          {photosLoading ? (
            <div className="empty-state">Loading...</div>
          ) : photoUrls.length === 0 ? (
            <div className="empty-state">No photos captured for this class.</div>
          ) : (
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(120px, 1fr))", gap: 10 }}>
              {photoUrls.map((url, i) => (
                <img key={i} src={url} alt="Class" style={{ width: "100%", borderRadius: 8, border: "1px solid var(--border)" }} />
              ))}
            </div>
          )}
        </Modal>
      )}
    </div>
  );
}
