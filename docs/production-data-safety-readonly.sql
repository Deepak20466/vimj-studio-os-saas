-- VIMJ production data safety audit. This file contains read-only inspection
-- statements only. Run with psql inside a caller-started READ ONLY transaction.
-- It prints table counts and SHA-256 row-set fingerprints to NOTICE output.
-- Exact scans can be I/O intensive; use an off-peak window or the isolated copy.

\set ON_ERROR_STOP on

DO $audit$
BEGIN
    IF current_setting('transaction_read_only') <> 'on' THEN
        RAISE EXCEPTION 'Start a READ ONLY transaction before running this audit';
    END IF;
END
$audit$;

SELECT current_setting('transaction_read_only') AS transaction_read_only,
       current_setting('server_version') AS postgres_version;

-- Compare the source application's expected public tables with all actual
-- public base tables. Unexpected tables (including legacy tables) need review.
WITH expected(table_name) AS (
    VALUES
        ('academy_settings'),
        ('activities'),
        ('admin_attendance_list_visibility'),
        ('alembic_version'),
        ('audit_log'),
        ('batches'),
        ('classes'),
        ('coach_activities'),
        ('coach_attendance'),
        ('coach_leave'),
        ('coach_salary'),
        ('fee_receipts'),
        ('fee_reminder_drafts'),
        ('notifications'),
        ('password_reset_tokens'),
        ('student_attendance'),
        ('student_enrollments'),
        ('student_fees'),
        ('user_details'),
        ('users')
), actual(table_name) AS (
    SELECT table_name
    FROM pg_catalog.pg_tables
    WHERE schemaname = 'public'
)
SELECT COALESCE(expected.table_name, actual.table_name) AS table_name,
       CASE
           WHEN expected.table_name IS NULL THEN 'UNEXPECTED_PUBLIC_TABLE'
           WHEN actual.table_name IS NULL THEN 'MISSING_EXPECTED_TABLE'
           ELSE 'PRESENT'
       END AS inventory_status
FROM expected
FULL OUTER JOIN actual USING (table_name)
ORDER BY table_name;

-- Seven tables explicitly dropped by migration 0013. This also reveals if any
-- are still present in a database whose revision is earlier or was hand-edited.
SELECT legacy.table_name,
       CASE WHEN actual.table_name IS NULL THEN 'ABSENT' ELSE 'PRESENT' END AS table_status
FROM (VALUES
    ('class_photos'),
    ('attendance_submissions'),
    ('class_skip_reasons'),
    ('chat_messages'),
    ('coach_swap'),
    ('coach_salary'),
    ('coach_leave')
) AS legacy(table_name)
LEFT JOIN pg_catalog.pg_tables AS actual
  ON actual.schemaname = 'public'
 AND actual.tablename = legacy.table_name
ORDER BY legacy.table_name;

-- Current Alembic revision. More than one row means a multi-head state that
-- must be reviewed rather than assumed to be revision 0019.
DO $audit$
DECLARE
    revision_row record;
BEGIN
    IF to_regclass('public.alembic_version') IS NULL THEN
        RAISE NOTICE 'ALEMBIC_REVISION|MISSING alembic_version table';
    ELSE
        FOR revision_row IN EXECUTE
            'SELECT version_num FROM public.alembic_version ORDER BY version_num'
        LOOP
            RAISE NOTICE 'ALEMBIC_REVISION|%', revision_row.version_num;
        END LOOP;
    END IF;
END
$audit$;

-- Exact counts and deterministic fingerprints for every public base table,
-- including unexpected/legacy tables. Fingerprints hash every column value,
-- including bytea photos, and are suitable for comparison between the same
-- source snapshot and its isolated restored copy. They are not password hashes.
DO $audit$
DECLARE
    table_row record;
    exact_rows bigint;
    rowset_sha256 text;
