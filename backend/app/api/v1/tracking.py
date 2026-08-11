from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
import uuid

from app.core.database import get_db
from app.schemas.tracking import LocationSampleResponse, LocationSampleCreate
from app.services.tracking_service import TrackingService
from app.services.device_service import DeviceService
from app.services.realtime_service import realtime_service
from app.schemas.device import DeviceResponse

router = APIRouter()

@router.post("/", response_model=LocationSampleResponse)
async def add_location(location: LocationSampleCreate, db: AsyncSession = Depends(get_db)):
    result = await TrackingService.add_location(db, location)
    
    # Lấy device mới nhất và broadcast
    device = await DeviceService.get_device(db, location.device_id)
    if device:
        await realtime_service.broadcast_telemetry({
            "type": "DEVICE_UPDATE",
            "device": DeviceResponse.model_validate(device).model_dump(mode='json')
        })
        
    return result

@router.get("/{device_id}/history", response_model=List[LocationSampleResponse])
async def get_history(device_id: uuid.UUID, limit: int = 100, db: AsyncSession = Depends(get_db)):
    return await TrackingService.get_location_history(db, device_id, limit)
