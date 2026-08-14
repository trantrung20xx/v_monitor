from typing import Optional

from app.schemas.common import BaseSchema


class ReverseGeocodeResponse(BaseSchema):
    latitude: float
    longitude: float
    formatted_address: Optional[str] = None
    display_name: Optional[str] = None
    provider: str
