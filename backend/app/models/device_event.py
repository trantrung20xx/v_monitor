import uuid
from datetime import datetime
from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP, JSONB
from geoalchemy2 import Geography
from typing import Optional
from app.models.base import Base, UUIDMixin

class DeviceEvent(Base, UUIDMixin):
    __tablename__ = "device_events"

    # ID của thiết bị phát sinh sự kiện
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), index=True, nullable=False)

    # Loại sự kiện (STATUS_CHANGE, GEOFENCE_EXIT, ERROR, v.v.)
    event_type: Mapped[str] = mapped_column(String, index=True, nullable=False)

    # Thời điểm sự kiện xảy ra
    occurred_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), index=True, nullable=False)

    # Vị trí thiết bị tại thời điểm xảy ra sự kiện
    location = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=True)

    # Dữ liệu bổ sung của sự kiện nếu cần
    metadata_: Mapped[Optional[dict]] = mapped_column("metadata", JSONB, nullable=True)

    # Relationships
    device = relationship("Device")
