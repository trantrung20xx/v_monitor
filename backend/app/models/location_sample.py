import uuid
from datetime import datetime
from sqlalchemy import CheckConstraint, Float, ForeignKey, Index, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP
from sqlalchemy import func
from geoalchemy2 import Geography
from typing import Optional
from app.models.base import Base, UUIDMixin

class LocationSample(Base, UUIDMixin):
    __tablename__ = "location_samples"
    __table_args__ = (
        Index(
            "ix_location_samples_device_measured_id",
            "device_id",
            "measured_at",
            "id",
        ),
        UniqueConstraint(
            "source_message_id",
            name="uq_location_samples_source_message_id",
        ),
        CheckConstraint(
            "latitude BETWEEN -90 AND 90",
            name="ck_location_samples_latitude",
        ),
        CheckConstraint(
            "longitude BETWEEN -180 AND 180",
            name="ck_location_samples_longitude",
        ),
        CheckConstraint(
            "speed_mps IS NULL OR speed_mps >= 0",
            name="ck_location_samples_speed",
        ),
        CheckConstraint(
            "heading_deg IS NULL OR (heading_deg >= 0 AND heading_deg < 360)",
            name="ck_location_samples_heading",
        ),
        CheckConstraint(
            "accuracy_m IS NULL OR accuracy_m >= 0",
            name="ck_location_samples_accuracy",
        ),
        CheckConstraint(
            "satellite_count IS NULL OR satellite_count >= 0",
            name="ck_location_samples_satellites",
        ),
    )
    
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)
    
    measured_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), index=True, nullable=False)
    received_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False)
    
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    location = mapped_column(Geography(geometry_type='POINT', srid=4326), nullable=False)
    
    altitude_m: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    speed_mps: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    heading_deg: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    accuracy_m: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    satellite_count: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    
    source: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    source_message_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("telemetry_messages.id", ondelete="SET NULL"),
        nullable=True,
    )
    
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), default=func.now(), nullable=False)
    
    # Các quan hệ dữ liệu
    device = relationship("Device")
