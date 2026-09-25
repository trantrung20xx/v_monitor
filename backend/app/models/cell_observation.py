"""Các serving/neighbor cell đã được modem quan sát trong một telemetry.

Mỗi row là dữ liệu thô của một lần quét, kể cả cell chưa tồn tại trong catalog.
Lịch sử này giúp đối chiếu modem và cải thiện catalog mà không biến dữ liệu chưa
được xác thực thành một vị trí địa lý.
"""
import uuid
from datetime import datetime

from sqlalchemy import BigInteger, Boolean, CheckConstraint, Float, ForeignKey, Index, Integer, SmallInteger, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, UUIDMixin


class CellObservation(Base, UUIDMixin):
    __tablename__ = "cell_observations"
    __table_args__ = (
        # Index là vị trí của cell trong scan: 0 là serving, các index sau là
        # neighbor. Unique giữ thứ tự này không bị ghi trùng trong một telemetry.
        UniqueConstraint("telemetry_message_id", "observation_index", name="uq_cell_observations_message_index"),
        CheckConstraint("rat = 'LTE'", name="ck_cell_observations_rat_lte"),
        CheckConstraint("mcc IS NULL OR mcc ~ '^[0-9]{3}$'", name="ck_cell_observations_mcc"),
        CheckConstraint("mnc IS NULL OR mnc ~ '^[0-9]{2,3}$'", name="ck_cell_observations_mnc"),
        CheckConstraint("tac IS NULL OR tac BETWEEN 0 AND 65535", name="ck_cell_observations_tac"),
        CheckConstraint("cell_id IS NULL OR cell_id BETWEEN 0 AND 268435455", name="ck_cell_observations_cell_id"),
        CheckConstraint("pci IS NULL OR pci BETWEEN 0 AND 503", name="ck_cell_observations_pci"),
        CheckConstraint("rsrp_dbm IS NULL OR rsrp_dbm BETWEEN -160 AND -30", name="ck_cell_observations_rsrp"),
        # Dùng cho audit scan của một thiết bị theo thời gian, không phục vụ lookup
        # nóng (lookup nóng chỉ đọc cell_towers).
        Index("ix_cell_observations_device_measured", "device_id", "measured_at"),
    )

    telemetry_message_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("telemetry_messages.id", ondelete="CASCADE"), nullable=False
    )
    device_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("devices.id", ondelete="CASCADE"), nullable=False
    )
    measured_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False)
    observation_index: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    is_serving: Mapped[bool] = mapped_column(Boolean, nullable=False)
    rat: Mapped[str] = mapped_column(String(12), nullable=False, default="LTE")
    mcc: Mapped[str | None] = mapped_column(String(3), nullable=True)
    mnc: Mapped[str | None] = mapped_column(String(3), nullable=True)
    tac: Mapped[int | None] = mapped_column(Integer, nullable=True)
    cell_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    pci: Mapped[int | None] = mapped_column(Integer, nullable=True)
    earfcn: Mapped[int | None] = mapped_column(Integer, nullable=True)
    rsrp_dbm: Mapped[float | None] = mapped_column(Float, nullable=True)
    rsrq_db: Mapped[float | None] = mapped_column(Float, nullable=True)
    sinr_db: Mapped[float | None] = mapped_column(Float, nullable=True)
    # SET NULL bảo toàn raw observation nếu catalog row bị xóa trong tương lai;
    # không cascade vì telemetry lịch sử vẫn có giá trị chẩn đoán.
    matched_cell_tower_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("cell_towers.id", ondelete="SET NULL"), nullable=True
    )
    # Chỉ các trường định vị chuẩn được tách cột để query. JSONB giữ alias/field
    # modem bổ sung đã được chấp nhận để có thể điều tra mà không đổi schema.
    raw_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
