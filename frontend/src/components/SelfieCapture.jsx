import { useEffect, useRef, useState } from "react";
import Modal from "./Modal";

export default function SelfieCapture({ onCapture, onClose, title = "Take a selfie to mark present" }) {
  const videoRef = useRef(null);
  const canvasRef = useRef(null);
  const streamRef = useRef(null);
  const [photo, setPhoto] = useState(null);
  const [error, setError] = useState("");

  useEffect(() => {
    navigator.mediaDevices
      ?.getUserMedia({ video: { facingMode: "user" } })
      .then((stream) => {
        streamRef.current = stream;
        if (videoRef.current) videoRef.current.srcObject = stream;
      })
      .catch(() => setError("Could not access the camera. Check browser permissions."));

    return () => {
      streamRef.current?.getTracks().forEach((t) => t.stop());
    };
  }, []);

  const capture = () => {
    const video = videoRef.current;
    const canvas = canvasRef.current;
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    canvas.getContext("2d").drawImage(video, 0, 0);
    setPhoto(canvas.toDataURL("image/jpeg", 0.8));
  };

  const usePhoto = () => {
    const base64 = photo.split(",")[1];
    onCapture(base64);
  };

  return (
    <Modal title={title} onClose={onClose}>
      {error ? (
        <div className="empty-state">{error}</div>
      ) : (
        <>
          <div style={{ background: "#000", borderRadius: 8, overflow: "hidden", maxWidth: 360 }}>
            {!photo ? (
              <video ref={videoRef} autoPlay playsInline muted style={{ width: "100%", display: "block" }} />
            ) : (
              <img src={photo} alt="Captured selfie" style={{ width: "100%", display: "block" }} />
            )}
          </div>
          <canvas ref={canvasRef} style={{ display: "none" }} />
          <div className="modal-actions">
            {!photo ? (
              <button type="button" className="btn btn-primary" onClick={capture}>
                Capture
              </button>
            ) : (
              <>
                <button type="button" className="btn btn-secondary" onClick={() => setPhoto(null)}>
                  Retake
                </button>
                <button type="button" className="btn btn-primary" onClick={usePhoto}>
                  Use this photo
                </button>
              </>
            )}
          </div>
        </>
      )}
    </Modal>
  );
}
