import contextlib
import importlib.util
import io
import json
import unittest
from pathlib import Path


SCRIPT_PATH = (
    Path(__file__).resolve().parents[2]
    / "deploy"
    / "cloud-run"
    / "backup-supabase-cloud-shell.py"
)
SPEC = importlib.util.spec_from_file_location("backup_supabase_cloud_shell", SCRIPT_PATH)
backup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backup)


class BackupBucketValidationTests(unittest.TestCase):
    source_project_number = "123456789012"
    backup_project_id = "teak-backup-491013-m3"
    backup_project_number = "987654321098"
    bucket_name = "vimj-academy-recovery-backup-2026"
    kms_key = (
        "projects/teak-backup-491013-m3/locations/asia-south1/"
        "keyRings/vimj-backups/cryptoKeys/recovery"
    )

    def raw_bucket(self, **changes):
        value = {
            "kind": "storage#bucket",
            "name": self.bucket_name,
            "projectNumber": self.backup_project_number,
            "encryption": {"defaultKmsKeyName": self.kms_key},
        }
        value.update(changes)
        return json.dumps(value).encode()

    def verify(self, raw):
        return backup.verify_bucket_metadata(
            raw,
            expected_bucket=self.bucket_name,
            source_project_number=self.source_project_number,
            backup_project_id=self.backup_project_id,
            backup_project_number=self.backup_project_number,
        )

    def assert_rejected(self, raw):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            self.verify(raw)

    def test_raw_gcloud_bucket_schema_accepts_owner_number_and_nested_default_key(self):
        self.assertEqual(self.verify(self.raw_bucket()), self.kms_key)

    def test_bucket_describe_requests_raw_api_metadata(self):
        self.assertEqual(
            backup.bucket_metadata_command(self.bucket_name),
            [
                "gcloud", "storage", "buckets", "describe",
                f"gs://{self.bucket_name}", "--raw", "--format=json",
            ],
        )

    def test_missing_project_number_fails_closed(self):
        missing_number = json.loads(self.raw_bucket())
        missing_number.pop("projectNumber")
        self.assert_rejected(json.dumps(missing_number).encode())

    def test_bucket_owned_by_application_project_is_rejected(self):
        self.assert_rejected(
            self.raw_bucket(projectNumber=self.source_project_number)
        )

    def test_bucket_owned_by_unexpected_project_is_rejected(self):
        self.assert_rejected(self.raw_bucket(projectNumber="555555555555"))

    def test_wrong_bucket_identity_is_rejected(self):
        self.assert_rejected(self.raw_bucket(name="another-bucket"))

    def test_root_level_kms_key_does_not_substitute_for_api_encryption_schema(self):
        self.assert_rejected(
            json.dumps(
                {
                    "name": self.bucket_name,
                    "projectNumber": self.backup_project_number,
                    "defaultKmsKeyName": self.kms_key,
                }
            ).encode()
        )

    def test_missing_or_malformed_default_cmek_fails_closed(self):
        self.assert_rejected(self.raw_bucket(encryption={}))
        self.assert_rejected(
            self.raw_bucket(encryption={"defaultKmsKeyName": "not-a-kms-resource"})
        )

    def test_project_metadata_must_match_project_id_and_active_project_number(self):
        good = json.dumps(
            {
                "projectId": self.backup_project_id,
                "projectNumber": self.backup_project_number,
                "lifecycleState": "ACTIVE",
            }
        ).encode()
        self.assertEqual(
            backup.parse_project_number(good, self.backup_project_id, "backup"),
            self.backup_project_number,
        )
        bad = json.dumps(
            {
                "projectId": self.backup_project_id,
                "lifecycleState": "ACTIVE",
            }
        ).encode()
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            backup.parse_project_number(bad, self.backup_project_id, "backup")


if __name__ == "__main__":
    unittest.main()
