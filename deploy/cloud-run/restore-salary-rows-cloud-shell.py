#!/usr/bin/env python3
"""Safely recover legacy coach_salary rows from a separate Supabase project.

The source connection is read-only. The target must already have the additive
0020 table and an empty salary ledger. Existing exact data is left untouched;
partial/nonmatching ledgers stop for manual reconciliation. No rows are deleted.
"""

from __future__ import annotations

import getpass
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import warnings
from pathlib import Path
from urllib.parse import unquote, urlsplit


PROJECT_ID = "vimj-academy"
REQUIRED_COLUMNS = {
    "id", "coach_id", "month", "year", "amount", "notified_at",
    "acknowledged_date", "created_at",
}


def run(args: list[str], *, env=None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
        env=env,
    )


def fail(message: str) -> "NoReturn":
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        fail(f"Set {name} in Cloud Shell after reviewing the recovery evidence.")
    return value


def parse_url(label: str, raw_url: str, expected_ref: str, *, require_session: bool) -> dict[str, object]:
    try:
        parsed = urlsplit(raw_url)
        host = (parsed.hostname or "").lower()
        username = unquote(parsed.username or "")
        password = unquote(parsed.password or "")
        database = unquote(parsed.path.lstrip("/"))
        port = parsed.port or 5432
    except Exception:
        fail(f"{label} database URL could not be validated; URL contents suppressed.")
    if parsed.scheme not in {"postgres", "postgresql", "postgresql+psycopg2"}:
        fail(f"{label} URL is not PostgreSQL; URL contents suppressed.")
    if not all((host, username, password, database)) or expected_ref.lower() not in (host + " " + username).lower():
        fail(f"{label} URL does not identify the expected Supabase project/database.")
    if not host.endswith(".pooler.supabase.com"):
        fail(f"{label} URL must use the Supabase session pooler.")
    if require_session and port != 5432:
        fail(f"{label} URL must use the Supabase session pooler on port 5432.")
    if not require_session and port not in {5432, 6543}:
        fail(f"{label} URL must use a supported Supabase pooler port.")
    return {
        "host": host,
        "username": username,
        "password": password,
        "database": database,
        "port": 5432,
    }


def pgpass_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace(":", "\\:")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_backup(backup_uri: str, expected_sha: str) -> str:
    info = run(["gcloud", "storage", "objects", "describe", backup_uri, "--format=json"])
    if info.returncode != 0:
        fail("The independent backup object could not be verified; no salary data was changed.")
    try:
        metadata = json.loads(info.stdout)
    except Exception:
        fail("The independent backup metadata could not be parsed; no salary data was changed.")
    generation = str(metadata.get("generation", ""))
    if (
        metadata.get("metadata", {}).get("sha256") != expected_sha
        or not generation
        or not metadata.get("kmsKeyName")
    ):
        fail("The independent backup checksum, generation, or CMEK metadata did not verify.")
    source_identity_sha = str(metadata.get("metadata", {}).get("source_identity_sha256", ""))
    if not re.fullmatch(r"[a-f0-9]{64}", source_identity_sha):
        fail("The independent backup is missing its database identity fingerprint.")
    with tempfile.TemporaryDirectory(prefix="vimj-salary-backup-check-") as temporary:
        copy = Path(temporary) / "backup.dump"
        downloaded = run(["gcloud", "storage", "cp", backup_uri, str(copy), "--quiet"])
        if downloaded.returncode != 0 or not copy.is_file() or sha256_file(copy) != expected_sha:
            fail("The independent backup readback SHA-256 did not match; no salary data was changed.")
    after = run(["gcloud", "storage", "objects", "describe", backup_uri, "--format=json"])
    try:
        generation_after = str(json.loads(after.stdout).get("generation", ""))
    except Exception:
        generation_after = ""
    if after.returncode != 0 or generation_after != generation:
        fail("The backup generation changed during verification; no salary data was changed.")
    return source_identity_sha


def configure_connection(path: Path, info: dict[str, object]) -> dict[str, str]:
    path.write_text(
        ":".join(
            pgpass_escape(str(info[key]))
            for key in ("host", "port", "database", "username", "password")
        ) + "\n",
        encoding="utf-8",
    )
    path.chmod(0o600)
    return {
        "PGPASSFILE": str(path),
        "PGSSLMODE": "require",
        "PGCONNECT_TIMEOUT": "15",
        "PGAPPNAME": "vimj-salary-recovery",
    }


def psql(info: dict[str, object], env: dict[str, str], sql: str) -> str:
    result = run(
        [
            "psql", "--no-psqlrc", "--no-password", "-XAt", "--field-separator=|",
            "--set=ON_ERROR_STOP=1", "--host", str(info["host"]), "--port", "5432",
            "--username", str(info["username"]), "--dbname", str(info["database"]),
            "--command", sql,
        ],
        env=env,
    )
    if result.returncode != 0:
        fail("A database read-only check failed; connection details and SQL output suppressed.")
    return result.stdout.decode("utf-8", errors="replace").strip()


