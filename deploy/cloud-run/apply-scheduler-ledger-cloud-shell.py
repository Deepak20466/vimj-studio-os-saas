#!/usr/bin/env python3
"""Apply only the gated additive 0020 -> 0021 scheduler execution ledger."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import unquote, urlsplit


PROJECT_ID = "vimj-academy"
REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND_DIR = REPO_ROOT / "backend"


def run(args: list[str], *, env=None, cwd=None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, cwd=cwd, check=False)


def require(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        fail(f"Set {name} after reviewing the production database identity and verified backup.")
    return value


def fail(message: str) -> "NoReturn":
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    if os.environ.get("SCHEDULER_SCHEMA_APPROVED") != "YES":
        fail("Set SCHEDULER_SCHEMA_APPROVED=YES only after explicit production schema approval.")
    if os.environ.get("BACKUP_VERIFIED") != "YES":
        fail("A verified, independently stored backup is required before the schema change.")
    if not re.fullmatch(r"[a-f0-9]{64}", require("BACKUP_SHA256")):
        fail("BACKUP_SHA256 must be the verified 64-character SHA-256 checksum.")

    backup_uri = require("BACKUP_URI")
    backup_info = run(["gcloud", "storage", "objects", "describe", backup_uri, "--format=json"])
    if backup_info.returncode != 0:
        fail("The independent backup object could not be verified; no migration was attempted.")
    try:
        metadata = json.loads(backup_info.stdout)
    except Exception:
        fail("The independent backup object metadata could not be parsed.")
    expected_backup_sha = os.environ["BACKUP_SHA256"]
    custom = metadata.get("metadata", {})
    if custom.get("sha256") != expected_backup_sha:
        fail("The backup object's recorded checksum does not match BACKUP_SHA256.")
    expected_identity = hashlib.sha256(
        f"{require('EXPECTED_SUPABASE_HOST').lower()}|{require('EXPECTED_SUPABASE_USER')}|{require('EXPECTED_DATABASE_NAME')}".encode("utf-8")
    ).hexdigest()
    if custom.get("source_identity_sha256") != expected_identity:
        fail("The independent backup was not created from the expected production database identity.")
    generation = str(metadata.get("generation", ""))
    if not generation or not metadata.get("kmsKeyName"):
        fail("The independent backup must have an immutable generation and CMEK encryption.")
    with tempfile.TemporaryDirectory(prefix="vimj-scheduler-backup-verify-") as temporary:
        backup_copy = Path(temporary) / "backup.dump"
        backup_copy.parent.chmod(0o700)
        download = run(["gcloud", "storage", "cp", backup_uri, str(backup_copy), "--quiet"])
        if download.returncode != 0 or not backup_copy.is_file():
            fail("The independent backup could not be read back; no migration was attempted.")
        if sha256_file(backup_copy) != expected_backup_sha:
            fail("The downloaded backup checksum does not match; no migration was attempted.")
    after = run(["gcloud", "storage", "objects", "describe", backup_uri, "--format=json"])
    try:
        current_generation = str(json.loads(after.stdout).get("generation", ""))
    except Exception:
        current_generation = ""
    if after.returncode != 0 or current_generation != generation:
        fail("The verified backup object generation changed; no migration was attempted.")

    project = run(["gcloud", "config", "get-value", "project"])
    if project.returncode != 0 or project.stdout.decode().strip() != PROJECT_ID:
        fail("Set the active gcloud project to vimj-academy.")

    secret_name = os.environ.get("DATABASE_URL_SECRET", "vimj-prod-database-url")
    secret_version = require("DATABASE_URL_SECRET_VERSION")
    if not re.fullmatch(r"[0-9]+", secret_version):
        fail("DATABASE_URL_SECRET_VERSION must be a pinned numeric Secret Manager version.")
    secret = run(
        ["gcloud", "secrets", "versions", "access", secret_version, f"--secret={secret_name}", f"--project={PROJECT_ID}"]
    )
    if secret.returncode != 0:
        fail("Could not read the pinned database URL secret; secret value suppressed.")
    database_url = secret.stdout.decode("utf-8").rstrip("\r\n")
    try:
        parsed = urlsplit(database_url)
        host = (parsed.hostname or "").lower()
        username = unquote(parsed.username or "")
        database = unquote(parsed.path.lstrip("/"))
        port = parsed.port or 5432
    except Exception:
        fail("The database URL format could not be validated; secret value suppressed.")
    if not host.endswith(".pooler.supabase.com") or port != 6543:
        fail("The database secret must use the verified Supabase transaction pooler on port 6543.")
    for variable, actual in (
        ("EXPECTED_SUPABASE_HOST", host),
        ("EXPECTED_SUPABASE_USER", username),
        ("EXPECTED_DATABASE_NAME", database),
    ):
        if actual != require(variable):
            fail(f"{variable} does not match the pinned database secret.")

    child_env = os.environ.copy()
    child_env.update(
        {
            "DATABASE_URL": database_url,
            "ENV": "production",
            "VIMJ_SCHEMA_CHANGE_APPROVED": "YES",
            "EXPECTED_SUPABASE_HOST": host,
            "EXPECTED_SUPABASE_USER": username,
            "EXPECTED_DATABASE_NAME": database,
        }
    )

    def alembic(*args: str) -> subprocess.CompletedProcess[bytes]:
        result = run([sys.executable, "-m", "alembic", "-c", "alembic.ini", *args], env=child_env, cwd=BACKEND_DIR)
        if result.returncode != 0:
            fail(f"Alembic {args[0]} failed; command output suppressed. Stop and inspect before retrying.")
        return result

    preflight = run([sys.executable, "scripts/check_database_readonly.py"], env=child_env, cwd=BACKEND_DIR)
    if preflight.returncode != 0:
        fail("Read-only database identity/table preflight failed; no migration was attempted.")
    print(preflight.stdout.decode("utf-8", errors="replace").rstrip())
    current = alembic("current")
    current_text = current.stdout.decode("utf-8", errors="replace")
    if re.search(r"\b0021\b", current_text):
        print("Scheduler execution-ledger migration is already at revision 0021; no write was performed.")
        return 0
    if not re.search(r"\b0020\b", current_text):
        fail("The current Alembic revision is not exactly 0020; no migration was attempted.")

    confirmation = input("Type APPROVE-SCHEDULER-MIGRATION-0021 to add the scheduler execution ledger: ")
    if confirmation != "APPROVE-SCHEDULER-MIGRATION-0021":
        fail("Migration cancelled; no database change was made.")
    alembic("upgrade", "0021")

    postflight = run([sys.executable, "scripts/check_database_readonly.py"], env=child_env, cwd=BACKEND_DIR)
    if postflight.returncode != 0:
        fail("Post-migration read-only verification failed; stop and inspect before any follow-up.")
    output = postflight.stdout.decode("utf-8", errors="replace")
    if "0021" not in output or "scheduler_job_executions" not in output:
        fail("Post-migration verification did not confirm revision 0021 and the scheduler ledger table.")
    print(output.rstrip())
    print("SCHEDULER_SCHEMA_MIGRATION=PASS (additive 0020 -> 0021; existing business tables untouched)")
    print(f"BACKUP_SHA256={expected_backup_sha}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        fail(str(exc))
