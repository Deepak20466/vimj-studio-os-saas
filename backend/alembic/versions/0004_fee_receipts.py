"""fee receipts (coach-submitted, admin-approved)

Revision ID: 0004
Revises: 0003
Create Date: 2026-09-06

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0004"
down_revision: Union[str, None] = "0003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

receipt_status_enum = sa.Enum("PENDING", "APPROVED", "REJECTED", name="receiptstatus")


def upgrade() -> None:
    op.create_table(
        "fee_receipts",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("student_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("month", sa.Integer, nullable=False),
        sa.Column("year", sa.Integer, nullable=False),
        sa.Column("payment_mode", sa.String(20), nullable=False, server_default="CASH"),
        sa.Column("note", sa.Text),
        sa.Column("status", receipt_status_enum, nullable=False, server_default="PENDING"),
        sa.Column("decision_note", sa.Text),
        sa.Column("approved_by_admin_id", sa.Integer, sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("decided_at", sa.DateTime(timezone=True)),
    )
    op.create_index("ix_fee_receipts_student_id", "fee_receipts", ["student_id"])
    op.create_index("ix_fee_receipts_coach_id", "fee_receipts", ["coach_id"])
    op.create_index("ix_fee_receipts_status", "fee_receipts", ["status"])


def downgrade() -> None:
    op.drop_index("ix_fee_receipts_status", table_name="fee_receipts")
    op.drop_index("ix_fee_receipts_coach_id", table_name="fee_receipts")
    op.drop_index("ix_fee_receipts_student_id", table_name="fee_receipts")
    op.drop_table("fee_receipts")

    bind = op.get_bind()
    receipt_status_enum.drop(bind, checkfirst=True)