def table_columns(info: dict[str, object], env: dict[str, str]) -> set[str]:
    sql = (
        "BEGIN TRANSACTION READ ONLY; "
        "SELECT column_name FROM information_schema.columns "
        "WHERE table_schema='public' AND table_name='coach_salary' ORDER BY ordinal_position; "
        "ROLLBACK;"
    )
    output = psql(info, env, sql)
    return set(output.splitlines()) if output else set()


def salary_fingerprint(info: dict[str, object], env: dict[str, str]) -> tuple[int, str]:
    sql = r"""
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT count(*)::text || '|' || encode(
  sha256(convert_to(coalesce(string_agg(row_hash, '' ORDER BY row_hash), ''), 'UTF8')),
  'hex'
)
FROM (
  SELECT encode(sha256(convert_to(to_jsonb(row_data)::text, 'UTF8')), 'hex') AS row_hash
  FROM public.coach_salary AS row_data
) AS hashed_rows;
ROLLBACK;
"""
    output = psql(info, env, sql)
    match = re.fullmatch(r"([0-9]+)\|([a-f0-9]{64})", output)
    if not match:
        fail("Could not validate the salary ledger fingerprint; no data was changed.")
    return int(match.group(1)), match.group(2)


def main() -> int:
    if os.environ.get("BACKUP_VERIFIED") != "YES":
        fail("A verified independent database backup is required before salary recovery.")
    backup_sha = required("BACKUP_SHA256")
    if not re.fullmatch(r"[a-f0-9]{64}", backup_sha):
        fail("BACKUP_SHA256 must be a verified 64-character checksum.")
    backup_source_identity_sha = verify_backup(required("BACKUP_URI"), backup_sha)
    if os.environ.get("SALARY_ROWS_RESTORE_APPROVED") != "YES":
        fail("Set SALARY_ROWS_RESTORE_APPROVED=YES only after approving salary-row recovery into production.")
    if not sys.stdin.isatty():
        fail("Run interactively in Cloud Shell so the source URL and restore approval stay hidden/explicit.")

    project = run(["gcloud", "config", "get-value", "project"])
    if project.returncode != 0 or project.stdout.decode().strip() != PROJECT_ID:
        fail("Set the active gcloud project to vimj-academy.")
    secret_name = os.environ.get("DATABASE_URL_SECRET", "vimj-prod-database-url")
    secret_version = required("DATABASE_URL_SECRET_VERSION")
    if not re.fullmatch(r"[0-9]+", secret_version):
        fail("DATABASE_URL_SECRET_VERSION must be a pinned numeric Secret Manager version.")
    target_result = run([
        "gcloud", "secrets", "versions", "access", secret_version,
        f"--secret={secret_name}", f"--project={PROJECT_ID}",
    ])
    if target_result.returncode != 0:
        fail("Could not read the pinned target database secret; secret contents suppressed.")
    target_url = target_result.stdout.decode("utf-8").rstrip("\r\n")
    target_ref = required("EXPECTED_TARGET_SUPABASE_REF")
    source_ref = required("EXPECTED_SOURCE_SUPABASE_REF")
    if source_ref.lower() == target_ref.lower():
        fail("Source and target Supabase project references must differ.")

    target = parse_url("target", target_url, target_ref, require_session=False)
    target_identity_sha = hashlib.sha256(
        f"{target['host']}|{target['username']}|{target['database']}".encode("utf-8")
    ).hexdigest()
    if target_identity_sha != backup_source_identity_sha:
        fail("The independent backup was not created from this target database identity.")
    try:
        with open("/dev/tty", "w", encoding="utf-8") as tty, warnings.catch_warnings():
            warnings.simplefilter("error", getpass.GetPassWarning)
            source_url = getpass.getpass("Paste the read-only recovery Supabase session-pooler URL (input hidden): ", stream=tty)
    except (OSError, getpass.GetPassWarning):
        fail("Hidden source URL input is unavailable; no database was changed.")
    source = parse_url("source", source_url, source_ref, require_session=True)
    if (source["host"], source["database"], source["username"]) == (
        target["host"], target["database"], target["username"]
    ):
        fail("Source and target connections resolve to the same database identity.")

    with tempfile.TemporaryDirectory(prefix="vimj-salary-recovery-") as temporary:
        work = Path(temporary)
        work.chmod(0o700)
        source_env = os.environ.copy()
        source_env.update(configure_connection(work / "source.pgpass", source))
        target_env = os.environ.copy()
        target_env.update(configure_connection(work / "target.pgpass", target))

        source_revision = psql(
            source,
            source_env,
            "BEGIN TRANSACTION READ ONLY; SELECT string_agg(version_num, ',') FROM public.alembic_version; ROLLBACK;",
        )
        target_revision = psql(
            target,
            target_env,
            "BEGIN TRANSACTION READ ONLY; SELECT string_agg(version_num, ',') FROM public.alembic_version; ROLLBACK;",
        )
        if not re.fullmatch(r"[0-9]{4}", source_revision):
            fail("The recovery source schema revision is unexpected; no data was changed.")
        if target_revision != "0020":
            fail("The target must first pass the approved additive migration to revision 0020.")

        source_columns = table_columns(source, source_env)
        target_columns = table_columns(target, target_env)
        if source_columns and source_columns != REQUIRED_COLUMNS:
            fail("The recovery source salary table has an unexpected shape; preserve it for manual review.")
        if target_columns != REQUIRED_COLUMNS:
            fail("The target salary table is missing required columns; no data was changed.")
        if not source_columns:
            fail("The selected recovery database has no coach_salary table; select the verified salary source.")
        target_sequence = psql(
            target,
            target_env,
            "BEGIN TRANSACTION READ ONLY; "
            "SELECT coalesce(pg_get_serial_sequence('public.coach_salary', 'id'), ''); ROLLBACK;",
        )
        if not target_sequence:
            fail("The target salary ID column has no sequence; stop for schema review before importing rows.")

        source_count, source_hash = salary_fingerprint(source, source_env)
        target_count, target_hash = salary_fingerprint(target, target_env)
        duplicates = psql(
            source,
            source_env,
            "BEGIN TRANSACTION READ ONLY; "
            "SELECT EXISTS(SELECT 1 FROM public.coach_salary "
            "GROUP BY coach_id, month, year HAVING count(*) > 1); ROLLBACK;",
        )
        if duplicates.lower() == "t":
            fail("The recovery salary ledger contains duplicate coach/month/year rows; no data was changed.")
        if source_count == target_count and source_hash == target_hash:
            print(f"SALARY_RECONCILIATION=PASS (existing target already matches; rows={target_count}; no write)")
            return 0
        if source_count == 0 and target_count == 0:
            print("SALARY_RECONCILIATION=CONFIRMED_EMPTY (source and target have no salary rows; no write)")
            return 0
        if target_count != 0:
            fail("Source and target salary ledgers differ and target is not empty; no rows changed; manual reconciliation is required.")
        if source_count == 0:
            fail("Recovery source is empty while target has rows; no rows changed; verify the source project.")

        confirmation = input("Type APPROVE-RESTORE-SALARY-ROWS to copy the verified source ledger into the empty target: ")
        if confirmation != "APPROVE-RESTORE-SALARY-ROWS":
            fail("Salary-row restoration cancelled; no data was changed.")
        archive = work / "coach-salary.dump"
        dump = run([
            "pg_dump", "--no-password", "--host", str(source["host"]), "--port", "5432",
            "--username", str(source["username"]), "--dbname", str(source["database"]),
            "--format=custom", "--data-only", "--table=public.coach_salary",
            "--no-owner", "--no-acl", "--file", str(archive),
        ], env=source_env)
        if dump.returncode != 0 or not archive.is_file() or archive.stat().st_size == 0:
            fail("Could not create the protected salary transfer archive; no target data was changed.")
        toc = run(["pg_restore", "--list", str(archive)])
        if toc.returncode != 0 or b"TABLE DATA public coach_salary" not in toc.stdout:
            fail("The salary transfer archive did not contain the expected table data; target unchanged.")
        source_count_after_dump, source_hash_after_dump = salary_fingerprint(source, source_env)
        if source_count_after_dump != source_count or source_hash_after_dump != source_hash:
            fail("The recovery source changed while the transfer archive was being prepared; target unchanged.")
        target_count_before_restore, target_hash_before_restore = salary_fingerprint(target, target_env)
        if target_count_before_restore != 0 or target_hash_before_restore != target_hash:
            fail("The target salary ledger changed during preflight; target was not modified by this script.")
        restored = run([
            "pg_restore", "--no-password", "--host", str(target["host"]), "--port", "5432",
            "--username", str(target["username"]), "--dbname", str(target["database"]),
            "--single-transaction", "--exit-on-error", "--data-only",
            "--table=public.coach_salary", str(archive),
        ], env=target_env)
        if restored.returncode != 0:
            fail("Atomic salary data restore failed and rolled back; inspect before retrying.")
        sequence_update = psql(
            target,
            target_env,
            "SELECT setval(pg_get_serial_sequence('public.coach_salary', 'id'), "
            "COALESCE((SELECT max(id) FROM public.coach_salary), 1), "
            "EXISTS(SELECT 1 FROM public.coach_salary));",
        )
        if not sequence_update:
            fail("Salary rows were imported but the ID sequence could not be confirmed; stop before further writes.")
        final_count, final_hash = salary_fingerprint(target, target_env)
        if final_count != source_count or final_hash != source_hash:
            fail("Post-restore salary fingerprint differs; preserve both ledgers and stop for manual review.")
        digest = sha256_file(archive)
        print(f"SALARY_RECONCILIATION=PASS (restored and verified exact row set; rows={final_count})")
        print(f"SALARY_TRANSFER_SHA256={digest}")
        print(f"BACKUP_SHA256={backup_sha}")
        return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        fail(str(exc))
