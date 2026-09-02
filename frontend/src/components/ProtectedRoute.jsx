import { Navigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";

export default function ProtectedRoute({ children }) {
  const { user } = useAuth();

  if (!user) {
    return <Navigate to="/login" replace />;
  }

  if (user.role !== "ADMIN") {
    return (
      <div className="login-page">
        <div className="login-card">
          <h1>Admin dashboard only</h1>
          <p className="subtitle">
            This web dashboard is for facility admins. Coaches and students should use the VIMJ Studio mobile app.
          </p>
        </div>
      </div>
    );
  }

  return children;
}
