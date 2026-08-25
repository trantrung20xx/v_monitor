import uuid
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.auth_dependencies import require_admin_if_enabled, require_viewer_if_enabled
from app.core.config import settings
from app.core.database import get_db
from app.schemas.device import (
    DeviceCreate,
    DeviceResponse,
    DeviceUpdate,
    MqttDeviceSightingResponse,
)
from app.services.device_service import DeviceService
from app.services.realtime_service import realtime_service


router = APIRouter()


@router.get(
    "/mqtt-sightings",
    response_model=List[MqttDeviceSightingResponse],
)
async def read_mqtt_sightings(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=5000),
    db: AsyncSession = Depends(get_db),
    _current_user=Depends(require_admin_if_enabled),
):
    return await DeviceService.get_mqtt_sightings(db, skip=skip, limit=limit)


@router.get("/", response_model=List[DeviceResponse])
async def read_devices(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1),
    db: AsyncSession = Depends(get_db),
    _current_user=Depends(require_viewer_if_enabled),
):
    if limit > settings.device_list_max_limit:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"limit không được vượt quá {settings.device_list_max_limit}",
        )
    return await DeviceService.get_devices(db, skip=skip, limit=limit)


@router.post("/", response_model=DeviceResponse)
async def create_device(
    device: DeviceCreate,
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_admin_if_enabled),
):
    try:
        return await DeviceService.create_device(
            db,
            device,
            actor_user_id=current_user.id if current_user else None,
        )
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Mã thiết bị đã tồn tại",
        )


@router.get("/{device_id}", response_model=DeviceResponse)
async def read_device(
    device_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _current_user=Depends(require_viewer_if_enabled),
):
    device = await DeviceService.get_device(db, device_id)
    if device is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy thiết bị")
    return device


@router.patch("/{device_id}", response_model=DeviceResponse)
async def update_device(
    device_id: uuid.UUID,
    device: DeviceUpdate,
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_admin_if_enabled),
):
    try:
        updated = await DeviceService.update_device(
            db,
            device_id,
            device,
            actor_user_id=current_user.id if current_user else None,
        )
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Mã thiết bị đã tồn tại",
        ) from exc
    if updated is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy thiết bị")
    await realtime_service.broadcast_telemetry(
        {"type": "DEVICE_UPDATE", "device": updated}
    )
    return updated
