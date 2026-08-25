# Hợp đồng API thiết bị. DeviceBase là dữ liệu quản lý; DeviceResponse ghép thêm
# trạng thái realtime; MqttDeviceSightingResponse chỉ mô tả thiết bị lạ đã quan sát.
from datetime import datetime
from typing import Dict, Optional
import uuid

from pydantic import Field, field_validator

from app.domain.enums import DeviceStatus, DeviceType
from app.schemas.common import BaseSchema


class DeviceBase(BaseSchema):
    # device_code dùng trên topic; name/type và thông tin phần cứng phục vụ quản lý.
    # is_enabled quyết định nhận telemetry; metadata_json dành cho thuộc tính mở rộng.
    device_code: str = Field(min_length=1, max_length=50)
    name: str = Field(min_length=1, max_length=255)
    device_type: DeviceType
    serial_number: Optional[str] = Field(default=None, max_length=100)
    manufacturer: Optional[str] = Field(default=None, max_length=100)
    model: Optional[str] = Field(default=None, max_length=100)
    firmware_version: Optional[str] = Field(default=None, max_length=50)
    status: DeviceStatus = DeviceStatus.UNKNOWN
    is_enabled: bool = True
    metadata_json: Optional[Dict] = None

    @field_validator("device_code", "name")
    @classmethod
    def _strip_required_text(cls, value: str) -> str:
        # device_code/name dùng cho topic và giao diện nên loại khoảng trắng ngoài.
        normalized = value.strip()
        # Field min_length chạy trước trim; kiểm tra này chặn chuỗi chỉ có khoảng trắng.
        if not normalized:
            raise ValueError("Giá trị không được chỉ chứa khoảng trắng")
        return normalized


class DeviceCreate(DeviceBase):
    # Tạo mới yêu cầu đầy đủ các trường bắt buộc từ DeviceBase.
    pass


class DeviceUpdate(BaseSchema):
    # PATCH chỉ thay trường được gửi; validator ngăn payload rỗng hoặc toàn null.
    device_code: Optional[str] = Field(default=None, min_length=1, max_length=50)
    name: Optional[str] = Field(default=None, min_length=1, max_length=255)
    device_type: Optional[DeviceType] = None
    serial_number: Optional[str] = Field(default=None, max_length=100)
    manufacturer: Optional[str] = Field(default=None, max_length=100)
    model: Optional[str] = Field(default=None, max_length=100)
    firmware_version: Optional[str] = Field(default=None, max_length=50)
    is_enabled: Optional[bool] = None
    metadata_json: Optional[Dict] = None

    @field_validator("device_code", "name")
    @classmethod
    def _strip_optional_required_text(cls, value: Optional[str]) -> Optional[str]:
        # None giữ nghĩa trường không được thay đổi trong PATCH.
        if value is None:
            return None
        normalized = value.strip()
        # Khi client đã gửi device_code/name thì giá trị sau trim bắt buộc có nội dung.
        if not normalized:
            raise ValueError("Giá trị không được chỉ chứa khoảng trắng")
        return normalized


class DeviceResponse(DeviceBase):
    # current_* và battery_pct lấy từ latest state; null nghĩa là chưa có phép đo.
    # last_seen_at phản ánh kết nối, latest_measured_at phản ánh độ mới của GPS.
    id: uuid.UUID
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    # Trạng thái tổng hợp mới nhất để giao diện hiển thị nhanh.
    is_online: Optional[bool] = False
    current_latitude: Optional[float] = None
    current_longitude: Optional[float] = None
    current_altitude_m: Optional[float] = None
    current_speed_mps: Optional[float] = None
    current_heading_deg: Optional[float] = None
    battery_pct: Optional[int] = None
    last_seen_at: Optional[datetime] = None
    latest_measured_at: Optional[datetime] = None


class DeviceLatestStateResponse(BaseSchema):
    # Trạng thái tách riêng dùng khi endpoint không cần toàn bộ hồ sơ thiết bị.
    device_id: uuid.UUID
    last_seen_at: Optional[datetime] = None
    latest_measured_at: Optional[datetime] = None
    is_online: bool
    current_latitude: Optional[float] = None
    current_longitude: Optional[float] = None
    current_altitude_m: Optional[float] = None
    current_speed_mps: Optional[float] = None
    current_heading_deg: Optional[float] = None
    battery_pct: Optional[int] = None


class MqttDeviceSightingResponse(BaseSchema):
    # Chỉ là thống kê phát hiện, không đồng nghĩa thiết bị đã đăng ký hoặc cấp quyền.
    device_code: str
    first_seen_at: datetime
    last_seen_at: datetime
    message_count: int
    last_topic: str
