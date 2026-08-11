from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import String, Enum
from sqlalchemy.dialects.postgresql import JSONB
from app.models.base import Base, UUIDMixin, TimestampMixin
import enum

class DeviceType(str, enum.Enum):
    UAV_CONTROLLER = "UAV_CONTROLLER"
    VEHICLE = "VEHICLE"
    OTHER = "OTHER"

class DeviceStatus(str, enum.Enum):
    UNKNOWN = "UNKNOWN"
    OFFLINE = "OFFLINE"
    ONLINE = "ONLINE"
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    MAINTENANCE = "MAINTENANCE"
    RETIRED = "RETIRED"

class Device(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "devices"
    
    device_code: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(255))
    device_type: Mapped[DeviceType] = mapped_column(Enum(DeviceType))
    serial_number: Mapped[str] = mapped_column(String(100), nullable=True)
    manufacturer: Mapped[str] = mapped_column(String(100), nullable=True)
    model: Mapped[str] = mapped_column(String(100), nullable=True)
    firmware_version: Mapped[str] = mapped_column(String(50), nullable=True)
    status: Mapped[DeviceStatus] = mapped_column(Enum(DeviceStatus), default=DeviceStatus.UNKNOWN)
    metadata_json: Mapped[dict] = mapped_column(JSONB, nullable=True)

    # Relationships
    latest_state = relationship("DeviceLatestState", back_populates="device", uselist=False)
    assignments = relationship("DeviceAssignment", back_populates="device")
    vehicle_profile = relationship("VehicleProfile", back_populates="device", uselist=False)
    uav_profile = relationship("UavControllerProfile", back_populates="device", uselist=False)
