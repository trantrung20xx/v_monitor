from pydantic import BaseModel
from typing import Optional, Dict
from datetime import datetime
import uuid

from app.schemas.common import BaseSchema


class PersonBase(BaseSchema):
    person_code: str                                      # Mã định danh người sử dụng
    full_name: str                                        # Họ và tên
    phone: Optional[str] = None                           # Số điện thoại
    email: Optional[str] = None                           # Địa chỉ email
    department: Optional[str] = None                      # Phòng ban
    role: Optional[str] = None                            # Vai trò/chức vụ
    status: str = "ACTIVE"                                # Trạng thái người sử dụng
    metadata_json: Optional[Dict] = None                  # Thông tin mở rộng dạng key-value


class PersonCreate(PersonBase):
    pass                                                   # Schema tạo người sử dụng


class PersonResponse(PersonBase):
    id: uuid.UUID                                          # ID duy nhất trong database
    created_at: datetime                                   # Thời điểm tạo bản ghi
    updated_at: datetime                                   # Thời điểm cập nhật bản ghi
