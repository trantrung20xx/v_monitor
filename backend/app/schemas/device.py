from pydantic import BaseModel
from typing import Optional, Dict
from datetime import datetime
import uuid

from app.schemas.common import BaseSchema
from app.domain.enums import DeviceType, DeviceStatus


class DeviceBase(BaseSchema):
    device_code: str                                       # Mã định danh thiết bị
    name: str                                              # Tên hiển thị thiết bị
    device_type: DeviceType                                # Loại thiết bị
    serial_number: Optional[str] = None                    # Số serial thiết bị
    manufacturer: Optional[str] = None                     # Nhà sản xuất
    model: Optional[str] = None                            # Model thiết bị
    firmware_version: Optional[str] = None                 # Phiên bản firmware
    status: DeviceStatus = DeviceStatus.UNKNOWN            # Trạng thái thiết bị
    metadata_json: Optional[Dict] = None                   # Thông tin mở rộng dạng key-value


class DeviceCreate(DeviceBase):
    pass                                                   # Schema tạo thiết bị


class DeviceResponse(DeviceBase):
    id: uuid.UUID                                          # ID duy nhất trong database
    created_at: Optional[datetime] = None                  # Thời điểm tạo bản ghi
    updated_at: Optional[datetime] = None                  # Thời điểm cập nhật bản ghi

    # Latest state
    is_online: Optional[bool] = False                      # Trạng thái online hiện tại
    current_latitude: Optional[float] = None               # Vĩ độ GPS hiện tại
    current_longitude: Optional[float] = None              # Kinh độ GPS hiện tại
    current_altitude_m: Optional[float] = None             # Độ cao GPS hiện tại (m)
    current_speed_mps: Optional[float] = None              # Vận tốc hiện tại (m/s)
    current_heading_deg: Optional[float] = None            # Hướng di chuyển hiện tại (độ)
    last_seen_at: Optional[datetime] = None                # Thời điểm nhận dữ liệu gần nhất
    uav_battery_pct: Optional[int] = None                  # Pin UAV (%)
    controller_battery_pct: Optional[int] = None           # Pin tay cầm (%)


class DeviceLatestStateResponse(BaseSchema):
    device_id: uuid.UUID                                   # ID thiết bị
    last_seen_at: datetime                                 # Thời điểm nhận dữ liệu gần nhất
    is_online: bool                                        # Trạng thái online hiện tại
    current_latitude: Optional[float] = None               # Vĩ độ GPS hiện tại
    current_longitude: Optional[float] = None              # Kinh độ GPS hiện tại
    current_altitude_m: Optional[float] = None             # Độ cao GPS hiện tại (m)
    current_speed_mps: Optional[float] = None              # Vận tốc hiện tại (m/s)
    current_heading_deg: Optional[float] = None            # Hướng di chuyển hiện tại (độ)
    uav_battery_pct: Optional[int] = None                  # Pin UAV (%)
    controller_battery_pct: Optional[int] = None           # Pin tay cầm (%)
