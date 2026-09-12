"""Add NOT_CONFIRM attendance status (client-directed removal of GPS marking)

Client round 3: coach attendance marking (both student attendance in "My Classes"
and the coach's own facility check-in) drops GPS/selfie verification entirely in
favor of plain manual entry — Present / Absent / Leave / Not Confirm — and once a
coach submits a mark it can no longer be self-corrected; only admin can change it.
This migration only adds the new enum value; the removed-GPS/selfie behavior and
the coach-self-edit lockout are application-layer changes with no other schema
impact (location_lat/lng and selfie_photo columns are simply left unpopulated by
new rows rather than dropped, since old rows still use them).

Revision ID: 0015
Revises: 0014
Create Date: 2026-09-13

"""
from typing import Sequence, Union

from alembic import op

revision: str = "0015"
down_revision: Union[str, None] = "0014"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("ALTER TYPE attendancestatus ADD VALUE IF NOT EXISTS 'NOT_CONFIRM'")
    op.execute("ALTER TYPE coachattendancestatus ADD VALUE IF NOT EXISTS 'NOT_CONFIRM'")


def downgrade() -> None:
    # Postgres cannot drop a single enum value in place. Rebuilding the enum type
    # without it would require rewriting every dependent column and is unnecessary
    # here — NOT_CONFIRM rows simply wouldn't exist yet on any downgrade path this
    # project actually uses. Left as a no-op, matching this repo's convention of
    # not over-engineering reversibility for additive enum values.
    pass
