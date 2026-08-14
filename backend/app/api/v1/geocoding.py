from fastapi import APIRouter, Query

from app.schemas.geocoding import ReverseGeocodeResponse
from app.services.geocoding_service import geocoding_service

router = APIRouter()


@router.get("/reverse", response_model=ReverseGeocodeResponse)
async def reverse_geocode(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
):
    result = await geocoding_service.reverse(latitude, longitude)
    return ReverseGeocodeResponse(
        latitude=latitude,
        longitude=longitude,
        formatted_address=result.get("formatted_address"),
        display_name=result.get("display_name"),
        provider="nominatim",
    )
