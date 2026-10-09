#!/usr/bin/env bash
# Add a new DATABASE_URL version after the password has already been rotated
# in the intended Supabase project's Dashboard. This script never changes the
# database, prints the URL/password, or disables the previous secret version.
set -Eeuo pipefail
set +x
umask 077

PROJECT_ID="vimj-academy"
SECRET_NAME="vimj-prod-database-url"
EXPECTED_SUPABASE_HOST="${EXPECTED_SUPABASE_HOST:-}"
EXPECTED_SUPABASE_USER="${EXPECTED_SUPABASE_USER:-}"
EXPECTED_DATABASE_NAME="${EXPECTED_DATABASE_NAME:-}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command is unavailable: $1"; }

need gcloud
need python3
[[ -n "$EXPECTED_SUPABASE_HOST" ]] || die "Set EXPECTED_SUPABASE_HOST from the intended Supabase project's Connect panel."
[[ -n "$EXPECTED_SUPABASE_USER" ]] || die "Set EXPECTED_SUPABASE_USER from the intended Supabase project's Connect panel."
[[ -n "$EXPECTED_DATABASE_NAME" ]] || die "Set EXPECTED_DATABASE_NAME from the intended Supabase project's Connect panel."
[[ "$(gcloud config get-value project 2>/dev/null || true)" == "$PROJECT_ID" ]] \
  || die "Set the active gcloud project to $PROJECT_ID."

python3 - "$PROJECT_ID" "$SECRET_NAME" "$EXPECTED_SUPABASE_HOST" \
  "$EXPECTED_SUPABASE_USER" "$EXPECTED_DATABASE_NAME" <<'PY'
from __future__ import annotations

import getpass
import re
import subprocess
import sys
from urllib.parse import quote, unquote, urlsplit, urlunsplit

project_id, secret_name, expected_host, expected_user, expected_database = sys.argv[1:]

def gcloud(args: list[str], *, input_bytes: bytes | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["gcloud", *args],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )

if not sys.stdin.isatty():
    raise SystemExit("ERROR: run this from an interactive Cloud Shell terminal so password entry stays hidden.")

versions = gcloud([
    "secrets", "versions", "list", secret_name, f"--project={project_id}",
    "--filter=state=ENABLED", "--sort-by=~createTime", "--limit=1", "--format=value(name)",
])
if versions.returncode != 0:
    raise SystemExit("ERROR: could not list enabled database URL secret versions.")
version_resource = versions.stdout.decode("utf-8", errors="replace").strip()
current_version = version_resource.rsplit("/", 1)[-1]
if not re.fullmatch(r"[0-9]+", current_version):
    raise SystemExit("ERROR: no enabled numeric database URL secret version was found.")

current = gcloud([
    "secrets", "versions", "access", current_version,
    f"--secret={secret_name}", f"--project={project_id}",
])
if current.returncode != 0:
    raise SystemExit("ERROR: could not read the current database URL secret version.")
database_url = current.stdout.decode("utf-8").rstrip("\r\n")
try:
    parsed = urlsplit(database_url)
    raw_userinfo, raw_hostport = parsed.netloc.rsplit("@", 1)
    raw_username, separator, _old_password = raw_userinfo.partition(":")
    username = unquote(raw_username)
    database = unquote(parsed.path.lstrip("/"))
    port = parsed.port
except Exception:
    raise SystemExit("ERROR: stored DATABASE_URL format could not be validated; no new version was written.")

if parsed.scheme not in {"postgres", "postgresql", "postgresql+psycopg2"}:
    raise SystemExit("ERROR: stored DATABASE_URL is not PostgreSQL; no new version was written.")
if parsed.hostname != expected_host or port != 6543:
    raise SystemExit("ERROR: stored DATABASE_URL host/port does not match the expected Supabase transaction pooler.")
if username != expected_user or database != expected_database or not separator:
    raise SystemExit("ERROR: stored DATABASE_URL user/database identity does not match the expected recovery database.")

confirmation = input(
    "After confirming the Supabase password was rotated for this exact project, type PASSWORD-ROTATED: "
)
if confirmation != "PASSWORD-ROTATED":
    raise SystemExit("Cancelled; Secret Manager was not changed.")

new_password = getpass.getpass("Enter the new Supabase database password (input hidden): ")
if len(new_password) < 24 or "\n" in new_password or "\r" in new_password:
    raise SystemExit("ERROR: enter a password of at least 24 characters; no secret version was written.")
confirmation_password = getpass.getpass("Re-enter the new password (input hidden): ")
if new_password != confirmation_password:
    raise SystemExit("ERROR: passwords did not match; no secret version was written.")

if "@" not in parsed.netloc:
    raise SystemExit("ERROR: stored DATABASE_URL credentials could not be reconstructed safely.")
new_netloc = f"{raw_username}:{quote(new_password, safe='')}@{raw_hostport}"
updated_url = urlunsplit((parsed.scheme, new_netloc, parsed.path, parsed.query, parsed.fragment))

result = gcloud([
    "secrets", "versions", "add", secret_name,
    f"--project={project_id}", "--data-file=-",
], input_bytes=updated_url.encode("utf-8"))
if result.returncode != 0:
    raise SystemExit("ERROR: Secret Manager did not accept a new version; output suppressed.")

created = re.search(rb"versions/([0-9]+)", result.stdout)
if created:
    print(f"Secret Manager database URL updated: version {created.group(1).decode()} (secret value not displayed).")
else:
    print("Secret Manager accepted a new database URL version; verify its version number with `gcloud secrets versions list`.")
print("The previous secret version remains enabled. No database SQL, migrations, or Render changes were made.")
PY
