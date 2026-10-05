"""Add product names to fees and fee receipts."""
from alembic import op
import sqlalchemy as sa

revision = "0018"
down_revision = "0017"
branch_labels = None
depends_on = None

def upgrade():
    op.add_column("student_fees", sa.Column("product_name", sa.String(120), nullable=True))
    op.add_column("fee_receipts", sa.Column("product_name", sa.String(120), nullable=True))

def downgrade():
    op.drop_column("fee_receipts", "product_name")
    op.drop_column("student_fees", "product_name")
