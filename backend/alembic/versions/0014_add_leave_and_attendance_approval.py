"""Re-add Coach Leave and add an admin-approval workflow to student attendance

Client-directed coach dashboard rebuild (2026-09-12, second round): the coach app is
being rebuilt around 6 sections (Students, Attendance, Leave, Fees, Settings,
Notifications). Leave management returns (it was deleted system-wide in migration
0013 during the admin dashboard rebuild) with the same shape it had before. Student
attendance also gains an approval workflow: once admin approves or rejects a record
a coach marked, the coach can no longer edit/delete it — only admin's own tools can.
Existing rows are backfilled as APPROVED so no historical backlog needs re-review.

Revision ID: 0014
Revises: 0013
Create Date: 2026-09-12

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0014"
down_revision: Union[str, None] = "0013"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

leave_status_enum = sa.Enum("PENDING", "APPROVED", "REJECTED", name="leavestatus")
attendance_approval_status_enum = sa.Enum("PENDING", "APPROVED", "REJECTED", name="attendanceapprovalstatus")


def upgrade() -> None:
    # create_table auto-creates an inline Enum column's type, but add_column does NOT —
    # it must be created explicitly first, then referenced with create_type=False below so
    # add_column doesn't also try (and fail with DuplicateObject) to create it again.
    bind = op.get_bind()
    attendance_approval_status_enum.create(bind, checkfirst=True)

    op.create_table(
        "coach_leave",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("start_date", sa.Date, nullable=False),
        sa.Column("end_date", sa.Date, nullable=False),
        sa.Column("reason", sa.String(1000), nullable=False),
        sa.Column("status", leave_status_enum, nullable=False, server_default="PENDING"),
        sa.Column("approved_by_admin_id", sa.Integer, sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("decision_note", sa.String(1000)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_coach_leave_coach_id", "coach_leave", ["coach_id"])
    op.create_index("ix_coach_leave_status", "coach_leave", ["status"])

    op.add_column(
        "student_attendance",
        sa.Column(
            "approval_status",
            sa.Enum("PENDING", "APPROVED", "REJECTED", name="attendanceapprovalstatus", create_type=False),
            nullable=False,
            server_default="APPROVED",
        ),
    )


def downgrade() -> None:
    op.drop_column("student_attendance", "approval_status")

    op.drop_index("ix_coach_leave_status", table_name="coach_leave")
    op.drop_index("ix_coach_leave_coach_id", table_name="coach_leave")
    op.drop_table("coach_leave")

    bind = op.get_bind()
    attendance_approval_status_enum.drop(bind, checkfirst=True)
    leave_status_enum.drop(bind, checkfirst=True)
