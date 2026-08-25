# Bảng danh mục thiết bị đã được doanh nghiệp chấp nhận quản lý.
# device_code là định danh MQTT; is_enabled là quyền nhận dữ liệu, độc lập với online/offline.
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import Boolean, CheckConstraint, Enum, String, true
from sqlalchemy.dialects.postgresql import JSONB
from app.domain.enums import DeviceStatus, DeviceType
from app.models.base import Base, UUIDMixin, TimestampMixin


class Device(Base, UUIDMixin, TimestampMixin):
    # `devices` là danh mục được quản trị viên phê duyệt. Sự xuất hiện trên MQTT
    # không tự tạo bản ghi tại đây, nhờ đó dữ liệu lạ không trở thành thiết bị thật.
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

    # Trạng thái nghiệp vụ do quản trị quản lý, không dùng thay cho is_online được
    # suy ra từ telemetry gần nhất trong DeviceLatestState.
    status: Mapped[DeviceStatus] = mapped_column(Enum(DeviceStatus), default=DeviceStatus.UNKNOWN)

    # Quyền nhận và xử lý telemetry, tách biệt với trạng thái online/offline.
    is_enabled: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        server_default=true(),
        nullable=False,
    )

    # Thông tin mở rộng không thuộc schema cốt lõi; null nghĩa là chưa khai báo.
    metadata_json: Mapped[dict] = mapped_column(JSONB, nullable=True)

    # Các quan hệ dữ liệu

    # Trạng thái mới nhất quan hệ một-một; `selectinload` dùng tại service để tránh
    # truy vấn riêng cho từng thiết bị khi dựng danh sách dashboard.
    latest_state = relationship("DeviceLatestState", back_populates="device", uselist=False)

    # Constraint ở database bảo vệ cả dữ liệu đi vào ngoài API/Pydantic: mã và tên
    # không rỗng, không chứa khoảng trắng thừa ở hai đầu.
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
