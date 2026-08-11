import uuid
from datetime import datetime
from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP, JSONB
from sqlalchemy import func
from geoalchemy2 import Geography
from typing import Optional
from app.models.base import Base, UUIDMixin

class DeviceEvent(Base, UUIDMixin):
    __tablename__ = "device_events"
    
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), index=True, nullable=False)
    
    event_type: Mapped[str] = mapped_column(String, index=True, nullable=False)
    
    occurred_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), index=True, nullable=False)
    received_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False)
    
    person_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("people.id"), nullable=True)
    usage_session_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("usage_sessions.id"), nullable=True)
    
    location = mapped_column(Geography(geometry_type='POINT', srid=4326), nullable=True)
    metadata_: Mapped[Optional[dict]] = mapped_column("metadata", JSONB, nullable=True)
    
    source: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), default=func.now(), nullable=False)
    
    # Relationships
    device = relationship("Device")
    person = relationship("Person")
    usage_session = relationship("UsageSession")
