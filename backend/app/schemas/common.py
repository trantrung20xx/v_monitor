# Schema nền dùng chung: đọc được SQLAlchemy object và chuẩn hóa cấu trúc phân trang.
from pydantic import BaseModel, ConfigDict
from typing import Optional, List, Any
from datetime import datetime
import uuid


class BaseSchema(BaseModel):
    # from_attributes cho phép response model đọc trực tiếp thuộc tính ORM sau khi service trả.
    model_config = ConfigDict(from_attributes=True)       # Cho phép tạo schema từ object ORM


class PaginatedResponse(BaseSchema):
    # Envelope phân trang dùng chung khi endpoint cần trả cả dữ liệu và thông tin trang.
    items: List[Any]                                       # Danh sách dữ liệu của trang hiện tại
    total: int                                             # Tổng số bản ghi
    page: int                                              # Số trang hiện tại
    size: int                                              # Số bản ghi mỗi trang
