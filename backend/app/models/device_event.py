import uuid
from datetime import datetime, timezone
from sqlalchemy import ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP, JSONB
from sqlalchemy import func
from geoalchemy2 import Geography
from typing import Optional
from app.models.base import Base, UUIDMixin

class DeviceEvent(Base, UUIDMixin):
    __tablename__ = "device_events"

    # ID của thiết bị phát sinh sự kiện
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)

    # Loại sự kiện (STATUS_CHANGE, GEOFENCE_EXIT, ERROR, v.v.)
    event_type: Mapped[str] = mapped_column(String(50), nullable=False)

    # Thời điểm sự kiện xảy ra
    occurred_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False)

    # Thời điểm server nhận sự kiện, khác với thời điểm thiết bị ghi nhận
    received_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    # Vị trí thiết bị tại thời điểm xảy ra sự kiện
    location = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=True)

    # Dữ liệu bổ sung của sự kiện nếu cần
    metadata_: Mapped[Optional[dict]] = mapped_column("metadata", JSONB, nullable=True)

    # Nguồn có cấu trúc giúp lọc sự kiện mà không phải đọc JSON metadata
    source: Mapped[Optional[str]] = mapped_column(String, nullable=True)

    # Nội dung mô tả dùng trực tiếp cho API và giao diện
    description: Mapped[Optional[str]] = mapped_column(String, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        default=func.now(),
        nullable=False,
    )

    # Các quan hệ dữ liệu
    device = relationship("Device")

    __table_args__ = (
        Index(
            "ix_device_events_device_occurred_id",
            "device_id",
            "occurred_at",
            "id",
        ),
        Index(
            "ix_device_events_device_type_occurred",
            "device_id",
            "event_type",
            "occurred_at",
        ),
    )
