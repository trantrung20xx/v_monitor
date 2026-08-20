from datetime import datetime
from typing import List, Optional
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.auth_dependencies import require_admin_if_enabled, require_viewer_if_enabled
from app.core.database import get_db
from app.models.device import Device
from app.schemas.device import DeviceResponse
from app.schemas.tracking import (
    DeviceEventResponse,
    LocationHistoryResponse,
    LocationSampleCreate,
    LocationSampleResponse,
)
from app.services.device_service import DeviceService
from app.services.realtime_service import realtime_service
from app.services.tracking_service import DeviceNotFoundError, TrackingService


router = APIRouter()


def _event_payload(event) -> dict:
    metadata = event.metadata_ or {}
    return {
        "id": str(event.id),
        "device_id": str(event.device_id),
        "event_type": event.event_type,
        "occurred_at": event.occurred_at.isoformat() if event.occurred_at else None,
        "source": event.source or metadata.get("source"),
        "description": event.description or metadata.get("description"),
    }


@router.post("/", response_model=LocationSampleResponse)
async def add_location(
    location: LocationSampleCreate,
    db: AsyncSession = Depends(get_db),
    _current_user=Depends(require_admin_if_enabled),
):
    try:
        result, generated_events = await TrackingService.add_location(db, location)
    except DeviceNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc))

    device = await DeviceService.get_device(db, location.device_id)
    if device:
        await realtime_service.broadcast_telemetry(
            {
                "type": "DEVICE_UPDATE",
                "device": DeviceResponse.model_validate(device).model_dump(mode="json"),
            }
        )
    for event in generated_events:
        await realtime_service.broadcast_telemetry(
            {"type": "DEVICE_EVENT", "event": _event_payload(event)}
        )
    return result


@router.get("/{device_id}/history", response_model=List[LocationSampleResponse])
async def get_history(
    device_id: uuid.UUID,
    limit: int = Query(100, ge=1, le=100000),
    db: AsyncSession = Depends(get_db),
    _current_user=Depends(require_viewer_if_enabled),
):
    return await TrackingService.get_location_history(db, device_id, limit)


@router.get("/{device_id}/history/range", response_model=LocationHistoryResponse)
async def get_history_range(
    device_id: uuid.UUID,
    from_time: datetime = Query(..., alias="from"),
    to_time: datetime = Query(..., alias="to"),
    max_samples: Optional[int] = Query(None, ge=1, le=100000),
    db: AsyncSession = Depends(get_db),
    _current_user=Depends(require_viewer_if_enabled),
):
    if from_time >= to_time:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Thời điểm bắt đầu phải nhỏ hơn thời điểm kết thúc",
        )
    if await DeviceService.get_device(db, device_id) is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy thiết bị")

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
        samples=[LocationSampleResponse.model_validate(sample) for sample in samples],
        total_count=total_count,
        truncated=truncated,
    )


@router.get("/{device_id}/events", response_model=List[DeviceEventResponse])
async def get_events(
    device_id: str,
    limit: int = Query(100, ge=1, le=10000),
    event_type: Optional[str] = Query(None, max_length=50),
    db: AsyncSession = Depends(get_db),
    _current_user=Depends(require_viewer_if_enabled),
):
    try:
        resolved_uuid = uuid.UUID(device_id)
    except (ValueError, TypeError):
        result = await db.execute(
            select(Device.id).where(Device.device_code == device_id)
        )
        resolved_uuid = result.scalar_one_or_none()

    if not resolved_uuid:
        return []
    events = await TrackingService.get_device_events(
        db,
        resolved_uuid,
        limit,
        event_type=event_type,
    )
    return [_event_payload(event) for event in events]
