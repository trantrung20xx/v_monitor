from pydantic import BaseModel
from typing import Optional, Dict
from datetime import datetime
import uuid
from app.schemas.common import BaseSchema

class PersonBase(BaseSchema):
    person_code: str
    full_name: str
    phone: Optional[str] = None
    email: Optional[str] = None
    department: Optional[str] = None
    role: Optional[str] = None
    status: str = "ACTIVE"
    metadata_json: Optional[Dict] = None

class PersonCreate(PersonBase):
    pass

class PersonResponse(PersonBase):
    id: uuid.UUID
    created_at: datetime
    updated_at: datetime
