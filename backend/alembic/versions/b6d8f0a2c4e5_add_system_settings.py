"""Thêm cấu hình nghiệp vụ dùng chung.

Revision ID: b6d8f0a2c4e5
Revises: a4c6e8f0b2d3
Create Date: 2026-08-21 09:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "b6d8f0a2c4e5"
down_revision: Union[str, Sequence[str], None] = "a4c6e8f0b2d3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


TABLE_NAME = "system_settings"


def _has_table() -> bool:
    return TABLE_NAME in sa.inspect(op.get_bind()).get_table_names()


def upgrade() -> None:
    if not _has_table():
        op.create_table(
            TABLE_NAME,
            sa.Column("id", sa.SmallInteger(), nullable=False),
            sa.Column("offline_timeout_seconds", sa.Integer(), nullable=False),
            sa.Column("movement_threshold_mps", sa.Float(), nullable=False),
            sa.Column(
                "default_gap_threshold_seconds",
                sa.Integer(),
                nullable=False,
            ),
            sa.Column(
                "updated_by",
                postgresql.UUID(as_uuid=True),
                nullable=True,
            ),
            sa.Column(
                "created_at",
                postgresql.TIMESTAMP(timezone=True),
                server_default=sa.func.now(),
                nullable=False,
            ),
            sa.Column(
                "updated_at",
                postgresql.TIMESTAMP(timezone=True),
                server_default=sa.func.now(),
                nullable=False,
            ),
            sa.CheckConstraint("id = 1", name="ck_system_settings_singleton"),
            sa.CheckConstraint(
                "offline_timeout_seconds BETWEEN 30 AND 86400",
                name="ck_system_settings_offline_timeout",
            ),
            sa.CheckConstraint(
                "movement_threshold_mps BETWEEN 0.0 AND 10.0",
                name="ck_system_settings_movement_threshold",
            ),
            sa.CheckConstraint(
                "default_gap_threshold_seconds BETWEEN 60 AND 3600",
                name="ck_system_settings_gap_threshold",
            ),
            sa.ForeignKeyConstraint(
                ["updated_by"],
                ["user_accounts.id"],
                name="system_settings_updated_by_fkey",
                ondelete="SET NULL",
            ),
            sa.PrimaryKeyConstraint("id", name="system_settings_pkey"),
        )

    # create_all có thể đã tạo bảng trên database trống trước khi Alembic chạy;
    # câu lệnh idempotent này vẫn bảo đảm singleton và các giá trị tương thích cũ.
    op.execute(
        sa.text(
            """
            INSERT INTO system_settings (
                id,
                offline_timeout_seconds,
                movement_threshold_mps,
                default_gap_threshold_seconds,
                created_at,
                updated_at
            ) VALUES (1, 300, 0.5, 300, now(), now())
            ON CONFLICT (id) DO NOTHING
            """
        )
    )


def downgrade() -> None:
    if _has_table():
        op.drop_table(TABLE_NAME)
