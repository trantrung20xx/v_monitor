from pydantic import BaseModel
from typing import Optional, Dict
from datetime import datetime
import uuid
from app.schemas.common import BaseSchema
from app.domain.enums import DeviceType, DeviceStatus

class DeviceBase(BaseSchema):
    device_code: str
    name: str
    device_type: DeviceType
    serial_number: Optional[str] = None
    manufacturer: Optional[str] = None
    model: Optional[str] = None
    firmware_version: Optional[str] = None
    status: DeviceStatus = DeviceStatus.UNKNOWN
    metadata_json: Optional[Dict] = None

class DeviceCreate(DeviceBase):
    pass

class DeviceResponse(DeviceBase):
    id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    
    # Latest state fields
    is_online: Optional[bool] = False
    current_latitude: Optional[float] = None
    current_longitude: Optional[float] = None
    current_speed_mps: Optional[float] = None
    current_heading_deg: Optional[float] = None
    controller_battery_pct: Optional[int] = None
    uav_battery_pct: Optional[int] = None
    last_seen_at: Optional[datetime] = None
    
class DeviceLatestStateResponse(BaseSchema):
    device_id: uuid.UUID
    last_seen_at: datetime
    is_online: bool
    current_latitude: Optional[float] = None
    current_longitude: Optional[float] = None
    current_speed_mps: Optional[float] = None
    current_heading_deg: Optional[float] = None
    controller_battery_pct: Optional[int] = None
    uav_battery_pct: Optional[int] = None
