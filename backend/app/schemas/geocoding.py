# Hợp đồng trả địa chỉ: giữ cả formatted_address ngắn gọn và display_name từ nhà cung cấp,
# kèm provider để vận hành biết nguồn dữ liệu đang được sử dụng.
from typing import Optional

from app.schemas.common import BaseSchema


class ReverseGeocodeResponse(BaseSchema):
    # latitude/longitude phản chiếu đầu vào; formatted/display_name là hai mức địa chỉ.
    latitude: float
    longitude: float
    formatted_address: Optional[str] = None
    display_name: Optional[str] = None
    provider: str
