# API đổi tọa độ GPS thành địa chỉ dễ đọc. Endpoint chỉ chuyển tiếp tọa độ hợp lệ
# tới GeocodingService và trả 503 khi nhà cung cấp bên ngoài tạm thời không sẵn sàng.
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
    # Query tự kiểm tra biên tọa độ trước khi gọi nhà cung cấp. Endpoint đọc dữ liệu
    # nên áp dụng cùng quyền viewer với các màn hình giám sát.
    try:
        result = await geocoding_service.reverse(latitude, longitude)
    except GeocodingUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Dịch vụ chuyển đổi tọa độ sang địa chỉ tạm thời không khả dụng",
        ) from exc
    # Luôn trả lại tọa độ đầu vào cùng địa chỉ/provider để client ghép đúng request,
    # kể cả khi provider không tìm thấy một chuỗi địa chỉ cụ thể.
    return ReverseGeocodeResponse(
        latitude=latitude,
        longitude=longitude,
        formatted_address=result.get("formatted_address"),
        display_name=result.get("display_name"),
        provider=result.get("provider") or "unknown",
    )