BEGIN
    FOR table_row IN
        SELECT schemaname, tablename
        FROM pg_catalog.pg_tables
        WHERE schemaname = 'public'
        ORDER BY tablename
    LOOP
        EXECUTE format(
            'SELECT count(*)::bigint,
                    encode(sha256(convert_to(coalesce(
                        string_agg(row_hash, '''' ORDER BY row_hash), ''''
                    ), ''UTF8'')), ''hex'')
             FROM (
                 SELECT encode(sha256(convert_to(to_jsonb(row_data)::text, ''UTF8'')), ''hex'') AS row_hash
                 FROM %I.%I AS row_data
             ) AS hashed_rows',
            table_row.schemaname,
            table_row.tablename
        ) INTO exact_rows, rowset_sha256;

        RAISE NOTICE 'AUDIT_TABLE|%.%|rows=%|sha256=%',
            table_row.schemaname,
            table_row.tablename,
            exact_rows,
            rowset_sha256;
    END LOOP;
END
$audit$;

-- Foreign-key definitions and validation status.
SELECT child_ns.nspname AS child_schema,
       child.relname AS child_table,
       constraint_row.conname AS constraint_name,
       parent_ns.nspname AS parent_schema,
       parent.relname AS parent_table,
       constraint_row.convalidated AS validated,
       pg_get_constraintdef(constraint_row.oid, true) AS definition
FROM pg_catalog.pg_constraint AS constraint_row
JOIN pg_catalog.pg_class AS child ON child.oid = constraint_row.conrelid
JOIN pg_catalog.pg_namespace AS child_ns ON child_ns.oid = child.relnamespace
JOIN pg_catalog.pg_class AS parent ON parent.oid = constraint_row.confrelid
JOIN pg_catalog.pg_namespace AS parent_ns ON parent_ns.oid = parent.relnamespace
WHERE constraint_row.contype = 'f'
  AND child_ns.nspname = 'public'
ORDER BY child.relname, constraint_row.conname;

-- Exact orphan counts for every public foreign key. Composite keys are checked
-- as a group; rows with a null key component are skipped under PostgreSQL's
-- default MATCH SIMPLE semantics and should be judged against column nullability.
DO $audit$
DECLARE
    foreign_key record;
    join_predicate text;
    nonnull_predicate text;
    orphan_rows bigint;
BEGIN
    FOR foreign_key IN
        SELECT constraint_row.oid,
               constraint_row.conname,
               constraint_row.conkey,
               constraint_row.confkey,
               constraint_row.convalidated,
               child_ns.nspname AS child_schema,
               child.relname AS child_table,
               constraint_row.conrelid AS child_oid,
               parent_ns.nspname AS parent_schema,
               parent.relname AS parent_table,
               constraint_row.confrelid AS parent_oid
        FROM pg_catalog.pg_constraint AS constraint_row
        JOIN pg_catalog.pg_class AS child ON child.oid = constraint_row.conrelid
        JOIN pg_catalog.pg_namespace AS child_ns ON child_ns.oid = child.relnamespace
        JOIN pg_catalog.pg_class AS parent ON parent.oid = constraint_row.confrelid
        JOIN pg_catalog.pg_namespace AS parent_ns ON parent_ns.oid = parent.relnamespace
        WHERE constraint_row.contype = 'f'
          AND child_ns.nspname = 'public'
        ORDER BY child.relname, constraint_row.conname
    LOOP
        SELECT string_agg(
                   format('p.%I = c.%I', parent_column.attname, child_column.attname),
                   ' AND ' ORDER BY key_columns.ordinality
               ),
               string_agg(
                   format('c.%I IS NOT NULL', child_column.attname),
                   ' AND ' ORDER BY key_columns.ordinality
               )
        INTO join_predicate, nonnull_predicate
        FROM unnest(foreign_key.conkey, foreign_key.confkey)
             WITH ORDINALITY AS key_columns(child_attnum, parent_attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS child_column
          ON child_column.attrelid = foreign_key.child_oid
         AND child_column.attnum = key_columns.child_attnum
        JOIN pg_catalog.pg_attribute AS parent_column
          ON parent_column.attrelid = foreign_key.parent_oid
         AND parent_column.attnum = key_columns.parent_attnum;

        EXECUTE format(
            'SELECT count(*)::bigint FROM %I.%I AS c
             WHERE %s AND NOT EXISTS (
                 SELECT 1 FROM %I.%I AS p WHERE %s
             )',
            foreign_key.child_schema,
            foreign_key.child_table,
            nonnull_predicate,
            foreign_key.parent_schema,
            foreign_key.parent_table,
            join_predicate
        ) INTO orphan_rows;

        RAISE NOTICE 'AUDIT_FK|%|%.%->%.%|validated=%|orphans=%',
            foreign_key.conname,
            foreign_key.child_schema,
            foreign_key.child_table,
            foreign_key.parent_schema,
            foreign_key.parent_table,
            foreign_key.convalidated,
            orphan_rows;
    END LOOP;
END
$audit$;

-- Columns, types, nullability, and defaults for schema/model comparison.
SELECT table_name,
       ordinal_position,
       column_name,
       data_type,
       udt_name,
       is_nullable,
       column_default
FROM information_schema.columns
WHERE table_schema = 'public'
ORDER BY table_name, ordinal_position;

-- Unique, primary-key, and check constraints; compare against source metadata.
SELECT child.relname AS table_name,
       constraint_row.conname AS constraint_name,
       constraint_row.contype AS constraint_type,
       constraint_row.convalidated AS validated,
       pg_get_constraintdef(constraint_row.oid, true) AS definition
FROM pg_catalog.pg_constraint AS constraint_row
JOIN pg_catalog.pg_class AS child ON child.oid = constraint_row.conrelid
JOIN pg_catalog.pg_namespace AS child_ns ON child_ns.oid = child.relnamespace
WHERE child_ns.nspname = 'public'
  AND constraint_row.contype IN ('p', 'u', 'c', 'x')
ORDER BY child.relname, constraint_row.contype, constraint_row.conname;

-- Index definitions, including indexes not represented by ORM constraints.
SELECT tablename, indexname, indexdef
FROM pg_catalog.pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- Caller must now issue ROLLBACK; to close the read-only audit transaction.
