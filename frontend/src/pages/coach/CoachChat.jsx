import { useAuth } from "../../context/AuthContext";
import ChatThread from "../../components/ChatThread";

export default function CoachChat() {
  const { user } = useAuth();

  return (
    <div>
      <div className="page-header">
        <h1>Chat</h1>
      </div>
      <ChatThread coachId={user.id} title="Chat with Admin" />
    </div>
  );
}
