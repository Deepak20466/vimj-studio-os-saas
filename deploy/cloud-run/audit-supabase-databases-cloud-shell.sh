#!/usr/bin/env bash
# Compare exact public-table row counts in vimj-academy-recovery and
# vimj restore. Both database sessions use repeatable-read, read-only
# transactions. Credentials are never printed or passed on the psql command
# line; temporary .pgpass files are owner-only and removed on exit.
set -Eeuo pipefail
set +x
umask 077

PROJECT_ID="vimj-academy"
RECOVERY_SECRET="vimj-prod-database-url"
EXPECTED_RECOVERY_REF="${EXPECTED_RECOVERY_REF:-}"
EXPECTED_RESTORE_REF="${EXPECTED_RESTORE_REF:-}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command is unavailable: $1"; }

need gcloud
need python3
need psql
[[ -n "$EXPECTED_RECOVERY_REF" ]] || die "Set EXPECTED_RECOVERY_REF to the recovery Supabase project reference."
[[ -n "$EXPECTED_RESTORE_REF" ]] || die "Set EXPECTED_RESTORE_REF to the vimj restore Supabase project reference."
[[ "$(gcloud config get-value project 2>/dev/null || true)" == "$PROJECT_ID" ]] \
  || die "Set the active gcloud project to $PROJECT_ID."

python3 - "$PROJECT_ID" "$RECOVERY_SECRET" "$EXPECTED_RECOVERY_REF" \
  "$EXPECTED_RESTORE_REF" <<'PY'
from __future__ import annotations

import getpass
import os
import re
import subprocess
import sys
import tempfile
import warnings
from pathlib import Path
from urllib.parse import unquote, urlsplit

project_id, recovery_secret, recovery_ref, restore_ref = sys.argv[1:]

def gcloud(args: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["gcloud", *args], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False
    )

def read_recovery_url() -> str:
    result = gcloud([
        "secrets", "versions", "list", recovery_secret,
        f"--project={project_id}", "--filter=state=ENABLED",
        "--sort-by=~createTime", "--limit=1", "--format=value(name)",
    ])
    if result.returncode != 0:
        raise RuntimeError("could not list enabled recovery database secret versions")
    resource = result.stdout.decode("utf-8", errors="replace").strip()
    version = resource.rsplit("/", 1)[-1]
    if not re.fullmatch(r"[0-9]+", version):
        raise RuntimeError("no enabled numeric recovery database secret version was found")
    result = gcloud([
        "secrets", "versions", "access", version,
        f"--secret={recovery_secret}", f"--project={project_id}",
    ])
    if result.returncode != 0:
        raise RuntimeError("could not read the recovery database secret version")
    value = result.stdout.decode("utf-8").rstrip("\r\n")
    if not value:
        raise RuntimeError("recovery database secret is empty")
    return value

def read_hidden_restore_url() -> str:
    try:
        # This Python process reads its program from a Bash heredoc, so stdin is
        # not the interactive terminal. Use the controlling TTY explicitly and
        # fail closed if getpass would fall back to input that could echo.
        with open("/dev/tty", "w", encoding="utf-8") as tty, warnings.catch_warnings():
            warnings.simplefilter("error", getpass.GetPassWarning)
            return getpass.getpass(
                "Paste the vimj restore PostgreSQL URL (input hidden): ", stream=tty
            )
    except (OSError, getpass.GetPassWarning):
        raise RuntimeError("hidden connection URL input via /dev/tty is unavailable")

def parse_url(label: str, raw_url: str, expected_ref: str) -> dict[str, object]:
    try:
        parsed = urlsplit(raw_url)
        host = parsed.hostname or ""
        port = parsed.port or 5432
        username = unquote(parsed.username or "")
        password = unquote(parsed.password or "")
        database = unquote(parsed.path.lstrip("/"))
    except Exception:
        raise RuntimeError(f"{label} connection URL could not be parsed")
    if parsed.scheme not in {"postgres", "postgresql", "postgresql+psycopg2"}:
        raise RuntimeError(f"{label} URL is not PostgreSQL")
    if not host or not username or not password or not database:
        raise RuntimeError(f"{label} URL is missing a required PostgreSQL connection field")
    if expected_ref.lower() not in (host + " " + username).lower():
        raise RuntimeError(f"{label} URL does not identify the expected Supabase project reference")
    return {
        "host": host, "port": port, "username": username,
        "password": password, "database": database,
    }

SQL = r"""\set ON_ERROR_STOP on
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT 'META', 'transaction_read_only', current_setting('transaction_read_only');
SELECT 'META', 'identity', current_database(), current_user;
SELECT format(
  'SELECT %L::text, %L::text, count(*)::bigint FROM %I.%I;',
  schemaname, tablename, schemaname, tablename
)
FROM pg_catalog.pg_tables
WHERE schemaname = 'public'
ORDER BY tablename
\gexec
SELECT CASE
  WHEN to_regclass('public.alembic_version') IS NULL
    THEN $$SELECT 'META', 'alembic_revision', 'missing';$$
  ELSE $$SELECT 'META', 'alembic_revision', string_agg(version_num, ',' ORDER BY version_num) FROM public.alembic_version;$$
END
\gexec
ROLLBACK;
"""

