import uuid
from datetime import datetime
from sqlalchemy import ForeignKey, String, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP, JSONB
from sqlalchemy import func
from typing import Optional
from app.models.base import Base, UUIDMixin
from app.domain.enums import ProcessingStatus


class TelemetryMessage(Base, UUIDMixin):
    __tablename__ = "telemetry_messages"

    # ID của thiết bị gửi bản tin telemetry
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), index=True, nullable=False)

    # Thời điểm hệ thống nhận được bản tin
    received_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False)

    # Thời điểm dữ liệu được thiết bị đo
    measured_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True), nullable=True)

    # Loại bản tin telemetry
    message_type: Mapped[Optional[str]] = mapped_column(String, nullable=True)

    # Nội dung dữ liệu telemetry gốc dưới dạng JSON
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)

    # Trạng thái xử lý bản tin
    processing_status: Mapped[ProcessingStatus] = mapped_column(Enum(ProcessingStatus), default=ProcessingStatus.PENDING, nullable=False)

    # Nội dung lỗi nếu xử lý bản tin thất bại
    processing_error: Mapped[Optional[str]] = mapped_column(String, nullable=True)

    # Thời điểm bản ghi được tạo trong database
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), default=func.now(), nullable=False)

    # Relationships

    # Liên kết bản tin telemetry với thiết bị gửi dữ liệu
    device = relationship("Device")
