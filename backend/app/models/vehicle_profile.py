import uuid
from sqlalchemy import ForeignKey, String, Integer, Float
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, JSONB
from typing import Optional
from app.models.base import Base, UUIDMixin, TimestampMixin

class VehicleProfile(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "vehicle_profiles"
    
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), unique=True, nullable=False)
    license_plate: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    vin: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    vehicle_type: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    fuel_type: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    engine_type: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    model_year: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    odometer_km: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    metadata_: Mapped[Optional[dict]] = mapped_column("metadata", JSONB, nullable=True)
    
    # Relationships
    device = relationship("Device", back_populates="vehicle_profile")
