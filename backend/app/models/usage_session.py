import uuid
from datetime import datetime
from sqlalchemy import ForeignKey, String, Float, Integer, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP
from geoalchemy2 import Geography
from typing import Optional
from app.models.base import Base, UUIDMixin, TimestampMixin
from app.domain.enums import UsageStatus

class UsageSession(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "usage_sessions"
    
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), index=True, nullable=False)
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("people.id"), nullable=True)
    responsible_person_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("people.id"), nullable=True)
    
    started_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), index=True, nullable=False)
    ended_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    
    start_location = mapped_column(Geography(geometry_type='POINT', srid=4326), nullable=True)
    end_location = mapped_column(Geography(geometry_type='POINT', srid=4326), nullable=True)
    
    distance_m: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    avg_speed_mps: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    max_speed_mps: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    
    moving_duration_s: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    stopped_duration_s: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    
    route_geometry = mapped_column(Geography(geometry_type='LINESTRING', srid=4326), nullable=True)
    
    status: Mapped[UsageStatus] = mapped_column(Enum(UsageStatus), default=UsageStatus.ACTIVE, nullable=False)
    end_reason: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    
    # Relationships
    device = relationship("Device")
    user = relationship("Person", foreign_keys=[user_id])
    responsible_person = relationship("Person", foreign_keys=[responsible_person_id])
