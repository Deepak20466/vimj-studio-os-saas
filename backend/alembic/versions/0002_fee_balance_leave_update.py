"""add balance_amount to student_fees

Revision ID: 0002
Revises: 0001
Create Date: 2026-09-02

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0002"
down_revision: Union[str, None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "student_fees",
        sa.Column("balance_amount", sa.Numeric(10, 2), nullable=False, server_default="0"),
    )
    op.execute(
        "UPDATE student_fees SET balance_amount = CASE WHEN status = 'PAID' THEN 0 ELSE amount END"
    )


def downgrade() -> None:
    op.drop_column("student_fees", "balance_amount")