def pgpass_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace(":", "\\:")

def audit_database(label: str, info: dict[str, object], workdir: Path) -> tuple[dict[str, int], str]:
    passfile = workdir / f"{label}.pgpass"
    line = ":".join(pgpass_escape(str(info[key])) for key in ("host", "port", "database", "username", "password"))
    passfile.write_text(line + "\n", encoding="utf-8")
    passfile.chmod(0o600)

    sql_file = workdir / "audit.sql"
    if not sql_file.exists():
        sql_file.write_text(SQL, encoding="utf-8")
        sql_file.chmod(0o600)

    env = os.environ.copy()
    env.update({
        "PGHOST": str(info["host"]),
        "PGPORT": str(info["port"]),
        "PGDATABASE": str(info["database"]),
        "PGUSER": str(info["username"]),
        "PGSSLMODE": "require",
        "PGCONNECT_TIMEOUT": "15",
        "PGAPPNAME": "vimj-readonly-audit",
        "PGPASSFILE": str(passfile),
    })
    result = subprocess.run(
        ["psql", "--no-psqlrc", "--quiet", "--no-align", "--tuples-only",
         "--field-separator=\t", "--set=ON_ERROR_STOP=1", "--file", str(sql_file)],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False, env=env,
    )
    if result.returncode != 0:
        raise RuntimeError(f"read-only SQL audit failed for {label}; database error details suppressed")

    rows: dict[str, int] = {}
    revision = "missing"
    read_only = False
    identity_matches = False
    for line in result.stdout.decode("utf-8", errors="replace").splitlines():
        fields = line.split("\t")
        if fields[0] == "META":
            if len(fields) >= 3 and fields[1] == "transaction_read_only":
                read_only = fields[2] == "on"
            elif len(fields) >= 4 and fields[1] == "identity":
                # Transaction-pooler roles can report a server-side current_user
                # that differs from the URL username (for example postgres.<ref>).
                # The URL's expected host/user was validated above; verify the
                # database name returned by the live connection here.
                identity_matches = fields[2] == info["database"]
            elif len(fields) >= 3 and fields[1] == "alembic_revision":
                revision = fields[2] or "empty"
        elif len(fields) == 3:
            schema, table, count = fields
            if schema == "public":
                rows[table] = int(count)

    if not read_only:
        raise RuntimeError(f"PostgreSQL did not confirm a read-only transaction for {label}")
    if not identity_matches:
        raise RuntimeError(f"connected database name did not match the {label} connection URL")
    return rows, revision

try:
    if recovery_ref.lower() == restore_ref.lower():
        raise RuntimeError("the two Supabase project references must differ")
    recovery_url = read_recovery_url()
    restore_url = read_hidden_restore_url()
    if not restore_url:
        raise RuntimeError("vimj restore URL was empty")

    recovery = parse_url("recovery", recovery_url, recovery_ref)
    restore = parse_url("vimj restore", restore_url, restore_ref)
    if all(recovery[key] == restore[key] for key in ("host", "port", "database", "username")):
        raise RuntimeError("both connection URLs resolve to the same database identity")

    with tempfile.TemporaryDirectory(prefix="vimj-db-audit-") as temporary_directory:
        workdir = Path(temporary_directory)
        workdir.chmod(0o700)
        recovery_counts, recovery_revision = audit_database("recovery", recovery, workdir)
        restore_counts, restore_revision = audit_database("restore", restore, workdir)

    all_tables = sorted(set(recovery_counts) | set(restore_counts))
    if not all_tables:
        raise RuntimeError("no public tables were found in either database")

    same_tables = set(recovery_counts) == set(restore_counts)
    same_counts = same_tables and all(recovery_counts[name] == restore_counts[name] for name in all_tables)
    print(f"Recovery Alembic revision: {recovery_revision}")
    print(f"vimj restore Alembic revision: {restore_revision}")
    print(f"Public table names match: {'yes' if same_tables else 'no'}")
    print(f"Exact public-table counts match: {'yes' if same_counts else 'no'}")
    print("table\trecovery_rows\trestore_rows\trecovery_minus_restore")
    for table in all_tables:
        recovery_count = recovery_counts.get(table)
        restore_count = restore_counts.get(table)
        difference = (
            str(recovery_count - restore_count)
            if recovery_count is not None and restore_count is not None else "n/a"
        )
        print(
            f"{table}\t{recovery_count if recovery_count is not None else 'MISSING'}\t"
            f"{restore_count if restore_count is not None else 'MISSING'}\t{difference}"
        )
    for table in ("users", "student_attendance", "coach_attendance", "student_fees", "fee_receipts", "coach_salary"):
        print(
            f"CHECK {table}: recovery={recovery_counts.get(table, 'MISSING')} "
            f"vimj_restore={restore_counts.get(table, 'MISSING')}"
        )
    print("No row contents or connection credentials were printed; both sessions rolled back read-only transactions.")
except Exception as exc:
    # Never include command output, connection URLs, or driver error text.
    if isinstance(exc, RuntimeError):
        print(f"BLOCKED: {exc}", file=sys.stderr)
    else:
        print(f"BLOCKED: database audit failed ({type(exc).__name__}); details suppressed.", file=sys.stderr)
    sys.exit(2)
PY
