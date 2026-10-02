"""Product charges and dated coach receipts."""
from alembic import op
import sqlalchemy as sa
revision = "0017"
down_revision = "0016"
branch_labels = None
depends_on = None

def upgrade():
    for table in ("student_fees", "fee_receipts"):
        op.add_column(table, sa.Column("product_amount", sa.Numeric(10, 2), nullable=False, server_default="0"))
    op.add_column("fee_receipts", sa.Column("billing_date", sa.Date(), nullable=True))

def downgrade():
    op.drop_column("fee_receipts", "billing_date")
    for table in ("student_fees", "fee_receipts"):
        op.drop_column(table, "product_amount")
