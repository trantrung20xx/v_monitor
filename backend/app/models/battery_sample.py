import uuid
from datetime import datetime
from sqlalchemy import ForeignKey, String, Float, Integer, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP
from sqlalchemy import func
from typing import Optional
from app.models.base import Base, UUIDMixin
from app.domain.enums import BatteryType

class BatterySample(Base, UUIDMixin):
    __tablename__ = "battery_samples"

    # ID của thiết bị gửi dữ liệu pin
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), index=True, nullable=False)

    # Loại pin được đo
    battery_type: Mapped[BatteryType] = mapped_column(Enum(BatteryType), nullable=False)

    # Thời điểm thiết bị đo thông số pin
    measured_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), index=True, nullable=False)

    # Phần trăm pin còn lại (%)
    percent: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    # Điện áp của pin (V)
    voltage: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Dòng điện tiêu thụ hoặc sạc (A)
    current_a: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Nhiệt độ pin (°C)
    temperature_c: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Thời gian sử dụng còn lại dự kiến (giây)
    time_remaining_s: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    # Trạng thái sạc hoặc sử dụng của pin
    charge_state: Mapped[Optional[str]] = mapped_column(String, nullable=True)

    # ID của bản tin telemetry chứa dữ liệu pin
    source_message_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("telemetry_messages.id"), nullable=True)

    # Thời điểm bản ghi được tạo trong database
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), default=func.now(), nullable=False)

    # Relationships

    # Liên kết mẫu pin với thiết bị tương ứng
    device = relationship("Device")
