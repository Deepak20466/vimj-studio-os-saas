import { useState } from "react";
import { useNavigate } from "react-router-dom";
import toast from "react-hot-toast";
import { useAuth } from "../context/AuthContext";
import { AuthAPI } from "../api/endpoints";

export default function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [mode, setMode] = useState("login"); // login | forgot | reset
  const [resetToken, setResetToken] = useState("");
  const [newPassword, setNewPassword] = useState("");

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true);
    try {
      const userData = await login(email, password);
      navigate(userData.role === "COACH" ? "/coach" : "/");
    } catch (err) {
      toast.error(err.response?.data?.detail || "Login failed");
    } finally {
      setLoading(false);
    }
  };

  const handleForgot = async (e) => {
    e.preventDefault();
    setLoading(true);
    try {
      const { data } = await AuthAPI.forgotPassword(email);
      toast.success("If the email exists, a reset code has been sent");
      if (data.reset_token) {
        setResetToken(data.reset_token);
      }
      setMode("reset");
    } catch (err) {
      toast.error(err.response?.data?.detail || "Request failed");
    } finally {
      setLoading(false);
    }
  };

  const handleReset = async (e) => {
    e.preventDefault();
    setLoading(true);
    try {
      await AuthAPI.resetPassword(resetToken, newPassword);
      toast.success("Password reset. Please log in.");
      setMode("login");
      setPassword("");
    } catch (err) {
      toast.error(err.response?.data?.detail || "Reset failed");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-page">
      <div className="login-card">
        <img
          src="/logo.png"
          alt="VIMJ Studio"
          className="login-logo"
          onError={(e) => {
            e.currentTarget.style.display = "none";
          }}
        />
        <h1>VIMJ Studio</h1>
        <p className="subtitle">Attendance Management System</p>

        {mode === "login" && (
          <form onSubmit={handleLogin}>
            <div className="field">
              <label>Email</label>
              <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
            </div>
            <div className="field">
              <label>Password</label>
              <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
            </div>
            <button className="btn btn-primary" style={{ width: "100%", justifyContent: "center" }} disabled={loading}>
              {loading ? "Signing in..." : "Sign in"}
            </button>
            <div style={{ textAlign: "center", marginTop: 14 }}>
              <button type="button" className="link-btn" onClick={() => setMode("forgot")}>
                Forgot password?
              </button>
            </div>
          </form>
        )}

        {mode === "forgot" && (
          <form onSubmit={handleForgot}>
            <div className="field">
              <label>Email</label>
              <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
            </div>
            <button className="btn btn-primary" style={{ width: "100%", justifyContent: "center" }} disabled={loading}>
              {loading ? "Sending..." : "Send reset code"}
            </button>
            <div style={{ textAlign: "center", marginTop: 14 }}>
              <button type="button" className="link-btn" onClick={() => setMode("login")}>
                Back to login
              </button>
            </div>
          </form>
        )}

        {mode === "reset" && (
          <form onSubmit={handleReset}>
            <div className="field">
              <label>Reset code</label>
              <input value={resetToken} onChange={(e) => setResetToken(e.target.value)} required />
            </div>
            <div className="field">
              <label>New password</label>
              <input type="password" minLength={8} value={newPassword} onChange={(e) => setNewPassword(e.target.value)} required />
            </div>
            <button className="btn btn-primary" style={{ width: "100%", justifyContent: "center" }} disabled={loading}>
              {loading ? "Resetting..." : "Reset password"}
            </button>
            <div style={{ textAlign: "center", marginTop: 14 }}>
              <button type="button" className="link-btn" onClick={() => setMode("login")}>
                Back to login
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
