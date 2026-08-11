import uuid
from sqlalchemy import ForeignKey, String, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, JSONB
from typing import Optional
from app.models.base import Base, UUIDMixin, TimestampMixin

class UavControllerProfile(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "uav_controller_profiles"
    
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), unique=True, nullable=False)
    hardware_version: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    battery_capacity_mah: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    connection_type: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    metadata_: Mapped[Optional[dict]] = mapped_column("metadata", JSONB, nullable=True)
    
    # Relationships
    device = relationship("Device", back_populates="uav_profile")
