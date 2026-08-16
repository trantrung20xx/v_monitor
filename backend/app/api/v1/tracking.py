from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from datetime import datetime
import uuid

from app.core.database import get_db
from app.schemas.tracking import (
    DeviceEventResponse,
    LocationSampleResponse,
    LocationSampleCreate,
    LocationHistoryResponse,
)
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
    """
    Lấy danh sách lịch sử vị trí gần đây nhất (giới hạn theo limit, mặc định 100).
    """
    return await TrackingService.get_location_history(db, device_id, limit)

@router.get("/{device_id}/history/range", response_model=LocationHistoryResponse)
async def get_history_range(
    device_id: uuid.UUID,
    from_time: datetime = Query(..., description="Thời điểm bắt đầu (ISO 8601, e.g. 2026-08-16T08:30:00+07:00)", alias="from"),
    to_time: datetime = Query(..., description="Thời điểm kết thúc (ISO 8601, e.g. 2026-08-16T12:45:00+07:00)", alias="to"),
    max_samples: Optional[int] = Query(None, ge=1, le=100000, description="Giới hạn số mẫu tối đa"),
    db: AsyncSession = Depends(get_db),
):
    """
    Truy xuất toàn bộ dữ liệu vị trí GPS của thiết bị trong khoảng thời gian [from, to].
    Sắp xếp chuẩn theo thứ tự đo đạc measured_at tăng dần.
    """
    if from_time >= to_time:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Thời điểm bắt đầu ('from') phải nhỏ hơn thời điểm kết thúc ('to').",
        )

    # Kiểm tra thiết bị có tồn tại không
    device = await DeviceService.get_device(db, device_id)
    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Không tìm thấy thiết bị với ID '{device_id}'",
        )

    samples, total_count, truncated = await TrackingService.get_location_history_range(
        db=db,
        device_id=device_id,
        from_time=from_time,
        to_time=to_time,
        max_samples=max_samples,
    )

    return LocationHistoryResponse(
        device_id=device_id,
        from_time=from_time,
        to_time=to_time,
        samples=[LocationSampleResponse.model_validate(s) for s in samples],
        total_count=total_count,
        truncated=truncated,
    )

@router.get("/{device_id}/events", response_model=List[DeviceEventResponse])
async def get_events(device_id: uuid.UUID, limit: int = 100, db: AsyncSession = Depends(get_db)):
    events = await TrackingService.get_device_events(db, device_id, limit)
    return [
        {
            "id": event.id,
            "device_id": event.device_id,
            "event_type": event.event_type,
            "occurred_at": event.occurred_at,
            "source": event.metadata_.get("source") if event.metadata_ else None,
        }
        for event in events
    ]
