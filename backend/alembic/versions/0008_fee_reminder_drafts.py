"""coach-drafted fee reminders (admin-approved before sending to student)

Revision ID: 0008
Revises: 0007
Create Date: 2026-09-06

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0008"
down_revision: Union[str, None] = "0007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

reminder_draft_status_enum = sa.Enum("PENDING", "APPROVED", "REJECTED", name="reminderdraftstatus")


def upgrade() -> None:
    op.create_table(
        "fee_reminder_drafts",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("student_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("month", sa.Integer, nullable=False),
        sa.Column("year", sa.Integer, nullable=False),
        sa.Column("message", sa.Text, nullable=False),
        sa.Column("status", reminder_draft_status_enum, nullable=False, server_default="PENDING"),
        sa.Column("decision_note", sa.Text),
        sa.Column("approved_by_admin_id", sa.Integer, sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("sent_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("decided_at", sa.DateTime(timezone=True)),
    )
    op.create_index("ix_fee_reminder_drafts_student_id", "fee_reminder_drafts", ["student_id"])
    op.create_index("ix_fee_reminder_drafts_coach_id", "fee_reminder_drafts", ["coach_id"])
    op.create_index("ix_fee_reminder_drafts_status", "fee_reminder_drafts", ["status"])


def downgrade() -> None:
    op.drop_index("ix_fee_reminder_drafts_status", table_name="fee_reminder_drafts")
    op.drop_index("ix_fee_reminder_drafts_coach_id", table_name="fee_reminder_drafts")
    op.drop_index("ix_fee_reminder_drafts_student_id", table_name="fee_reminder_drafts")
    op.drop_table("fee_reminder_drafts")

    bind = op.get_bind()
    reminder_draft_status_enum.drop(bind, checkfirst=True)
