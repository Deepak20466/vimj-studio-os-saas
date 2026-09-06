"""batches, coach activity assignment, swap reason/batch link

Revision ID: 0003
Revises: 0002
Create Date: 2026-09-06

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

session_period_enum = sa.Enum("MORNING", "AFTERNOON", "EVENING", name="sessionperiod")


def upgrade() -> None:
    op.create_table(
        "batches",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("activity_id", sa.Integer, sa.ForeignKey("activities.id", ondelete="CASCADE"), nullable=False),
        sa.Column("coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("location", sa.String(255), nullable=False),
        sa.Column("session_period", session_period_enum, nullable=False),
        sa.Column("start_time", sa.Time, nullable=False),
        sa.Column("end_time", sa.Time, nullable=False),
        sa.Column("days_of_week", sa.String(40), nullable=False),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_batches_activity_id", "batches", ["activity_id"])
    op.create_index("ix_batches_coach_id", "batches", ["coach_id"])

    op.create_table(
        "coach_activities",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("activity_id", sa.Integer, sa.ForeignKey("activities.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("coach_id", "activity_id", name="uq_coach_activity"),
    )
    op.create_index("ix_coach_activities_coach_id", "coach_activities", ["coach_id"])
    op.create_index("ix_coach_activities_activity_id", "coach_activities", ["activity_id"])

    # batch_alter_table: plain ALTER TABLE on Postgres, copy-and-move on SQLite (which
    # can't ALTER in a new column with a foreign-key constraint directly).
    with op.batch_alter_table("classes") as batch_op:
        batch_op.add_column(
            sa.Column("batch_id", sa.Integer, sa.ForeignKey("batches.id", ondelete="SET NULL", name="fk_classes_batch_id"))
        )
    op.create_index("ix_classes_batch_id", "classes", ["batch_id"])

    with op.batch_alter_table("coach_swap") as batch_op:
        batch_op.add_column(
            sa.Column("batch_id", sa.Integer, sa.ForeignKey("batches.id", ondelete="SET NULL", name="fk_coach_swap_batch_id"))
        )
        batch_op.add_column(sa.Column("reason", sa.Text))
    op.create_index("ix_coach_swap_batch_id", "coach_swap", ["batch_id"])


def downgrade() -> None:
    op.drop_index("ix_coach_swap_batch_id", table_name="coach_swap")
    with op.batch_alter_table("coach_swap") as batch_op:
        batch_op.drop_column("reason")
        batch_op.drop_column("batch_id")

    op.drop_index("ix_classes_batch_id", table_name="classes")
    with op.batch_alter_table("classes") as batch_op:
        batch_op.drop_column("batch_id")

    op.drop_index("ix_coach_activities_activity_id", table_name="coach_activities")
    op.drop_index("ix_coach_activities_coach_id", table_name="coach_activities")
    op.drop_table("coach_activities")

    op.drop_index("ix_batches_coach_id", table_name="batches")
    op.drop_index("ix_batches_activity_id", table_name="batches")
    op.drop_table("batches")

    bind = op.get_bind()
    session_period_enum.drop(bind, checkfirst=True)
