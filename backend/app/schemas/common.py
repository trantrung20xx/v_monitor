from pydantic import BaseModel, ConfigDict
from typing import Optional, List, Any
from datetime import datetime
import uuid


class BaseSchema(BaseModel):
    model_config = ConfigDict(from_attributes=True)       # Cho phép tạo schema từ object ORM


class PaginatedResponse(BaseSchema):
    items: List[Any]                                       # Danh sách dữ liệu của trang hiện tại
    total: int                                             # Tổng số bản ghi
    page: int                                              # Số trang hiện tại
    size: int                                              # Số bản ghi mỗi trang
