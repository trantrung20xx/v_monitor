import uuid
from datetime import datetime
from sqlalchemy import ForeignKey, String, Float, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP
from sqlalchemy import func
from geoalchemy2 import Geography
from typing import Optional
from app.models.base import Base, UUIDMixin

class LocationSample(Base, UUIDMixin):
    __tablename__ = "location_samples"
    
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), index=True, nullable=False)
    
    measured_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), index=True, nullable=False)
    received_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False)
    
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    location = mapped_column(Geography(geometry_type='POINT', srid=4326), index=True, nullable=False)
    
    altitude_m: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    speed_mps: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    heading_deg: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    accuracy_m: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    satellite_count: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    
    source: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    source_message_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("telemetry_messages.id"), nullable=True)
    
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), default=func.now(), nullable=False)
    
    # Relationships
    device = relationship("Device")
