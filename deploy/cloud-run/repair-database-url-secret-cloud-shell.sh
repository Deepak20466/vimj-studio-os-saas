#!/usr/bin/env bash
# Add and verify a corrected recovery DATABASE_URL without changing the DB.
set -Eeuo pipefail
set +x
umask 077

PROJECT_ID="vimj-academy"
SECRET_NAME="vimj-prod-database-url"

need() { command -v "$1" >/dev/null 2>&1 || { printf 'ERROR: required command is unavailable: %s\n' "$1" >&2; exit 1; }; }
need gcloud
need python3
need psql

[[ "$(gcloud config get-value project 2>/dev/null || true)" == "$PROJECT_ID" ]] \
  || { printf 'ERROR: set the active gcloud project to %s.\n' "$PROJECT_ID" >&2; exit 1; }

read -r -p 'Recovery Supabase project reference (visible): ' EXPECTED_RECOVERY_REF
[[ -n "$EXPECTED_RECOVERY_REF" ]] || { printf 'ERROR: project reference is required.\n' >&2; exit 1; }
export EXPECTED_RECOVERY_REF

python3 - "$PROJECT_ID" "$SECRET_NAME" <<'PY'
from __future__ import annotations

import getpass
import json
import os
import re
import subprocess
import sys
import tempfile
import warnings
from pathlib import Path
from urllib.parse import unquote, urlsplit

project_id, secret_name = sys.argv[1:]
expected_ref = os.environ.get("EXPECTED_RECOVERY_REF", "").strip()


class SafeStop(Exception):
    pass


def gcloud(args: list[str], input_bytes: bytes | None = None) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            ["gcloud", *args], input=input_bytes, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, check=False,
        )
    except OSError:
        raise SafeStop("gcloud could not be run; secret values were not displayed")


def get_enabled_version() -> str:
    result = gcloud([
        "secrets", "versions", "list", secret_name,
        f"--project={project_id}", "--filter=state=ENABLED",
        "--sort-by=~createTime", "--limit=1", "--format=value(name)",
    ])
    if result.returncode != 0:
        raise SafeStop("could not list the enabled database URL version")
    version = result.stdout.decode("utf-8", "replace").strip().rsplit("/", 1)[-1]
    if not re.fullmatch(r"[0-9]+", version):
        raise SafeStop("no enabled numeric database URL version was found")
    return version


def get_version_ids() -> set[str]:
    result = gcloud([
        "secrets", "versions", "list", secret_name,
        f"--project={project_id}", "--format=value(name)",
    ])
    if result.returncode != 0:
        raise SafeStop("could not enumerate database URL version IDs")
    ids = {
        line.strip().rsplit("/", 1)[-1]
        for line in result.stdout.decode("utf-8", "replace").splitlines()
        if line.strip()
    }
    if any(not re.fullmatch(r"[0-9]+", version) for version in ids):
        raise SafeStop("Secret Manager returned an unexpected version identifier")
    return ids


def read_version(version: str) -> str:
    result = gcloud([
        "secrets", "versions", "access", version,
        f"--secret={secret_name}", f"--project={project_id}",
    ])
    if result.returncode != 0:
        raise SafeStop(f"could not access secret version {version}")
    return result.stdout.decode("utf-8").rstrip("\r\n")


def parse_url(raw: str, *, expected_path: str | None = None):
    try:
        parsed = urlsplit(raw)
        host = (parsed.hostname or "").lower()
        port = parsed.port
        username = unquote(parsed.username or "")
        password = unquote(parsed.password or "")
    except Exception:
        raise SafeStop("database URL structure is invalid")
    if (
        parsed.scheme not in {"postgres", "postgresql", "postgresql+psycopg2"}
        or not host or not username or not password or port != 6543
        or parsed.fragment or raw != raw.strip()
        or any(character.isspace() for character in raw)
    ):
        raise SafeStop("database URL must be PostgreSQL on the transaction pooler at port 6543")
    if expected_path is not None and parsed.path != expected_path:
        raise SafeStop("database URL path must be exactly /postgres")
    if expected_ref.lower() not in (host + " " + username).lower():
        raise SafeStop("database URL does not identify the expected recovery project")
    return parsed, host, port, username, password


