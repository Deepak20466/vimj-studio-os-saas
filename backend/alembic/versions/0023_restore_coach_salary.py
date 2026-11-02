"""Restore Coach Salary while preserving any retained production records.

Revision 0013 removed the salary table in some installations. Production has
also had deployments that retained the legacy table and its rows. Create the
table only when absent so either state is safe and existing salary history is
never replaced.
"""
from alembic import op
import sqlalchemy as sa


revision = "0023"
down_revision = "0022"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    if sa.inspect(bind).has_table("coach_salary"):
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
    op.create_index("ix_coach_salary_id", "coach_salary", ["id"])
    op.create_index("ix_coach_salary_coach_id", "coach_salary", ["coach_id"])


def downgrade():
    # Salary rows are financial history; rolling back application code must
    # never erase them.
    raise RuntimeError("Refusing to drop coach_salary or its financial history")
