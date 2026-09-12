"""Add group photo columns to classes (coach mobile app group/batch photo)

Client request (2026-09-13, follow-up to the GPS/selfie removal round): a coach
should be able to capture a single photo covering the whole class roster once a
session has finished, from the mobile coach app's Classes tab. This is a plain
additive column pair on the existing `classes` table (one photo per class
occurrence, same "bytes in Postgres" pattern as every other photo in this app —
see backend/app/services/storage.py) — not a new ClassPhoto table like the old,
now-deleted compliance-era feature, which allowed many photos per class and
stored them on disk.

Revision ID: 0016
Revises: 0015
Create Date: 2026-09-13

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0016"
down_revision: Union[str, None] = "0015"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("classes", sa.Column("group_photo", sa.LargeBinary(), nullable=True))
    op.add_column("classes", sa.Column("group_photo_uploaded_at", sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column("classes", "group_photo_uploaded_at")
    op.drop_column("classes", "group_photo")