def read_hidden_url() -> str:
    try:
        # stdin carries this heredoc; getpass must use the controlling terminal.
        # Convert fallback warnings to errors so input can never echo via stdin.
        with open("/dev/tty", "w", encoding="utf-8") as tty, warnings.catch_warnings():
            warnings.simplefilter("error", getpass.GetPassWarning)
            return getpass.getpass(
                "Paste the corrected recovery DATABASE_URL (input hidden): ",
                stream=tty,
            )
    except (OSError, getpass.GetPassWarning):
        raise SafeStop("hidden URL input via /dev/tty is unavailable")


def pgpass_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace(":", "\\:")


try:
    if not expected_ref:
        raise SafeStop("the recovery project reference is required")

    # Validate the existing secret's authority before accepting a replacement.
    current_version = get_enabled_version()
    current_url = read_version(current_version)
    _, current_host, current_port, current_user, _ = parse_url(current_url)

    new_url = read_hidden_url()
    _, new_host, new_port, new_user, new_password = parse_url(
        new_url, expected_path="/postgres"
    )
    if (new_host, new_port, new_user) != (current_host, current_port, current_user):
        raise SafeStop("new URL host, username, or port differs from the current recovery target")

    versions_before = get_version_ids()
    added = gcloud([
        "secrets", "versions", "add", secret_name,
        f"--project={project_id}", "--data-file=-",
    ], input_bytes=new_url.encode("utf-8"))
    if added.returncode != 0:
        raise SafeStop("Secret Manager did not accept a new version; previous versions remain unchanged")

    # Identify the new immutable version by set difference, not by a latest alias.
    versions_after = get_version_ids()
    new_versions = versions_after - versions_before
    if len(new_versions) != 1:
        raise SafeStop("version was added, but a single new version ID could not be isolated; no version was deleted")
    new_version = new_versions.pop()

    state = gcloud([
        "secrets", "versions", "describe", new_version,
        f"--secret={secret_name}", f"--project={project_id}", "--format=value(state)",
    ])
    if state.returncode != 0 or state.stdout.decode("utf-8", "replace").strip() != "ENABLED":
        raise SafeStop(f"new version {new_version} was identified but is not confirmed enabled; it was not deleted")

    stored_url = read_version(new_version)
    if stored_url != new_url:
        raise SafeStop(f"new version {new_version} did not match the submitted URL; it was not deleted")
    _, host, port, username, password = parse_url(
        stored_url, expected_path="/postgres"
    )
    if (host, port, username) != (current_host, current_port, current_user):
        raise SafeStop(f"new version {new_version} failed target validation; it was not deleted")

    with tempfile.TemporaryDirectory(prefix="vimj-url-check-") as temporary_directory:
        workdir = Path(temporary_directory)
        workdir.chmod(0o700)
        passfile = workdir / "pgpass"
        passfile.write_text(
            ":".join(pgpass_escape(value) for value in (
                host, str(port), "postgres", username, password
            )) + "\n",
            encoding="utf-8",
        )
        passfile.chmod(0o600)

        env = os.environ.copy()
        env.update({
            "PGHOST": host, "PGPORT": str(port), "PGDATABASE": "postgres",
            "PGUSER": username, "PGPASSFILE": str(passfile),
            "PGSSLMODE": "require", "PGCONNECT_TIMEOUT": "15",
            "PGAPPNAME": "vimj-readonly-secret-check",
        })
        sql = (
            "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY; "
            "SELECT json_build_array(current_database(), "
            "current_setting('transaction_read_only'))::text; ROLLBACK;"
        )
        check = subprocess.run(
            ["psql", "--no-psqlrc", "--quiet", "--no-align", "--tuples-only",
             "--set=ON_ERROR_STOP=1", "--command", sql],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            check=False, env=env,
        )
        if check.returncode != 0:
            raise SafeStop(
                f"new version {new_version} URL structure passed, but read-only connectivity failed; version remains enabled"
            )
        rows = [line for line in check.stdout.decode("utf-8", "replace").splitlines() if line]
        try:
            identity = json.loads(rows[0]) if len(rows) == 1 else None
        except Exception:
            identity = None
        if identity != ["postgres", "on"]:
            raise SafeStop(
                f"new version {new_version} connected, but the read-only database check failed; version remains enabled"
            )

    print(f"New secret version {new_version}: URL structure PASS; read-only connectivity PASS.")
    print("Previous versions were left unchanged. No database records or schema were modified.")
except SafeStop as exc:
    print(f"BLOCKED: {exc}", file=sys.stderr)
    sys.exit(2)
except Exception as exc:
    print(f"BLOCKED: operation failed ({type(exc).__name__}); details suppressed.", file=sys.stderr)
    sys.exit(2)
PY
