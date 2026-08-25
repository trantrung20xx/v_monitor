from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.api.auth_dependencies import require_viewer_if_enabled
from app.schemas.geocoding import ReverseGeocodeResponse
from app.services.geocoding_service import (
    GeocodingUnavailableError,
    geocoding_service,
)

router = APIRouter()


@router.get("/reverse", response_model=ReverseGeocodeResponse)
async def reverse_geocode(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    _current_user=Depends(require_viewer_if_enabled),
):
    try:
        result = await geocoding_service.reverse(latitude, longitude)
    except GeocodingUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Dịch vụ chuyển đổi tọa độ sang địa chỉ tạm thời không khả dụng",
        ) from exc
    return ReverseGeocodeResponse(
        latitude=latitude,
        longitude=longitude,
        formatted_address=result.get("formatted_address"),
        display_name=result.get("display_name"),
        provider=result.get("provider") or "unknown",
    )
