"""initial schema

Revision ID: 0001
Revises:
Create Date: 2026-09-02

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

user_role_enum = sa.Enum("ADMIN", "COACH", "STUDENT", name="userrole")
attendance_status_enum = sa.Enum("PRESENT", "ABSENT", "LEAVE", name="attendancestatus")
coach_attendance_status_enum = sa.Enum("PRESENT", "ABSENT", "LEAVE", "INCOMPLETE", name="coachattendancestatus")
leave_status_enum = sa.Enum("PENDING", "APPROVED", "REJECTED", name="leavestatus")
swap_status_enum = sa.Enum("PENDING", "APPROVED", "REJECTED", name="swapstatus")
fee_status_enum = sa.Enum("PAID", "UNPAID", "OVERDUE", name="feestatus")


def upgrade() -> None:
    bind = op.get_bind()
    user_role_enum.create(bind, checkfirst=True)
    attendance_status_enum.create(bind, checkfirst=True)
    coach_attendance_status_enum.create(bind, checkfirst=True)
    leave_status_enum.create(bind, checkfirst=True)
    swap_status_enum.create(bind, checkfirst=True)
    fee_status_enum.create(bind, checkfirst=True)

    op.create_table(
        "users",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("email", sa.String(255), nullable=False, unique=True),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("phone", sa.String(32)),
        sa.Column("role", user_role_enum, nullable=False),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_users_email", "users", ["email"])
    op.create_index("ix_users_role", "users", ["role"])

    op.create_table(
        "user_details",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True),
        sa.Column("address", sa.String(500)),
        sa.Column("dob", sa.Date),
        sa.Column("profile_photo", sa.String(500)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "password_reset_tokens",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("token", sa.String(255), nullable=False, unique=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_password_reset_tokens_user_id", "password_reset_tokens", ["user_id"])
    op.create_index("ix_password_reset_tokens_token", "password_reset_tokens", ["token"])

    op.create_table(
        "activities",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("capacity", sa.Integer, nullable=False, server_default="0"),
        sa.Column("location_lat", sa.Numeric(9, 6)),
        sa.Column("location_lng", sa.Numeric(9, 6)),
        sa.Column("monthly_fee", sa.Numeric(10, 2), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_table(
        "classes",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("activity_id", sa.Integer, sa.ForeignKey("activities.id", ondelete="CASCADE"), nullable=False),
        sa.Column("coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("date", sa.Date, nullable=False),
        sa.Column("start_time", sa.Time, nullable=False),
        sa.Column("end_time", sa.Time, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_classes_activity_id", "classes", ["activity_id"])
    op.create_index("ix_classes_coach_id", "classes", ["coach_id"])
    op.create_index("ix_classes_date", "classes", ["date"])

    op.create_table(
        "student_enrollments",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("student_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("activity_id", sa.Integer, sa.ForeignKey("activities.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("student_id", "activity_id", name="uq_student_activity"),
    )
    op.create_index("ix_student_enrollments_student_id", "student_enrollments", ["student_id"])
    op.create_index("ix_student_enrollments_activity_id", "student_enrollments", ["activity_id"])

    op.create_table(
        "student_attendance",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("student_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("class_id", sa.Integer, sa.ForeignKey("classes.id", ondelete="CASCADE"), nullable=False),
        sa.Column("status", attendance_status_enum, nullable=False),
        sa.Column("coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("timestamp", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("location_lat", sa.Numeric(9, 6)),
        sa.Column("location_lng", sa.Numeric(9, 6)),
        sa.Column("selfie_photo", sa.String(500)),
        sa.Column("marked_manually", sa.Numeric, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_student_attendance_student_id", "student_attendance", ["student_id"])
    op.create_index("ix_student_attendance_class_id", "student_attendance", ["class_id"])
    op.create_index("ix_student_attendance_coach_id", "student_attendance", ["coach_id"])

    op.create_table(
        "coach_attendance",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("date", sa.Date, nullable=False),
        sa.Column("entry_time", sa.DateTime(timezone=True)),
        sa.Column("exit_time", sa.DateTime(timezone=True)),
        sa.Column("entry_lat", sa.Numeric(9, 6)),
        sa.Column("entry_lng", sa.Numeric(9, 6)),
        sa.Column("exit_lat", sa.Numeric(9, 6)),
        sa.Column("exit_lng", sa.Numeric(9, 6)),
        sa.Column("activity_id", sa.Integer, sa.ForeignKey("activities.id", ondelete="SET NULL")),
        sa.Column("status", coach_attendance_status_enum, nullable=False, server_default="INCOMPLETE"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_coach_attendance_coach_id", "coach_attendance", ["coach_id"])
    op.create_index("ix_coach_attendance_date", "coach_attendance", ["date"])

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
        "coach_swap",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("original_coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("covering_coach_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("class_id", sa.Integer, sa.ForeignKey("classes.id", ondelete="CASCADE"), nullable=False),
        sa.Column("date", sa.Date, nullable=False),
        sa.Column("status", swap_status_enum, nullable=False, server_default="PENDING"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_coach_swap_original_coach_id", "coach_swap", ["original_coach_id"])
    op.create_index("ix_coach_swap_covering_coach_id", "coach_swap", ["covering_coach_id"])
    op.create_index("ix_coach_swap_class_id", "coach_swap", ["class_id"])
    op.create_index("ix_coach_swap_status", "coach_swap", ["status"])

    op.create_table(
        "student_fees",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("student_id", sa.Integer, sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("month", sa.Integer, nullable=False),
        sa.Column("year", sa.Integer, nullable=False),
        sa.Column("amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("status", fee_status_enum, nullable=False, server_default="UNPAID"),
        sa.Column("due_date", sa.Date, nullable=False),
        sa.Column("paid_date", sa.Date),
        sa.Column("reminder_sent_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("student_id", "month", "year", name="uq_student_fee_period"),
    )
    op.create_index("ix_student_fees_student_id", "student_fees", ["student_id"])
    op.create_index("ix_student_fees_status", "student_fees", ["status"])

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
        "audit_log",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("action", sa.String(100), nullable=False),
        sa.Column("entity_type", sa.String(100), nullable=False),
        sa.Column("entity_id", sa.Integer),
        sa.Column("details", sa.Text),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_audit_log_user_id", "audit_log", ["user_id"])
    op.create_index("ix_audit_log_action", "audit_log", ["action"])
    op.create_index("ix_audit_log_created_at", "audit_log", ["created_at"])


def downgrade() -> None:
    op.drop_table("audit_log")
    op.drop_table("coach_salary")
    op.drop_table("student_fees")
    op.drop_table("coach_swap")
    op.drop_table("coach_leave")
    op.drop_table("coach_attendance")
    op.drop_table("student_attendance")
    op.drop_table("student_enrollments")
    op.drop_table("classes")
    op.drop_table("activities")
    op.drop_table("password_reset_tokens")
    op.drop_table("user_details")
    op.drop_table("users")

    bind = op.get_bind()
    fee_status_enum.drop(bind, checkfirst=True)
    swap_status_enum.drop(bind, checkfirst=True)
    leave_status_enum.drop(bind, checkfirst=True)
    coach_attendance_status_enum.drop(bind, checkfirst=True)
    attendance_status_enum.drop(bind, checkfirst=True)
    user_role_enum.drop(bind, checkfirst=True)
