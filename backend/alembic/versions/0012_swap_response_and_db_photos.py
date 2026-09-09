"""coach-side swap accept/reject, and move photo storage from disk to the database

Revision ID: 0012
Revises: 0011
Create Date: 2026-09-09

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0012"
down_revision: Union[str, None] = "0011"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

swap_initiator_enum = sa.Enum("ADMIN", "COACH", name="swapinitiator")


def upgrade() -> None:
    swap_initiator_enum.create(op.get_bind(), checkfirst=True)
    op.add_column(
        "coach_swap",
        sa.Column("initiated_by", swap_initiator_enum, nullable=False, server_default="ADMIN"),
    )
    op.add_column("coach_swap", sa.Column("decline_reason", sa.Text(), nullable=True))
    with op.batch_alter_table("coach_swap") as batch_op:
        batch_op.alter_column("initiated_by", server_default=None)

    # Photos move from disk (a path string) to bytes stored directly on the row — Render's
    # free-tier filesystem is ephemeral, so anything saved to disk was silently lost on the
    # next restart/cold-start. Existing path values (plain ASCII, e.g. "uploads/students/x.jpg")
    # cast losslessly to bytea; they're not valid images either way since the files behind them
    # are already gone, so there's no real data to preserve here.
    op.alter_column(
        "student_attendance",
        "selfie_photo",
        type_=sa.LargeBinary(),
        existing_type=sa.String(500),
        postgresql_using="selfie_photo::bytea",
    )
    op.alter_column(
        "user_details",
        "profile_photo",
        type_=sa.LargeBinary(),
        existing_type=sa.String(500),
        postgresql_using="profile_photo::bytea",
    )
    op.alter_column(
        "class_photos",
        "photo_path",
        type_=sa.LargeBinary(),
        existing_type=sa.String(500),
        existing_nullable=False,
        nullable=True,
        postgresql_using="photo_path::bytea",
    )


def downgrade() -> None:
    op.alter_column(
        "class_photos",
        "photo_path",
        type_=sa.String(500),
        existing_type=sa.LargeBinary(),
        nullable=False,
        postgresql_using="encode(photo_path, 'escape')",
    )
    op.alter_column(
        "user_details",
        "profile_photo",
        type_=sa.String(500),
        existing_type=sa.LargeBinary(),
        postgresql_using="encode(profile_photo, 'escape')",
    )
    op.alter_column(
        "student_attendance",
        "selfie_photo",
        type_=sa.String(500),
        existing_type=sa.LargeBinary(),
        postgresql_using="encode(selfie_photo, 'escape')",
    )

    op.drop_column("coach_swap", "decline_reason")
    op.drop_column("coach_swap", "initiated_by")
    swap_initiator_enum.drop(op.get_bind(), checkfirst=True)
