"""Store authenticated devices for Firebase Cloud Messaging."""
from alembic import op
import sqlalchemy as sa


revision = "0022"
down_revision = "0021"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "push_device_tokens",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("token", sa.String(length=512), nullable=False),
        sa.Column("platform", sa.String(length=20), nullable=False, server_default="android"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_push_device_tokens_id", "push_device_tokens", ["id"])
    op.create_index("ix_push_device_tokens_user_id", "push_device_tokens", ["user_id"])
    op.create_index("ix_push_device_tokens_token", "push_device_tokens", ["token"], unique=True)


def downgrade():
    op.drop_index("ix_push_device_tokens_token", table_name="push_device_tokens")
    op.drop_index("ix_push_device_tokens_user_id", table_name="push_device_tokens")
    op.drop_index("ix_push_device_tokens_id", table_name="push_device_tokens")
    op.drop_table("push_device_tokens")
