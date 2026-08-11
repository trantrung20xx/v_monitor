import uuid
from datetime import datetime
from sqlalchemy import ForeignKey, String, Float, Integer, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP
from sqlalchemy import func
from typing import Optional
from app.models.base import Base, UUIDMixin
from app.domain.enums import BatteryType

class BatterySample(Base, UUIDMixin):
    __tablename__ = "battery_samples"
    
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), index=True, nullable=False)
    battery_type: Mapped[BatteryType] = mapped_column(Enum(BatteryType), nullable=False)
    
    measured_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), index=True, nullable=False)
    
    percent: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    voltage: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    current_a: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    temperature_c: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    time_remaining_s: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    charge_state: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    
    source_message_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("telemetry_messages.id"), nullable=True)
    
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), default=func.now(), nullable=False)
    
    # Relationships
    device = relationship("Device")
