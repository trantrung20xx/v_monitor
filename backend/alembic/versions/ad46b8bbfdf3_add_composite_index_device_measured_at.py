"""add_composite_index_device_measured_at

Revision ID: ad46b8bbfdf3
Revises: 
Create Date: 2026-08-16 13:46:57.388887

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'ad46b8bbfdf3'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create composite index on location_samples (device_id, measured_at) for high-performance time-range history queries
    op.create_index(
        'ix_location_samples_device_measured',
        'location_samples',
        ['device_id', 'measured_at'],
        unique=False,
        if_not_exists=True,
    )


def downgrade() -> None:
    op.drop_index('ix_location_samples_device_measured', table_name='location_samples', if_exists=True)
