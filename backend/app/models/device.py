from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import CheckConstraint, Enum, String
from sqlalchemy.dialects.postgresql import JSONB
from app.domain.enums import DeviceStatus, DeviceType
from app.models.base import Base, UUIDMixin, TimestampMixin


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

    # Các quan hệ dữ liệu

    # Trạng thái mới nhất của thiết bị
    latest_state = relationship("DeviceLatestState", back_populates="device", uselist=False)

    __table_args__ = (
        CheckConstraint(
            "length(btrim(device_code)) >= 1",
            name="ck_devices_code_not_blank",
        ),
        CheckConstraint(
            "length(btrim(name)) >= 1",
            name="ck_devices_name_not_blank",
        ),
        CheckConstraint(
            "device_code = btrim(device_code)",
            name="ck_devices_code_trimmed",
        ),
        CheckConstraint(
            "name = btrim(name)",
            name="ck_devices_name_trimmed",
        ),
    )
