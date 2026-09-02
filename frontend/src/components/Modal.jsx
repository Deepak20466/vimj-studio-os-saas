export default function Modal({ title, onClose, children }) {
  return (
    <div className="modal-overlay" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal-box">
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
          <h2 style={{ margin: 0, fontSize: "1.1rem" }}>{title}</h2>
          <button className="link-btn" onClick={onClose} style={{ fontSize: "1.2rem" }}>
            ✕
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}
