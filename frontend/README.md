# VIMJ Studio OS SaaS — Web Dashboard (React)

The web app has separate protected Admin and Coach dashboards. Admins manage students,
coaches, activities, attendance, leave, fees, reports, and Admin-only AI insights. Coaches
use their own student and attendance workflows and do not receive revenue forecasts.

## Development

```bash
npm install
npm run dev
```

Runs on `http://localhost:5173` and proxies `/api/*` to FastAPI at
`http://localhost:8000` (see `vite.config.js`). Start the backend first.

## Production build

```bash
npm run build
```

Outputs static files to `dist/`. The deployed React app runs on Google Cloud Run;
see [the architecture guide](../docs/ARCHITECTURE.md).

## Role access

- The Admin dashboard is protected by the Admin role.
- Coaches are routed to `/coach` and keep a separate student and attendance view.
- Students do not receive logins.
