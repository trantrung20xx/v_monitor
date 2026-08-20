import uuid
from datetime import datetime
from sqlalchemy import CheckConstraint, Enum, ForeignKey, Index, Integer, SmallInteger, String, UniqueConstraint, text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP, JSONB
from sqlalchemy import func
from typing import Optional
from app.models.base import Base, UUIDMixin
from app.domain.enums import ProcessingStatus


class TelemetryMessage(Base, UUIDMixin):
    __tablename__ = "telemetry_messages"

    # ID của thiết bị gửi bản tin telemetry
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)

    # Mã ổn định do thiết bị gửi để loại bỏ bản tin MQTT bị phát lại.
    external_message_id: Mapped[Optional[str]] = mapped_column(
        String(128),
        nullable=True,
    )

    topic: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    qos: Mapped[Optional[int]] = mapped_column(SmallInteger, nullable=True)

    # Thời điểm hệ thống nhận được bản tin
    received_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False)

    # Thời điểm dữ liệu được thiết bị đo
    measured_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True), nullable=True)

    # Loại bản tin telemetry
    message_type: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)

    # Giao thức đã truyền bản tin, ví dụ MQTT hoặc HTTP
    protocol: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)

    # Phiên bản cấu trúc payload do thiết bị cung cấp
    schema_version: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)

    # Nội dung dữ liệu telemetry gốc dưới dạng JSON
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)

    # Trạng thái xử lý bản tin
    processing_status: Mapped[ProcessingStatus] = mapped_column(Enum(ProcessingStatus), default=ProcessingStatus.PENDING, nullable=False)

    # Nội dung lỗi nếu xử lý bản tin thất bại
    processing_error: Mapped[Optional[str]] = mapped_column(String, nullable=True)

    processed_at: Mapped[Optional[datetime]] = mapped_column(
        TIMESTAMP(timezone=True),
        nullable=True,
    )

    retry_count: Mapped[int] = mapped_column(
        Integer,
        default=0,
        server_default="0",
        nullable=False,
    )

    # Thời điểm bản ghi được tạo trong cơ sở dữ liệu.
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), default=func.now(), nullable=False)

    # Các quan hệ dữ liệu

    # Liên kết bản tin telemetry với thiết bị gửi dữ liệu
    device = relationship("Device")

    __table_args__ = (
        CheckConstraint(
            "qos IS NULL OR qos BETWEEN 0 AND 2",
            name="ck_telemetry_messages_qos",
        ),
        CheckConstraint(
            "retry_count >= 0",
            name="ck_telemetry_messages_retry_count",
        ),
        UniqueConstraint(
            "device_id",
            "external_message_id",
            name="uq_telemetry_messages_device_external_message",
        ),
        Index(
            "ix_telemetry_messages_device_received",
            "device_id",
            "received_at",
        ),
        Index(
            "ix_telemetry_messages_pending_received",
            "received_at",
            postgresql_where=text(
                "processing_status IN ('PENDING', 'FAILED')"
            ),
        ),
    )
