"""Thêm quyền kích hoạt và danh sách thiết bị MQTT chờ đăng ký.

Revision ID: d8e9f0a1b2c3
Revises: b6d8f0a2c4e5
Create Date: 2026-08-24 11:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "d8e9f0a1b2c3"
down_revision: Union[str, Sequence[str], None] = "b6d8f0a2c4e5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


SIGHTINGS_TABLE = "mqtt_device_sightings"


def _inspector() -> sa.Inspector:
    return sa.inspect(op.get_bind())


def _has_table(table_name: str) -> bool:
    return table_name in _inspector().get_table_names()


def _has_column(table_name: str, column_name: str) -> bool:
    return _has_table(table_name) and any(
        column["name"] == column_name
        for column in _inspector().get_columns(table_name)
    )


def upgrade() -> None:
    if not _has_column("devices", "is_enabled"):
        op.add_column(
            "devices",
            sa.Column(
                "is_enabled",
                sa.Boolean(),
                server_default=sa.true(),
                nullable=False,
            ),
        )

    if not _has_table(SIGHTINGS_TABLE):
        op.create_table(
            SIGHTINGS_TABLE,
            sa.Column("device_code", sa.String(length=50), nullable=False),
            sa.Column(
                "first_seen_at",
                postgresql.TIMESTAMP(timezone=True),
                server_default=sa.func.now(),
                nullable=False,
            ),
            sa.Column(
                "last_seen_at",
                postgresql.TIMESTAMP(timezone=True),
                server_default=sa.func.now(),
                nullable=False,
            ),
            sa.Column(
                "message_count",
                sa.BigInteger(),
                server_default="1",
                nullable=False,
            ),
            sa.Column("last_topic", sa.String(length=255), nullable=False),
            sa.CheckConstraint(
                "length(btrim(device_code)) >= 1",
                name="ck_mqtt_device_sightings_code_not_blank",
            ),
            sa.CheckConstraint(
                "message_count >= 1",
                name="ck_mqtt_device_sightings_message_count",
            ),
            sa.PrimaryKeyConstraint(
                "device_code",
                name="mqtt_device_sightings_pkey",
            ),
        )
        op.create_index(
            "ix_mqtt_device_sightings_last_seen",
            SIGHTINGS_TABLE,
            ["last_seen_at"],
        )


def downgrade() -> None:
    if _has_table(SIGHTINGS_TABLE):
        op.drop_table(SIGHTINGS_TABLE)
    if _has_column("devices", "is_enabled"):
        op.drop_column("devices", "is_enabled")
