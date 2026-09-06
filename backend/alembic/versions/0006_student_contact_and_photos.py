"""secondary contact number and additional details for students (and any user)

Revision ID: 0006
Revises: 0005
Create Date: 2026-09-06

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0006"
down_revision: Union[str, None] = "0005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("phone_secondary", sa.String(32)))
    op.add_column("user_details", sa.Column("additional_details", sa.Text))


def downgrade() -> None:
    op.drop_column("user_details", "additional_details")
    op.drop_column("users", "phone_secondary")
