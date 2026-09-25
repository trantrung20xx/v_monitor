"""Thêm catalog LTE, radio observations và vị trí cell tách biệt GPS.

Ba bảng mới tạo chuỗi audit ``telemetry_messages -> cell_observations ->
cell_position_estimates``. ``device_latest_state`` chỉ giữ con trỏ tới estimate
mới nhất, không dùng hoặc sửa các cột GPS hiện hữu.

Revision ID: g1c4e7a9d2f6
Revises: c8e0f2a4b6d8
Create Date: 2026-09-25 13:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
from geoalchemy2 import Geography
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "g1c4e7a9d2f6"
down_revision: Union[str, Sequence[str], None] = "c8e0f2a4b6d8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _is_bootstrapped_current_schema() -> bool:
    """Alembic's empty-DB bootstrap creates the current SQLAlchemy metadata.

    The project intentionally does this before replaying historical migrations.
    Avoid trying to create these new tables a second time in that path while
    retaining the normal migration behavior for an existing deployment.
    """
    inspector = sa.inspect(op.get_bind())
    tables = set(inspector.get_table_names())
    if not {"cell_towers", "cell_observations", "cell_position_estimates"}.issubset(tables):
        return False
    return {"latest_cell_estimate_id", "latest_cell_measured_at"}.issubset({
        column["name"] for column in inspector.get_columns("device_latest_state")
    })


def upgrade() -> None:
    # env.py bootstrap database rỗng bằng Base.metadata.create_all() trước khi
    # Alembic replay lịch sử. Khi đó schema hiện tại đã có tất cả object của
    # revision này; return tránh CREATE TABLE/ADD COLUMN lần hai. Database đang
    # ở revision cũ thật sự không có các object này nên đi tiếp DDL bên dưới.
    if _is_bootstrapped_current_schema():
        return

    # Catalog là nguồn tọa độ tin cậy. Observation và estimate phía sau mới có
    # foreign key tới catalog/telemetry để tạo chuỗi truy vết đầy đủ.
    op.create_table(
        "cell_towers",
        sa.Column("rat", sa.String(length=12), nullable=False, server_default="LTE"),
        sa.Column("mcc", sa.String(length=3), nullable=False),
        sa.Column("mnc", sa.String(length=3), nullable=False),
        sa.Column("tac", sa.Integer(), nullable=False),
        sa.Column("cell_id", sa.BigInteger(), nullable=False),
        sa.Column("pci", sa.Integer(), nullable=True),
        sa.Column("earfcn", sa.Integer(), nullable=True),
        sa.Column("site_key", sa.String(length=128), nullable=True),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
        sa.Column("location", Geography(geometry_type="POINT", srid=4326), nullable=False),
        sa.Column("accuracy_m", sa.Float(), nullable=True),
        sa.Column("source", sa.String(length=100), nullable=True),
        sa.Column("source_updated_at", postgresql.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", postgresql.TIMESTAMP(timezone=True), nullable=False),
        sa.Column("updated_at", postgresql.TIMESTAMP(timezone=True), nullable=False),
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.CheckConstraint("rat = 'LTE'", name="ck_cell_towers_rat_lte"),
        sa.CheckConstraint("mcc ~ '^[0-9]{3}$'", name="ck_cell_towers_mcc"),
        sa.CheckConstraint("mnc ~ '^[0-9]{2,3}$'", name="ck_cell_towers_mnc"),
        sa.CheckConstraint("tac BETWEEN 0 AND 65535", name="ck_cell_towers_tac"),
        sa.CheckConstraint("cell_id BETWEEN 0 AND 268435455", name="ck_cell_towers_cell_id"),
        sa.CheckConstraint("latitude BETWEEN -90 AND 90", name="ck_cell_towers_latitude"),
        sa.CheckConstraint("longitude BETWEEN -180 AND 180", name="ck_cell_towers_longitude"),
        sa.CheckConstraint("accuracy_m IS NULL OR accuracy_m >= 0", name="ck_cell_towers_accuracy"),
        sa.CheckConstraint("pci IS NULL OR pci BETWEEN 0 AND 503", name="ck_cell_towers_pci"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("rat", "mcc", "mnc", "tac", "cell_id", name="uq_cell_towers_identity"),
    )
    op.create_index(
        "ix_cell_towers_active_identity",
        "cell_towers",
        ["is_active", "rat", "mcc", "mnc", "tac", "cell_id"],
    )

    # Một row cho serving hoặc từng neighbor. Các identity có thể null vì modem
    # thường chỉ cung cấp PCI/EARFCN cho neighbor, nhưng raw scan vẫn cần lưu.
    op.create_table(
        "cell_observations",
        sa.Column("telemetry_message_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("device_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("measured_at", postgresql.TIMESTAMP(timezone=True), nullable=False),
        sa.Column("observation_index", sa.SmallInteger(), nullable=False),
        sa.Column("is_serving", sa.Boolean(), nullable=False),
        sa.Column("rat", sa.String(length=12), nullable=False, server_default="LTE"),
        sa.Column("mcc", sa.String(length=3), nullable=True),
        sa.Column("mnc", sa.String(length=3), nullable=True),
        sa.Column("tac", sa.Integer(), nullable=True),
        sa.Column("cell_id", sa.BigInteger(), nullable=True),
        sa.Column("pci", sa.Integer(), nullable=True),
        sa.Column("earfcn", sa.Integer(), nullable=True),
        sa.Column("rsrp_dbm", sa.Float(), nullable=True),
        sa.Column("rsrq_db", sa.Float(), nullable=True),
        sa.Column("sinr_db", sa.Float(), nullable=True),
        sa.Column("matched_cell_tower_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("raw_json", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.CheckConstraint("rat = 'LTE'", name="ck_cell_observations_rat_lte"),
        sa.CheckConstraint("mcc IS NULL OR mcc ~ '^[0-9]{3}$'", name="ck_cell_observations_mcc"),
        sa.CheckConstraint("mnc IS NULL OR mnc ~ '^[0-9]{2,3}$'", name="ck_cell_observations_mnc"),
        sa.CheckConstraint("tac IS NULL OR tac BETWEEN 0 AND 65535", name="ck_cell_observations_tac"),
        sa.CheckConstraint("cell_id IS NULL OR cell_id BETWEEN 0 AND 268435455", name="ck_cell_observations_cell_id"),
        sa.CheckConstraint("pci IS NULL OR pci BETWEEN 0 AND 503", name="ck_cell_observations_pci"),
        sa.CheckConstraint("rsrp_dbm IS NULL OR rsrp_dbm BETWEEN -160 AND -30", name="ck_cell_observations_rsrp"),
        sa.ForeignKeyConstraint(["telemetry_message_id"], ["telemetry_messages.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["device_id"], ["devices.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["matched_cell_tower_id"], ["cell_towers.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("telemetry_message_id", "observation_index", name="uq_cell_observations_message_index"),
    )
    op.create_index("ix_cell_observations_device_measured", "cell_observations", ["device_id", "measured_at"])

    # Lưu cả NO_MATCH/REJECTED_ACCURACY để vận hành phân biệt catalog thiếu với
    # lỗi worker. CHECK coordinate_pair bắt buộc lat/lon cùng có hoặc cùng null.
    op.create_table(
        "cell_position_estimates",
        sa.Column("device_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("telemetry_message_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("measured_at", postgresql.TIMESTAMP(timezone=True), nullable=False),
        sa.Column("received_at", postgresql.TIMESTAMP(timezone=True), nullable=False),
        sa.Column("method", sa.String(length=80), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("latitude", sa.Float(), nullable=True),
        sa.Column("longitude", sa.Float(), nullable=True),
        sa.Column("location", Geography(geometry_type="POINT", srid=4326), nullable=True),
        sa.Column("accuracy_m", sa.Float(), nullable=True),
        sa.Column("confidence", sa.Float(), nullable=False, server_default="0"),
        sa.Column("matched_cell_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("diagnostics_json", postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default=sa.text("'{}'::jsonb")),
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.CheckConstraint("status IN ('ESTIMATED', 'NO_MATCH', 'REJECTED_ACCURACY')", name="ck_cell_position_estimates_status"),
        sa.CheckConstraint("latitude IS NULL OR latitude BETWEEN -90 AND 90", name="ck_cell_position_estimates_latitude"),
        sa.CheckConstraint("longitude IS NULL OR longitude BETWEEN -180 AND 180", name="ck_cell_position_estimates_longitude"),
        sa.CheckConstraint("(latitude IS NULL) = (longitude IS NULL)", name="ck_cell_position_estimates_coordinate_pair"),
        sa.CheckConstraint("accuracy_m IS NULL OR accuracy_m >= 0", name="ck_cell_position_estimates_accuracy"),
        sa.CheckConstraint("confidence BETWEEN 0 AND 1", name="ck_cell_position_estimates_confidence"),
        sa.ForeignKeyConstraint(["device_id"], ["devices.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["telemetry_message_id"], ["telemetry_messages.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("telemetry_message_id", name="uq_cell_position_estimates_message"),
    )
    op.create_index(
        "ix_cell_position_estimates_device_measured",
        "cell_position_estimates",
        ["device_id", "measured_at", "id"],
    )
    # Hai metadata LTE ở latest_state được tách khỏi latest_measured_at GPS.
    # latest_cell_measured_at giúp gói cũ đến muộn không ghi đè estimate mới.
    op.add_column(
        "device_latest_state",
        sa.Column("latest_cell_estimate_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.add_column(
        "device_latest_state",
        sa.Column("latest_cell_measured_at", postgresql.TIMESTAMP(timezone=True), nullable=True),
    )
    op.create_foreign_key(
        "device_latest_state_latest_cell_estimate_id_fkey",
        "device_latest_state",
        "cell_position_estimates",
        ["latest_cell_estimate_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    # Thứ tự ngược bảo vệ foreign key: bỏ con trỏ state trước, rồi các bảng con
    # estimate/observation, cuối cùng mới đến catalog anchor.
    op.drop_constraint(
        "device_latest_state_latest_cell_estimate_id_fkey",
        "device_latest_state",
        type_="foreignkey",
    )
    op.drop_column("device_latest_state", "latest_cell_measured_at")
    op.drop_column("device_latest_state", "latest_cell_estimate_id")
    op.drop_index("ix_cell_position_estimates_device_measured", table_name="cell_position_estimates")
    op.drop_table("cell_position_estimates")
    op.drop_index("ix_cell_observations_device_measured", table_name="cell_observations")
    op.drop_table("cell_observations")
    op.drop_index("ix_cell_towers_active_identity", table_name="cell_towers")
    op.drop_table("cell_towers")
