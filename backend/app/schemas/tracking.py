from pydantic import BaseModel
from typing import Optional
from datetime import datetime
import uuid

from app.schemas.common import BaseSchema


class LocationSampleBase(BaseSchema):
    device_id: uuid.UUID                                  # ID thiết bị
    measured_at: datetime                                 # Thời điểm thiết bị đo dữ liệu
    latitude: float                                       # Vĩ độ GPS
    longitude: float                                      # Kinh độ GPS
    altitude_m: Optional[float] = None                    # Độ cao GPS (m)
    speed_mps: Optional[float] = None                     # Vận tốc (m/s)
    heading_deg: Optional[float] = None                   # Hướng di chuyển (độ)
    accuracy_m: Optional[float] = None                    # Độ chính xác vị trí GPS (m)
    satellite_count: Optional[int] = None                 # Số lượng vệ tinh GPS
    source: Optional[str] = None                          # Nguồn dữ liệu vị trí


class LocationSampleCreate(LocationSampleBase):
    pass                                                   # Schema tạo bản ghi vị trí


class LocationSampleResponse(LocationSampleBase):
    id: uuid.UUID                                          # ID duy nhất của bản ghi
    received_at: datetime                                  # Thời điểm server nhận dữ liệu
    created_at: datetime                                   # Thời điểm lưu bản ghi vào database
