from pydantic import BaseModel, ConfigDict
from typing import Optional, List, Any
from datetime import datetime
import uuid

class BaseSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True)

class PaginatedResponse(BaseSchema):
    items: List[Any]
    total: int
    page: int
    size: int
