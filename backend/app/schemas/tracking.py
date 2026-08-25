# Hợp đồng GPS và lịch sử hành trình. Các giới hạn tọa độ/tốc độ/hướng loại dữ liệu sai
# trước khi ghi; truncated báo frontend rằng kết quả đã chạm giới hạn số mẫu.
from datetime import datetime
from typing import List, Optional
import uuid

from pydantic import ConfigDict, Field

from app.schemas.common import BaseSchema


class LocationSampleBase(BaseSchema):
    # measured_at do thiết bị cung cấp; các đơn vị chuẩn là mét, m/s và độ [0, 360).
    device_id: uuid.UUID
    measured_at: datetime
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    altitude_m: Optional[float] = None
    speed_mps: Optional[float] = Field(default=None, ge=0)
    heading_deg: Optional[float] = Field(default=None, ge=0, lt=360)
    accuracy_m: Optional[float] = Field(default=None, ge=0)
    satellite_count: Optional[int] = Field(default=None, ge=0)
    source: Optional[str] = Field(default=None, max_length=100)


class LocationSampleCreate(LocationSampleBase):
    # Từ chối trường không khai báo để thiết bị gửi sai tên thuộc tính nhận lỗi
    # 422 rõ ràng, tránh tình trạng payload được chấp nhận nhưng dữ liệu bị bỏ qua.
    model_config = ConfigDict(from_attributes=True, extra="forbid")

    # Phần trăm pin thuộc về chính thiết bị gửi mẫu vị trí. Cùng một trường được
    # sử dụng cho ô tô, tay điều khiển UAV và các loại thiết bị khác để API không
    # gắn dữ liệu pin với một loại phương tiện cụ thể.
    battery_pct: Optional[int] = Field(default=None, ge=0, le=100)


class LocationSampleResponse(LocationSampleBase):
    # Bổ sung id và thời điểm server nhận/tạo để frontend đánh giá độ trễ dữ liệu.
    id: uuid.UUID
    received_at: datetime
    created_at: datetime


class LocationHistoryResponse(BaseSchema):
    # from/to là khoảng truy vấn thực tế; total_count và truncated mô tả tính đầy đủ kết quả.
    device_id: uuid.UUID
    from_time: datetime
    to_time: datetime
    samples: List[LocationSampleResponse]
    total_count: int
    truncated: bool = False


class DeviceEventResponse(BaseSchema):
    # Sự kiện chuẩn hóa để timeline hiển thị thời gian, nguồn và mô tả dễ hiểu.
    id: uuid.UUID
    device_id: uuid.UUID
    event_type: str
    occurred_at: datetime
    source: Optional[str] = None
    description: Optional[str] = None
