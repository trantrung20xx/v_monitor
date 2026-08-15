from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
import uuid

from app.core.database import get_db
from app.schemas.device import DeviceResponse, DeviceCreate
from app.services.device_service import DeviceService

router = APIRouter()

@router.get("/", response_model=List[DeviceResponse])
async def read_devices(skip: int = 0, limit: int = 100, db: AsyncSession = Depends(get_db)):
    return await DeviceService.get_devices(db, skip=skip, limit=limit)

@router.post("/", response_model=DeviceResponse)
async def create_device(device: DeviceCreate, db: AsyncSession = Depends(get_db)):
    return await DeviceService.create_device(db, device)

@router.get("/{device_id}", response_model=DeviceResponse)
async def read_device(device_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    device = await DeviceService.get_device(db, device_id)
    if device is None:
        raise HTTPException(status_code=404, detail="Device not found")
    return device
