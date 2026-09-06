"""class-not-conducted reasons, attendance submissions/late approval, class photos

Revision ID: 0005
Revises: 0004
Create Date: 2026-09-06

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0005"
down_revision: Union[str, None] = "0004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

late_status_enum = sa.Enum("NONE", "PENDING", "APPROVED", "REJECTED", name="latestatus")


def upgrade() -> None:
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
        sa.Column("photo_path", sa.String(500), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_class_photos_class_id", "class_photos", ["class_id"])
    op.create_index("ix_class_photos_coach_id", "class_photos", ["coach_id"])


def downgrade() -> None:
    op.drop_index("ix_class_photos_coach_id", table_name="class_photos")
    op.drop_index("ix_class_photos_class_id", table_name="class_photos")
    op.drop_table("class_photos")

    op.drop_index("ix_attendance_submissions_late_status", table_name="attendance_submissions")
    op.drop_index("ix_attendance_submissions_coach_id", table_name="attendance_submissions")
    op.drop_index("ix_attendance_submissions_class_id", table_name="attendance_submissions")
    op.drop_table("attendance_submissions")

    op.drop_index("ix_class_skip_reasons_coach_id", table_name="class_skip_reasons")
    op.drop_index("ix_class_skip_reasons_class_id", table_name="class_skip_reasons")
    op.drop_table("class_skip_reasons")

    bind = op.get_bind()
    late_status_enum.drop(bind, checkfirst=True)
