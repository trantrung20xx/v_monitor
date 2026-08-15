from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import String, Enum
from sqlalchemy.dialects.postgresql import JSONB
from app.models.base import Base, UUIDMixin, TimestampMixin
import enum


# Loại thiết bị được quản lý trong hệ thống
class DeviceType(str, enum.Enum):
    UAV_CONTROLLER = "UAV_CONTROLLER"  # Tay cầm điều khiển UAV
    VEHICLE = "VEHICLE"                # Ô tô
    OTHER = "OTHER"                    # Loại thiết bị khác


# Trạng thái hiện tại của thiết bị
class DeviceStatus(str, enum.Enum):
    UNKNOWN = "UNKNOWN"                # Chưa xác định trạng thái
    OFFLINE = "OFFLINE"                # Thiết bị đang ngoại tuyến
    ONLINE = "ONLINE"                  # Thiết bị đang kết nối
    ACTIVE = "ACTIVE"                  # Thiết bị đang hoạt động
    INACTIVE = "INACTIVE"              # Thiết bị không hoạt động
    MAINTENANCE = "MAINTENANCE"        # Thiết bị đang bảo trì
    RETIRED = "RETIRED"                # Thiết bị đã ngừng sử dụng


class Device(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "devices"

    # Mã định danh của thiết bị trong hệ thống
    device_code: Mapped[str] = mapped_column(String(50), unique=True, index=True)

    # Tên hiển thị của thiết bị
    name: Mapped[str] = mapped_column(String(255))

    # Loại thiết bị
    device_type: Mapped[DeviceType] = mapped_column(Enum(DeviceType))

    # Số serial của thiết bị
    serial_number: Mapped[str] = mapped_column(String(100), nullable=True)

    # Nhà sản xuất thiết bị
    manufacturer: Mapped[str] = mapped_column(String(100), nullable=True)

    # Model của thiết bị
    model: Mapped[str] = mapped_column(String(100), nullable=True)

    # Phiên bản firmware hiện tại
    firmware_version: Mapped[str] = mapped_column(String(50), nullable=True)

    # Trạng thái hiện tại của thiết bị
    status: Mapped[DeviceStatus] = mapped_column(Enum(DeviceStatus), default=DeviceStatus.UNKNOWN)

    # Thông tin mở rộng của thiết bị dưới dạng JSON
    metadata_json: Mapped[dict] = mapped_column(JSONB, nullable=True)

    # Relationships

    # Trạng thái mới nhất của thiết bị
    latest_state = relationship("DeviceLatestState", back_populates="device", uselist=False)
