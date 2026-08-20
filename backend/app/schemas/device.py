from datetime import datetime
from typing import Dict, Optional
import uuid

from pydantic import Field, field_validator

from app.domain.enums import DeviceStatus, DeviceType
from app.schemas.common import BaseSchema


class DeviceBase(BaseSchema):
    device_code: str = Field(min_length=1, max_length=50)
    name: str = Field(min_length=1, max_length=255)
    device_type: DeviceType
    serial_number: Optional[str] = Field(default=None, max_length=100)
    manufacturer: Optional[str] = Field(default=None, max_length=100)
    model: Optional[str] = Field(default=None, max_length=100)
    firmware_version: Optional[str] = Field(default=None, max_length=50)
    status: DeviceStatus = DeviceStatus.UNKNOWN
    metadata_json: Optional[Dict] = None

    @field_validator("device_code", "name")
    @classmethod
    def _strip_required_text(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("Giá trị không được chỉ chứa khoảng trắng")
        return normalized


class DeviceCreate(DeviceBase):
    pass


class DeviceResponse(DeviceBase):
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
