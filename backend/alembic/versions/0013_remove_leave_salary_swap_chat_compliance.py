"""Remove Leave, Salary, Swap, Chat, and Compliance features (admin dashboard rebuild)

Client-directed simplification: the admin dashboard is being rebuilt around 7 core
sections only (Students, Coaches, Attendance, Activities/Batches, Fees, Settings,
Notifications). Leave, Salary, Coach Swapping, Chat, and Compliance (late-attendance
approval / class-not-conducted / class photos) are dropped system-wide to reduce
surface area — this also affects the coach app, which is being rebuilt separately.

Revision ID: 0013
Revises: 0012
Create Date: 2026-09-12

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0013"
down_revision: Union[str, None] = "0012"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

leave_status_enum = sa.Enum("PENDING", "APPROVED", "REJECTED", name="leavestatus")
swap_status_enum = sa.Enum("PENDING", "APPROVED", "REJECTED", name="swapstatus")
swap_initiator_enum = sa.Enum("ADMIN", "COACH", name="swapinitiator")
late_status_enum = sa.Enum("NONE", "PENDING", "APPROVED", "REJECTED", name="latestatus")


def upgrade() -> None:
    op.drop_table("class_photos")
    op.drop_table("attendance_submissions")
    op.drop_table("class_skip_reasons")
    op.drop_table("chat_messages")
    op.drop_table("coach_swap")
    op.drop_table("coach_salary")
    op.drop_table("coach_leave")

    bind = op.get_bind()
    late_status_enum.drop(bind, checkfirst=True)
    swap_initiator_enum.drop(bind, checkfirst=True)
    swap_status_enum.drop(bind, checkfirst=True)
    leave_status_enum.drop(bind, checkfirst=True)


def downgrade() -> None:
    bind = op.get_bind()
    leave_status_enum.create(bind, checkfirst=True)
    swap_status_enum.create(bind, checkfirst=True)
    swap_initiator_enum.create(bind, checkfirst=True)
    late_status_enum.create(bind, checkfirst=True)

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

    op.create_table(
        "coach_salary",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("month", sa.Integer, nullable=False),
        sa.Column("year", sa.Integer, nullable=False),
        sa.Column("amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("notified_at", sa.DateTime(timezone=True)),
        sa.Column("acknowledged_date", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("coach_id", "month", "year", name="uq_coach_salary_period"),
    )
    op.create_index("ix_coach_salary_coach_id", "coach_salary", ["coach_id"])

    op.create_table(
        "coach_swap",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("original_coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("covering_coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("class_id", sa.Integer, sa.ForeignKey("classes.id", ondelete="CASCADE"), nullable=False),
        sa.Column("batch_id", sa.Integer, sa.ForeignKey("batches.id", ondelete="SET NULL")),
        sa.Column("date", sa.Date, nullable=False),
        sa.Column("reason", sa.Text),
        sa.Column("status", swap_status_enum, nullable=False, server_default="PENDING"),
        sa.Column("initiated_by", swap_initiator_enum, nullable=False, server_default="ADMIN"),
        sa.Column("decline_reason", sa.Text),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_coach_swap_original_coach_id", "coach_swap", ["original_coach_id"])
    op.create_index("ix_coach_swap_covering_coach_id", "coach_swap", ["covering_coach_id"])
    op.create_index("ix_coach_swap_class_id", "coach_swap", ["class_id"])
    op.create_index("ix_coach_swap_batch_id", "coach_swap", ["batch_id"])
    op.create_index("ix_coach_swap_status", "coach_swap", ["status"])

    op.create_table(
        "chat_messages",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("sender_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("sender_role", sa.String(20), nullable=False),
        sa.Column("message", sa.Text, nullable=False),
        sa.Column("is_read", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_chat_messages_coach_id", "chat_messages", ["coach_id"])
    op.create_index("ix_chat_messages_is_read", "chat_messages", ["is_read"])
    op.create_index("ix_chat_messages_created_at", "chat_messages", ["created_at"])

    op.create_table(
        "class_skip_reasons",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("class_id", sa.Integer, sa.ForeignKey("classes.id", ondelete="CASCADE"), nullable=False, unique=True),
        sa.Column("coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("reason", sa.Text, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_class_skip_reasons_class_id", "class_skip_reasons", ["class_id"])
    op.create_index("ix_class_skip_reasons_coach_id", "class_skip_reasons", ["coach_id"])

    op.create_table(
        "attendance_submissions",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("class_id", sa.Integer, sa.ForeignKey("classes.id", ondelete="CASCADE"), nullable=False, unique=True),
        sa.Column("coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("submitted_at", sa.DateTime(timezone=True)),
        sa.Column("is_late", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("late_reason", sa.Text),
        sa.Column("late_status", late_status_enum, nullable=False, server_default="NONE"),
        sa.Column("decided_by_admin_id", sa.Integer, sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("decided_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_attendance_submissions_class_id", "attendance_submissions", ["class_id"])
    op.create_index("ix_attendance_submissions_coach_id", "attendance_submissions", ["coach_id"])
    op.create_index("ix_attendance_submissions_late_status", "attendance_submissions", ["late_status"])

    op.create_table(
        "class_photos",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("class_id", sa.Integer, sa.ForeignKey("classes.id", ondelete="CASCADE"), nullable=False),
        sa.Column("coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("photo_path", sa.LargeBinary()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_class_photos_class_id", "class_photos", ["class_id"])
    op.create_index("ix_class_photos_coach_id", "class_photos", ["coach_id"])
