# VIMJ Studio Attendance Dashboard (React)

Admin-only web dashboard: students, coaches, activities/classes, attendance oversight,
leave approvals, fee tracking, and business analytics with charts + PDF/CSV export.

## Development

```bash
npm install
npm run dev
```

Runs on `http://localhost:5173` and proxies `/api/*` to the FastAPI backend at
`http://localhost:8000` (see `vite.config.js`). Start the backend first.

## Production build

```bash
npm run build
```

Outputs static files to `dist/`, served by Nginx alongside the FastAPI reverse proxy
(see `backend/nginx.conf.example`).

## Notes

- Coaches and students are not granted access to this dashboard — they use the React
  Native mobile app. Logging in here with a non-admin account shows a redirect message.
- Brand colors: `#0000FF` (primary) / `#F0F8FF` (light accent), defined in `src/theme/theme.css`.
