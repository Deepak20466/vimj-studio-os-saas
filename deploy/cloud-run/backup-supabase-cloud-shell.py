#!/usr/bin/env python3
"""Create a logical public-schema backup and verify an independent GCS copy.

The source password is read from Secret Manager and used only in a temporary
owner-only .pgpass file. The archive includes all public rows and bytea photo
data. No SQL is written to the source database.
"""

from __future__ import annotations

import datetime as dt
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
_PROJECT_NUMBER_RE = re.compile(r"[0-9]+")
_KMS_KEY_RE = re.compile(
    r"projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+"
)


def run(args: list[str], *, capture: bool = True, env=None) -> subprocess.CompletedProcess:
    return subprocess.run(
        args,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        check=False,
        env=env,
    )


def fail(message: str) -> "NoReturn":
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        fail(f"Set {name} in the Cloud Shell session.")
    return value


def pgpass_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace(":", "\\:")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def project_metadata_command(project_id: str) -> list[str]:
    """Return the authoritative Resource Manager project metadata request."""
    return ["gcloud", "projects", "describe", project_id, "--format=json"]


def bucket_metadata_command(bucket: str) -> list[str]:
    """Request the raw Cloud Storage API bucket representation from gcloud."""
    return [
        "gcloud", "storage", "buckets", "describe", f"gs://{bucket}",
        "--raw", "--format=json",
    ]


def parse_project_number(raw: bytes, expected_project_id: str, label: str) -> str:
    try:
        metadata = json.loads(raw)
    except (TypeError, ValueError):
        fail(f"Could not parse authoritative {label} project metadata.")
    if not isinstance(metadata, dict):
        fail(f"Could not parse authoritative {label} project metadata.")
    project_id = metadata.get("projectId")
    project_number = str(metadata.get("projectNumber", ""))
    if project_id != expected_project_id or not _PROJECT_NUMBER_RE.fullmatch(project_number):
        fail(f"Could not verify the {label} project ID and project number.")
    if metadata.get("lifecycleState") != "ACTIVE":
        fail(f"The {label} Google Cloud project is not confirmed ACTIVE.")
    return project_number


def verify_bucket_metadata(
    raw: bytes,
    *,
    expected_bucket: str,
    source_project_number: str,
    backup_project_id: str,
    backup_project_number: str,
) -> str:
    """Verify raw bucket ownership and its default CMEK; return the key name."""
    try:
        bucket = json.loads(raw)
    except (TypeError, ValueError):
        fail("Could not inspect the backup bucket metadata.")
    if not isinstance(bucket, dict) or bucket.get("name") != expected_bucket:
        fail("The Cloud Storage response did not identify the expected backup bucket.")

    bucket_project_number = str(bucket.get("projectNumber", ""))
    if not _PROJECT_NUMBER_RE.fullmatch(bucket_project_number):
        fail("Raw Cloud Storage bucket metadata did not include a valid owner project number.")
    if backup_project_id == PROJECT_ID or backup_project_number == source_project_number:
        fail("The expected backup project must be distinct from vimj-academy.")
    if bucket_project_number != backup_project_number:
        fail("The backup bucket is not owned by the reviewed backup Google Cloud project.")
    if bucket_project_number == source_project_number:
        fail("The backup bucket must belong to a different Google Cloud project.")

    encryption = bucket.get("encryption")
    kms_key = encryption.get("defaultKmsKeyName") if isinstance(encryption, dict) else None
    if not isinstance(kms_key, str) or not _KMS_KEY_RE.fullmatch(kms_key):
        fail("The independent bucket must have a valid default Cloud KMS encryption key configured.")
    return kms_key


