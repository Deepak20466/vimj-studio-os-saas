"""Read-only Supabase connectivity and table-inventory preflight.

Run from ``backend`` with the production DATABASE_URL supplied through the
environment. The script starts a PostgreSQL read-only transaction and only
issues SELECT statements. It prints no connection URL, username, or hostname.
Row counts are PostgreSQL estimates, not exact counts or a backup comparison.
"""

from __future__ import annotations

import os
import sys

from sqlalchemy import inspect, text
from sqlalchemy.engine import make_url


BASE_EXPECTED_TABLES = {
    "academy_settings",
    "activities",
    "admin_attendance_list_visibility",
    "alembic_version",
    "audit_log",
    "batches",
    "classes",
    "coach_activities",
    "coach_attendance",
    "coach_leave",
    "fee_receipts",
    "fee_reminder_drafts",
    "notifications",
    "password_reset_tokens",
    "student_attendance",
    "student_enrollments",
    "student_fees",
    "user_details",
    "users",
}
SALARY_TABLE = "coach_salary"
SCHEDULER_TABLE = "scheduler_job_executions"
PRESERVED_LEGACY_TABLES = {
    "attendance_submissions",
    "chat_messages",
    "class_photos",
    "class_skip_reasons",
    "coach_swap",
}


def main() -> int:
    raw_url = os.environ.get("DATABASE_URL", "").strip()
    if not raw_url:
        print("FAIL: DATABASE_URL is not set; no connection was attempted.", file=sys.stderr)
        return 2

    engine = None
    try:
        # Import only after requiring the explicit URL; app.database configures
        # the repository's normal SQLAlchemy engine/pool behavior for Supabase.
        from app.database import create_database_engine, normalize_database_url

        normalized_url = normalize_database_url(raw_url)
        parsed_url = make_url(normalized_url)
        if parsed_url.get_backend_name() != "postgresql":
            print("FAIL: DATABASE_URL does not use PostgreSQL; no connection was attempted.", file=sys.stderr)
            return 2
        if not (parsed_url.host or "").lower().endswith(".pooler.supabase.com") or parsed_url.port != 6543:
            print("FAIL: DATABASE_URL must use the Supabase transaction pooler on port 6543.", file=sys.stderr)
            return 2
        for env_name, actual in (
            ("EXPECTED_SUPABASE_HOST", parsed_url.host),
            ("EXPECTED_SUPABASE_USER", parsed_url.username),
            ("EXPECTED_DATABASE_NAME", parsed_url.database),
        ):
            expected = os.environ.get(env_name)
            if expected and actual != expected:
                print(f"FAIL: {env_name} does not match the supplied DATABASE_URL; no query was run.", file=sys.stderr)
                return 2

        engine = create_database_engine(raw_url)
        with engine.connect() as connection:
            transaction = connection.begin()
            try:
                connection.exec_driver_sql("SET TRANSACTION READ ONLY")
                result = connection.execute(
                    text(
                        "SELECT current_setting('transaction_read_only') AS read_only, "
                        "current_setting('server_version') AS server_version"
                    )
                ).one()
                if result.read_only != "on":
                    raise RuntimeError("PostgreSQL did not confirm a read-only transaction")

                tables = set(inspect(connection).get_table_names(schema="public"))
                revisions = list(connection.execute(text(
                    "SELECT version_num FROM public.alembic_version"
                )).scalars()) if "alembic_version" in tables else []
                expected_tables = set(BASE_EXPECTED_TABLES)
                if revisions == ["0020"]:
                    expected_tables.add(SALARY_TABLE)
                elif revisions == ["0021"]:
                    expected_tables.update({SALARY_TABLE, SCHEDULER_TABLE})
                elif revisions == ["0019"] and SALARY_TABLE in tables:
                    # A legacy table may survive at the pre-restoration revision.
                    # Keep it visible for data reconciliation; never drop it here.
                    expected_tables.add(SALARY_TABLE)
                elif revisions != ["0019"]:
                    raise RuntimeError("database revision is not one of the reviewed 0019, 0020, or 0021 states")
                estimates = dict(
                    connection.execute(
                        text(
                            "SELECT relname, n_live_tup "
                            "FROM pg_stat_user_tables WHERE schemaname = 'public'"
                        )
                    ).all()
                )

                print("Connection: PASS (PostgreSQL, transaction is read-only)")
                print(f"PostgreSQL server version: {result.server_version}")
                print(f"Alembic revisions found: {revisions}")
                print(f"Public tables found: {len(tables)}")
                for table_name in sorted(tables):
                    estimate = estimates.get(table_name)
                    estimate_text = "unknown" if estimate is None else f"~{estimate:,} rows"
                    print(f"  {table_name}: {estimate_text}")

                missing = sorted(expected_tables - tables)
                preserved_legacy = sorted(tables & PRESERVED_LEGACY_TABLES)
                extra = sorted(tables - expected_tables - PRESERVED_LEGACY_TABLES)
                print(f"Expected tables missing: {missing or 'none'}")
                print(f"Unexpected public tables: {extra or 'none'}")
                print(f"Preserved historical tables present: {preserved_legacy or 'none'}")
                transaction.rollback()

                if missing or extra:
                    print("Inventory: FAIL (reconcile against the verified backup before deployment)")
                    return 1
                print(f"Inventory: PASS ({len(expected_tables)} required tables found; preserved historical tables retained; row estimates are not integrity proof)")
                return 0
            finally:
                if transaction.is_active:
                    transaction.rollback()
    except Exception as exc:
        # Avoid including the SQLAlchemy exception's URL-bearing connection
        # details, which can include the database username/host.
        print(f"FAIL: read-only database preflight failed ({type(exc).__name__}).", file=sys.stderr)
        return 2
    finally:
        if engine is not None:
            engine.dispose()


if __name__ == "__main__":
    raise SystemExit(main())
