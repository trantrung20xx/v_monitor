# Schema nền dùng chung cho các response được tạo từ SQLAlchemy object.
from pydantic import BaseModel, ConfigDict


class BaseSchema(BaseModel):
    # from_attributes cho phép response model đọc trực tiếp thuộc tính ORM sau khi service trả.
    model_config = ConfigDict(from_attributes=True)