def main() -> int:
    secret_name = os.environ.get("DATABASE_URL_SECRET", "vimj-prod-database-url")
    secret_version = required("DATABASE_URL_SECRET_VERSION")
    expected_host = required("EXPECTED_SUPABASE_HOST").lower()
    expected_user = required("EXPECTED_SUPABASE_USER")
    expected_database = required("EXPECTED_DATABASE_NAME")
    bucket_prefix = required("BACKUP_BUCKET_URI").rstrip("/")
    if os.environ.get("BACKUP_TRANSFER_APPROVED") != "YES":
        fail("Approve the encrypted cross-project backup copy by setting BACKUP_TRANSFER_APPROVED=YES.")
    if not re.fullmatch(r"[0-9]+", secret_version):
        fail("DATABASE_URL_SECRET_VERSION must be a pinned numeric Secret Manager version.")
    if not bucket_prefix.startswith("gs://") or bucket_prefix.count("/") < 3:
        fail("BACKUP_BUCKET_URI must be a gs://bucket/prefix URI.")

    active_project = run(["gcloud", "config", "get-value", "project"])
    if active_project.returncode != 0 or active_project.stdout.decode().strip() != PROJECT_ID:
        fail("Set the active gcloud project to vimj-academy.")
    source_project = run(project_metadata_command(PROJECT_ID))
    if source_project.returncode != 0:
        fail("Could not verify the source Google Cloud project.")
    source_project_number = parse_project_number(source_project.stdout, PROJECT_ID, "source")

    backup_project_id = required("EXPECTED_BACKUP_PROJECT_ID")
    if backup_project_id == PROJECT_ID:
        fail("EXPECTED_BACKUP_PROJECT_ID must differ from vimj-academy.")
    backup_project = run(project_metadata_command(backup_project_id))
    if backup_project.returncode != 0:
        fail("Could not verify the expected backup Google Cloud project.")
    backup_project_number = parse_project_number(
        backup_project.stdout, backup_project_id, "backup"
    )
    if backup_project_number == source_project_number:
        fail("The backup project number must differ from vimj-academy.")

    bucket = bucket_prefix[5:].split("/", 1)[0]
    bucket_info = run(bucket_metadata_command(bucket))
    if bucket_info.returncode != 0:
        fail("The pre-existing backup bucket is not accessible; this script will not create a bucket.")
    kms_key = verify_bucket_metadata(
        bucket_info.stdout,
        expected_bucket=bucket,
        source_project_number=source_project_number,
        backup_project_id=backup_project_id,
        backup_project_number=backup_project_number,
    )

    secret = run(
        [
            "gcloud", "secrets", "versions", "access", secret_version,
            f"--secret={secret_name}", f"--project={PROJECT_ID}",
        ]
    )
    if secret.returncode != 0:
        fail("Could not read the pinned database URL secret version; secret value suppressed.")
    database_url = secret.stdout.decode("utf-8").rstrip("\r\n")
    try:
        parsed = urlsplit(database_url)
        username = unquote(parsed.username or "")
        password = unquote(parsed.password or "")
        host = (parsed.hostname or "").lower()
        database = unquote(parsed.path.lstrip("/"))
        source_port = parsed.port or 5432
    except Exception:
        fail("The database URL secret format could not be validated; secret value suppressed.")
    if parsed.scheme not in {"postgres", "postgresql", "postgresql+psycopg2"}:
        fail("The configured database URL is not PostgreSQL; secret value suppressed.")
    if host != expected_host or not host.endswith(".pooler.supabase.com"):
        fail("The Supabase database host does not match the expected recovery project.")
    if username != expected_user or database != expected_database:
        fail("The database user/name do not match the expected recovery database.")
    if source_port not in {5432, 6543} or not password:
        fail("The database URL does not contain supported Supabase pooler credentials.")
    source_identity_sha = hashlib.sha256(
        f"{host}|{username}|{database}".encode("utf-8")
    ).hexdigest()

    object_name = f"vimj-public-{dt.datetime.now(dt.timezone.utc):%Y%m%dT%H%M%SZ}-{os.urandom(4).hex()}.dump"
    remote_uri = f"{bucket_prefix}/{object_name}"
    with tempfile.TemporaryDirectory(prefix="vimj-supabase-backup-") as temporary:
        work = Path(temporary)
        work.chmod(0o700)
        pgpass = work / ".pgpass"
        pgpass.write_text(
            ":".join(
                map(
                    pgpass_escape,
                    [host, "5432", database, username, password],
                )
            )
            + "\n",
            encoding="utf-8",
        )
        pgpass.chmod(0o600)
        archive = work / object_name
        pg_env = os.environ.copy()
        pg_env.update({"PGPASSFILE": str(pgpass), "PGSSLMODE": "require"})
        status = run(
            [
                "psql", "--no-psqlrc", "-XAt", "--no-password", "--host", host,
                "--port", "5432", "--username", username, "--dbname", database,
                "--command", "SELECT version_num || '|' || current_setting('server_version') FROM public.alembic_version",
            ],
            env=pg_env,
        )
        if status.returncode != 0:
            fail("Could not read the database revision/server version before backup; details suppressed.")
        revision_status = status.stdout.decode("utf-8", errors="replace").strip().splitlines()
        if len(revision_status) != 1 or "|" not in revision_status[0]:
            fail("The database must report exactly one Alembic revision before backup.")
        source_revision, server_version = revision_status[0].split("|", 1)
        if not re.fullmatch(r"[0-9]{4}", source_revision):
            fail("The live Alembic revision is not a recognized four-digit revision.")
        client_version = run(["pg_dump", "--version"])
        version_match = re.search(rb"\b([0-9]+)(?:\.[0-9]+)?\b", client_version.stdout)
        server_match = re.search(r"\b([0-9]+)(?:\.[0-9]+)?\b", server_version)
        if not version_match or not server_match or int(version_match.group(1)) < int(server_match.group(1)):
            fail("Use a pg_dump client at least as new as the PostgreSQL server before backing up.")
        dump = run(
            [
                "pg_dump", "--no-password", "--host", host, "--port", "5432",
                "--username", username, "--dbname", database, "--format=custom",
                "--schema=public", "--no-owner", "--no-acl", "--file", str(archive),
            ],
            env=pg_env,
        )
        if dump.returncode != 0 or not archive.is_file() or archive.stat().st_size == 0:
            fail("pg_dump did not produce a valid non-empty archive; database details suppressed.")
        toc = run(["pg_restore", "--list", str(archive)])
        if toc.returncode != 0 or b"TABLE DATA" not in toc.stdout:
            fail("The PostgreSQL archive table-of-contents check failed.")
        decode = run(["pg_restore", "--no-owner", "--no-acl", "--file", "/dev/null", str(archive)])
        if decode.returncode != 0:
            fail("The PostgreSQL archive data-integrity decode failed.")
        digest = sha256_file(archive)
        local_size = archive.stat().st_size

        upload = run(
            [
                "gcloud", "storage", "cp", str(archive), remote_uri,
                "--if-generation-match=0",
                f"--custom-metadata=sha256={digest},source_revision={source_revision},source_identity_sha256={source_identity_sha}",
                "--quiet",
            ]
        )
        if upload.returncode != 0:
            fail("The backup was not uploaded; no existing backup object was overwritten.")

        downloaded = work / "readback.dump"
        readback = run(["gcloud", "storage", "cp", remote_uri, str(downloaded), "--quiet"])
        if readback.returncode != 0 or not downloaded.is_file():
            fail("The independent backup object could not be read back for verification.")
        readback_digest = sha256_file(downloaded)
        if readback_digest != digest or downloaded.stat().st_size != local_size:
            fail("The downloaded independent backup does not match the source archive checksum/size.")
        remote_info = run(["gcloud", "storage", "objects", "describe", remote_uri, "--format=json"])
        if remote_info.returncode != 0:
            fail("The independent backup object metadata could not be verified.")
        try:
            metadata = json.loads(remote_info.stdout)
        except Exception:
            fail("The independent backup object metadata was invalid.")
        if str(metadata.get("metadata", {}).get("sha256", "")) != digest:
            fail("The independent backup's stored checksum metadata does not match.")
        if str(metadata.get("generation", "")) in {"", "0"}:
            fail("The independent backup object has no valid immutable generation.")

    print(f"BACKUP_URI={remote_uri}")
    print(f"BACKUP_SHA256={digest}")
    print(f"BACKUP_BYTES={local_size}")
    print(f"BACKUP_GENERATION={metadata['generation']}")
    print(f"SOURCE_REVISION={source_revision}")
    print(f"POSTGRES_SERVER_VERSION={server_version}")
    print("BACKUP_VERIFICATION=PASS (custom archive, TOC, verified cross-project CMEK bucket, readback SHA-256)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
