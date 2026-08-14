from typing import Optional
from datetime import datetime
import uuid

from app.schemas.common import BaseSchema


class LocationSampleBase(BaseSchema):
    device_id: uuid.UUID
    measured_at: datetime
    latitude: float
    longitude: float
    altitude_m: Optional[float] = None
    speed_mps: Optional[float] = None
    heading_deg: Optional[float] = None
    accuracy_m: Optional[float] = None
    satellite_count: Optional[int] = None
    source: Optional[str] = None


class LocationSampleCreate(LocationSampleBase):
    pass


class LocationSampleResponse(LocationSampleBase):
    id: uuid.UUID
    received_at: datetime
    created_at: datetime


class DeviceEventResponse(BaseSchema):
    id: uuid.UUID
    device_id: uuid.UUID
    event_type: str
    occurred_at: datetime
    person_id: Optional[uuid.UUID] = None
    source: Optional[str] = None
