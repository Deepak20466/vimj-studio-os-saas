"""Restore coach salary records without dropping or replacing an existing table.

This is intentionally additive. If a legacy table survived outside the normal
migration path, its rows are left in place and the migration validates its
shape before advancing the revision.
"""
import os

from alembic import op
import sqlalchemy as sa


revision = "0020"
down_revision = "0019"
branch_labels = None
depends_on = None


_COLUMNS = {
    "id",
    "coach_id",
    "month",
    "year",
    "amount",
    "notified_at",
    "acknowledged_date",
    "created_at",
}


def upgrade():
    bind = op.get_bind()
    host = (bind.engine.url.host or "").lower()
    is_supabase = host.endswith((".supabase.com", ".supabase.co"))
    if is_supabase and os.environ.get("VIMJ_SCHEMA_CHANGE_APPROVED") != "YES":
        raise RuntimeError(
            "Schema migration on Supabase requires VIMJ_SCHEMA_CHANGE_APPROVED=YES after backup and salary reconciliation"
        )
    if "alembic_version" not in set(sa.inspect(bind).get_table_names(schema="public")):
        raise RuntimeError("Alembic revision table is missing; refusing to infer or stamp the schema")
    revisions = list(bind.execute(sa.text("SELECT version_num FROM public.alembic_version")).scalars())
    if revisions != ["0019"]:
        raise RuntimeError("Salary schema migration requires exact Alembic revision 0019")
    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names(schema="public"))
    if "coach_salary" in tables:
        existing_columns = {column["name"] for column in inspector.get_columns("coach_salary", schema="public")}
        if not _COLUMNS.issubset(existing_columns):
            raise RuntimeError(
                "coach_salary exists with an unexpected shape; preserve it and review manually before migration"
            )
        constraints = inspector.get_unique_constraints("coach_salary", schema="public")
        has_period_constraint = any(
            item.get("column_names") == ["coach_id", "month", "year"]
            for item in constraints
        )
        if not has_period_constraint:
            duplicates = bind.execute(
                sa.text(
                    "SELECT 1 FROM public.coach_salary "
                    "GROUP BY coach_id, month, year HAVING count(*) > 1 LIMIT 1"
                )
            ).first()
            if duplicates:
                raise RuntimeError(
                    "coach_salary contains duplicate coach/month/year rows; preserve data and reconcile manually"
                )
            op.create_unique_constraint(
                "uq_coach_salary_period", "coach_salary", ["coach_id", "month", "year"]
            )
        return

    op.create_table(
        "coach_salary",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "coach_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("month", sa.Integer(), nullable=False),
        sa.Column("year", sa.Integer(), nullable=False),
        sa.Column("amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("notified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("acknowledged_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("coach_id", "month", "year", name="uq_coach_salary_period"),
    )
    op.create_index("ix_coach_salary_coach_id", "coach_salary", ["coach_id"])


def downgrade():
    raise RuntimeError(
        "Refusing to drop coach_salary during downgrade because it may contain payroll history"
    )
