"""batch active months (recurring schedule restricted to selected months)

Revision ID: 0011
Revises: 0010
Create Date: 2026-09-06

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0011"
down_revision: Union[str, None] = "0010"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

ALL_MONTHS = "1,2,3,4,5,6,7,8,9,10,11,12"


def upgrade() -> None:
    op.add_column(
        "batches",
        sa.Column("active_months", sa.String(60), nullable=False, server_default=ALL_MONTHS),
    )
    op.alter_column("batches", "active_months", server_default=None)


def downgrade() -> None:
    op.drop_column("batches", "active_months")
