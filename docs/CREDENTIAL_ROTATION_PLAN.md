# Credential rotation plan (prepared 2026-11-17, NOT yet executed)

Context: production moved from Supabase to Google Cloud SQL on 2026-11-17. During the migration
the old Supabase database password was printed once into an assistant session transcript, and the
Aiven test database password was shared in plain text. Neither is used by production any more, but
both are still valid. Nothing below has been run. Execute in the order shown; each step lists its
blast radius and how to verify. Never paste a password into chat, a commit, or a command line that
is logged; generate and store secrets directly into Secret Manager or a password manager.

## Order of operations

| # | Credential | Used by production? | Risk if left | Downtime |
|---|------------|--------------------|--------------|----------|
| 1 | Supabase DB password (exposed) | No | Anyone with it can read/alter the retained Supabase copy | None |
| 2 | Aiven DB password (exposed) | No | Same, for the Aiven test copy | None |
| 3 | Cloud SQL `vimj_app` password | **Yes** | Lives in `~/vimj-migration-backups/cloudsql-app.pw` and secret `vimj-cloudsql-database-url` v1 | None (dual-user method) |
| 4 | Cloud SQL `postgres` password | No | Set at instance creation; unknown to the migration tooling | None |
| 5 | `JWT_SECRET_KEY` (`vimj-prod-jwt-secret`) | **Yes** | Low: read into a shell variable once during the cutover, never printed | Every user is logged out |
| 6 | Local artifacts | n/a | Dumps and URL files on a laptop | None |

`ADMIN_RECOVERY_SECRET`, Firebase service-account keys and the Cloud Scheduler OIDC identities were
not touched and do not need rotating for this event.

## 1. Supabase password (do first; zero production impact)
1. Supabase dashboard -> Project Settings -> Database -> Reset database password. Store the new one
   in the owner's password manager only. Do NOT add it to Secret Manager (nothing should use it).
2. Disable (not delete) secret versions 1-4 of `vimj-prod-database-url` so the old password is not
   left readable in Secret Manager: `gcloud secrets versions disable N --secret vimj-prod-database-url`.
3. Expected effect: revision `vimj-backend-00042-mey` and jobs `vimj-supabase-backup` and
   `vimj-migration-0022` can no longer connect. That is intended; rollback to Supabase was closed at
   the first Cloud SQL write (see CLAUDE.md).
4. Verify: `/health/ready` still 200 and the minute scheduler still SUCCEEDED (production uses Cloud SQL).
5. Supabase project and its data stay preserved. Decide the retention end-date separately.

## 2. Aiven password
Reset it in the Aiven console (or, preferably, power off / delete the Aiven service once you no longer
need the test copy: it is idle and may bill). Then disable versions of `vimj-aiven-database-url`.
Production is unaffected.

## 3. Cloud SQL `vimj_app` password (zero-downtime dual-user method)
1. Generate a strong password locally; create user `vimj_app2` with it:
   `gcloud sql users create vimj_app2 --instance deepak20 --password-file=<file>` (or `--prompt-for-password`).
2. Give it the same access: connect as `vimj_app` (Auth Proxy) and run `GRANT vimj_app TO vimj_app2;`
   (members inherit the owner's privileges, so DML and Alembic DDL both work).
3. Add secret version 2 to `vimj-cloudsql-database-url` using `vimj_app2` (socket URL form, password
   percent-encoded). Do not edit v1.
4. Deploy a NO-TRAFFIC revision pinned to v2:
   `gcloud run services update vimj-backend --no-traffic --tag canary --update-secrets DATABASE_URL=vimj-cloudsql-database-url:2`.
5. Smoke test the canary tag URL with an identity token and a normal admin login (read-only checks).
6. `gcloud run services update-traffic vimj-backend --to-revisions <new-revision>=100`.
7. Repoint job `vimj-cloudsql-backup` at `:2` (its secret reference is pinned to version 1) and run it once.
8. After 24 h of clean logs: `REASSIGN OWNED BY vimj_app TO vimj_app2; DROP OWNED BY vimj_app; DROP USER vimj_app;`
   then disable secret v1.
9. Rollback at any step before 8: send traffic back to the previous revision (still on v1).

## 4. Cloud SQL `postgres` user
`gcloud sql users set-password postgres --instance deepak20 --prompt-for-password`; keep the value in the
password manager only. The application never uses this account.

## 5. JWT signing key (optional, user-visible)
Rotating logs out every web and mobile user (access and sliding refresh tokens are signed with this key).
The exposure risk is low, so schedule it only with a user announcement, or skip. If done: add v2 of
`vimj-prod-jwt-secret`, deploy a no-traffic revision pinned to it, switch traffic, disable v1.

## 6. Local artifacts (after the retention decision)
Securely delete when no longer needed: `~/urls.env`, `~/vimj-migration-backups/` (Supabase dumps,
`cloudsql-app.pw`, `proxy.log`, the downloaded dumps). Use `shred -u`. Offsite copies in
`gs://vimj-academy-recovery-backup-2026/vimj-daily/` expire after 35 days by lifecycle rule; copy any
dump you want to keep longer before then.

## Standing rules
- One change at a time; verify `/health/ready` and the scheduler ledger after each.
- Never change production traffic and a credential in the same step.
- Keep the previous secret version enabled until the new one has run cleanly, then disable (not delete).
