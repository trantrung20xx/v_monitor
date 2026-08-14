from pydantic import BaseModel
from typing import Optional
from datetime import datetime
import uuid

from app.schemas.common import BaseSchema
from app.domain.enums import AssignmentType, UsageStatus

class DeviceAssignmentResponse(BaseSchema):
    id: uuid.UUID
    device_id: uuid.UUID
    person_id: uuid.UUID
    assigned_at: datetime
    unassigned_at: Optional[datetime] = None
    assignment_type: AssignmentType
    notes: Optional[str] = None
    
    person_name: Optional[str] = None
    person_code: Optional[str] = None

class UsageSessionResponse(BaseSchema):
    id: uuid.UUID
    device_id: uuid.UUID
    person_id: Optional[uuid.UUID] = None
    started_at: datetime
    ended_at: Optional[datetime] = None
    
    distance_m: Optional[float] = None
    avg_speed_mps: Optional[float] = None
    max_speed_mps: Optional[float] = None
    moving_duration_s: Optional[int] = None
    stopped_duration_s: Optional[int] = None
    status: UsageStatus
    end_reason: Optional[str] = None
    
    person_name: Optional[str] = None
    person_code: Optional[str] = None
