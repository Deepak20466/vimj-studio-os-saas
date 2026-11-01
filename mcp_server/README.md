# VIMJ Studio OS SaaS — MCP Server

This local FastMCP server exposes five VIMJ tools over stdio. It reads the existing SQLAlchemy models and database directly; analytics are deterministic rules, and no OpenAI, Gemini, Twilio, or other paid API is called by these tools.

## Setup

1. Create an isolated MCP environment and install its dependencies:

   ```powershell
   cd mcp_server
   python -m venv .venv
   .\.venv\Scripts\python.exe -m pip install -r requirements.txt
   cd ..
   Copy-Item backend/.env.example backend/.env
   ```

2. Set `DATABASE_URL` in `backend/.env` and set `VIMJ_MCP_ADMIN_EMAIL` to an active account whose role is `ADMIN`. The server checks that account and role for every tool call. The MCP server uses local stdio and does not open a network port; only run it on a machine where that admin database access is appropriate.

3. Run the database migrations if this is a fresh local database:

   ```powershell
   cd backend
   alembic upgrade head
   cd ..
   ```

## Claude Desktop

Claude Desktop reads its MCP configuration from `%APPDATA%\Claude\claude_desktop_config.json`. Add the following entry under `mcpServers`, replacing the paths with the absolute path to this checkout. Use the isolated MCP virtual environment executable so it can load FastMCP alongside the shared backend models without changing FastAPI's pinned dependencies.

```json
{
  "mcpServers": {
    "vimj-studio-os": {
      "command": "C:\\path\\to\\attendance-management-master\\mcp_server\\.venv\\Scripts\\python.exe",
      "args": ["C:\\path\\to\\attendance-management-master\\mcp_server\\server.py"],
      "env": {
        "VIMJ_MCP_ADMIN_EMAIL": "your-active-admin@example.com"
      }
    }
  }
}
```

The root `.mcp.json` is the equivalent project-root configuration for Claude Code. For Claude Desktop, use absolute paths in its config and replace the example email with your own active Admin email. Restart Claude Desktop after saving. The Python process loads `backend/.env` for the database URL; `VIMJ_MCP_ADMIN_EMAIL` may be supplied by the MCP config or `backend/.env`. Do not commit real database URLs, passwords, or personal Admin configuration.

## Admin-only tools

- `get_todays_absentees()` — students explicitly marked absent for today's classes.
- `get_fee_defaulters(days_overdue=7)` — late unpaid balances grouped by student and total pending.
- `mark_attendance(student_id, status, date)` — admin manual mark as Present, Absent, or Leave (`date` uses `YYYY-MM-DD`). The tool requires one unambiguous scheduled class and records an approved manual mark in the audit log.
- `create_fee_reminder(student_id)` — queues a mock WhatsApp reminder for open fee records. It does not send a message.
- `get_batch_analytics()` — estimated batch revenue/profitability, attendance drops, and revenue at risk. Actual batch costs are not stored, so the profit figure is a revenue estimate.

If a student has multiple matching scheduled classes on a requested date, `mark_attendance` returns an ambiguity error without changing attendance. Choose a date with one matching class and retry.
