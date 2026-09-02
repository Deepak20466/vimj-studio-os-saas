export default function StatusBadge({ status }) {
  const cls = `badge badge-${String(status).toLowerCase()}`;
  return <span className={cls}>{status}</span>;
}
