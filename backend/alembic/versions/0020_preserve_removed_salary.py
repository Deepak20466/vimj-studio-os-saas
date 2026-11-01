"""Bridge the production Alembic history without restoring removed Salary data.

Production recorded revision 0020 when legacy coach_salary rows were preserved.
This product branch intentionally removed Salary, so this bridge performs no
schema operation and never creates, changes, or drops the legacy table.
"""

revision = "0020"
down_revision = "0019"
branch_labels = None
depends_on = None


def upgrade():
    pass


def downgrade():
    raise RuntimeError("Refusing to alter legacy schema during downgrade")
