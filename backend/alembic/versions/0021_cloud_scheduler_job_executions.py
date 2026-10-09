"""Add a small durable execution ledger for Cloud Scheduler retries."""
import os

from alembic import op
import sqlalchemy as sa


revision = "0021"
down_revision = "0020"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    host = (bind.engine.url.host or "").lower()
    is_supabase = host.endswith((".supabase.com", ".supabase.co"))
    if is_supabase and os.environ.get("VIMJ_SCHEMA_CHANGE_APPROVED") != "YES":
        raise RuntimeError(
            "Schema migration on Supabase requires VIMJ_SCHEMA_CHANGE_APPROVED=YES after verified backup"
        )
    if "alembic_version" not in set(sa.inspect(bind).get_table_names(schema="public")):
        raise RuntimeError("Alembic revision table is missing; refusing to infer or stamp the schema")
    revisions = list(bind.execute(sa.text("SELECT version_num FROM public.alembic_version")).scalars())
    if revisions != ["0020"]:
        raise RuntimeError("Cloud Scheduler ledger migration requires exact Alembic revision 0020")

    op.create_table(
        "scheduler_job_executions",
        sa.Column("job_name", sa.String(length=100), primary_key=True),
        sa.Column("scheduled_for", sa.DateTime(timezone=True), primary_key=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("error_type", sa.String(length=100), nullable=True),
    )
    op.create_index(
        "ix_scheduler_job_executions_scheduled_for",
        "scheduler_job_executions",
        ["scheduled_for"],
    )


def downgrade():
    raise RuntimeError(
        "Refusing to drop scheduler_job_executions during downgrade; preserve production execution state"
    )
