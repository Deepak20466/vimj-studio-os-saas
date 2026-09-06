import { useEffect, useState } from "react";
import { LineChart, Line, PieChart, Pie, Cell, Legend, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from "recharts";
import toast from "react-hot-toast";
import { ReportsAPI } from "../api/endpoints";
import useResizeAfterLoad from "../hooks/useResizeAfterLoad";

const FEE_PIE_COLORS = ["#16a34a", "#d97706"];

export default function StudentReportPanel({ studentId }) {
  const [report, setReport] = useState(null);
  const [graph, setGraph] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([ReportsAPI.studentReport(studentId), ReportsAPI.attendanceGraph(studentId)])
      .then(([r, g]) => {
        setReport(r.data);
        setGraph(g.data.points);
      })
      .catch((err) => toast.error(err.response?.data?.detail || "Failed to load report"))
      .finally(() => setLoading(false));
  }, [studentId]);

  const downloadReport = async (fmt) => {
    try {
      const { data } = await ReportsAPI.exportStudent(studentId, fmt);
      const url = window.URL.createObjectURL(new Blob([data]));
      const a = document.createElement("a");
      a.href = url;
      a.download = `student_${studentId}_report.${fmt}`;
      a.click();
      window.URL.revokeObjectURL(url);
    } catch {
      toast.error("Export failed");
    }
  };

  useResizeAfterLoad(!loading && !!report);

  if (loading) return <div className="empty-state">Loading report...</div>;
  if (!report) return null;

  const feeData = [
    { name: "Paid", value: report.fees_paid },
    { name: "Unpaid", value: report.fees_unpaid },
  ];
  const hasFeeData = report.fees_paid + report.fees_unpaid > 0;

  return (
    <div>
      <div className="stat-grid" style={{ marginBottom: 12 }}>
        <div className="stat-card">
          <div className="stat-label">Attendance %</div>
          <div className="stat-value">{report.attendance_pct}%</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Outstanding Balance</div>
          <div className="stat-value">₹{report.outstanding_balance}</div>
        </div>
      </div>

      <table style={{ marginBottom: 16 }}>
        <tbody>
          <tr>
            <td>Total Classes</td>
            <td>{report.total_classes}</td>
          </tr>
          <tr>
            <td>Present</td>
            <td>{report.present}</td>
          </tr>
          <tr>
            <td>Absent</td>
            <td>{report.absent}</td>
          </tr>
          <tr>
            <td>Leave</td>
            <td>{report.leave}</td>
          </tr>
          <tr>
            <td>Fees Paid / Unpaid</td>
            <td>
              {report.fees_paid} / {report.fees_unpaid}
            </td>
          </tr>
        </tbody>
      </table>

      {hasFeeData && (
        <div style={{ marginBottom: 16 }}>
          <h4 style={{ marginBottom: 4 }}>Fee Status</h4>
          <ResponsiveContainer width="100%" height={180}>
            <PieChart>
              <Pie data={feeData} dataKey="value" nameKey="name" outerRadius={60} label>
                {feeData.map((_, i) => (
                  <Cell key={i} fill={FEE_PIE_COLORS[i % FEE_PIE_COLORS.length]} />
                ))}
              </Pie>
              <Tooltip />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
        </div>
      )}

      {graph.length > 0 && (
        <ResponsiveContainer width="100%" height={200}>
          <LineChart data={graph}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="label" fontSize={11} />
            <YAxis fontSize={11} />
            <Tooltip />
            <Line type="monotone" dataKey="value" stroke="#CC7000" strokeWidth={2} name="Attendance %" />
          </LineChart>
        </ResponsiveContainer>
      )}

      <div className="modal-actions">
        <button className="btn btn-secondary" onClick={() => downloadReport("csv")}>
          Export CSV
        </button>
        <button className="btn btn-primary" onClick={() => downloadReport("pdf")}>
          Export PDF
        </button>
      </div>
    </div>
  );
}
