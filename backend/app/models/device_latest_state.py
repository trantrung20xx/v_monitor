from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import ForeignKey, Float, Boolean, Integer
from sqlalchemy.dialects.postgresql import UUID
from datetime import datetime
import uuid
from app.models.base import Base, TimestampMixin

class DeviceLatestState(Base, TimestampMixin):
    __tablename__ = "device_latest_state"
    
    device_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), 
        ForeignKey("devices.id", ondelete="CASCADE"), 
        primary_key=True
    )
    last_seen_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)
    is_online: Mapped[bool] = mapped_column(Boolean, default=False)
    current_latitude: Mapped[float] = mapped_column(Float, nullable=True)
    current_longitude: Mapped[float] = mapped_column(Float, nullable=True)
    current_speed_mps: Mapped[float] = mapped_column(Float, nullable=True)
    current_heading_deg: Mapped[float] = mapped_column(Float, nullable=True)
    controller_battery_pct: Mapped[int] = mapped_column(Integer, nullable=True)
    uav_battery_pct: Mapped[int] = mapped_column(Integer, nullable=True)
    
    device = relationship("Device", back_populates="latest_state")
