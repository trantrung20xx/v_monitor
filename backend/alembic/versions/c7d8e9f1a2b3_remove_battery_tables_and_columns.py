"""remove_battery_tables_and_columns

Revision ID: c7d8e9f1a2b3
Revises: ad46b8bbfdf3
Create Date: 2026-08-17 15:35:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c7d8e9f1a2b3'
down_revision: Union[str, Sequence[str], None] = 'ad46b8bbfdf3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Drop battery_samples table if it exists
    op.execute("DROP TABLE IF EXISTS battery_samples CASCADE;")

    # 2. Drop battery columns from device_latest_state
    op.execute("ALTER TABLE device_latest_state DROP COLUMN IF EXISTS uav_battery_pct;")
    op.execute("ALTER TABLE device_latest_state DROP COLUMN IF EXISTS controller_battery_pct;")

    # 3. Drop batterytype enum if it exists
    op.execute("DROP TYPE IF EXISTS batterytype;")


def downgrade() -> None:
    # Re-add columns to device_latest_state
    op.add_column(
        'device_latest_state',
        sa.Column('uav_battery_pct', sa.Integer(), nullable=True),
    )
    op.add_column(
        'device_latest_state',
        sa.Column('controller_battery_pct', sa.Integer(), nullable=True),
    )
