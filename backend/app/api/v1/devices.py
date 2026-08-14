from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
import uuid

from app.core.database import get_db
from app.schemas.device import DeviceResponse, DeviceCreate
from app.schemas.assignment import DeviceAssignmentResponse, UsageSessionResponse
from app.services.device_service import DeviceService

router = APIRouter()

@router.get("/", response_model=List[DeviceResponse])
async def read_devices(skip: int = 0, limit: int = 100, db: AsyncSession = Depends(get_db)):
    return await DeviceService.get_devices(db, skip=skip, limit=limit)

@router.post("/", response_model=DeviceResponse)
async def create_device(device: DeviceCreate, db: AsyncSession = Depends(get_db)):
    return await DeviceService.create_device(db, device)

@router.get("/usages/latest", response_model=List[UsageSessionResponse])
async def read_latest_device_usages(limit_per_device: int = 1, db: AsyncSession = Depends(get_db)):
    usages = await DeviceService.get_latest_device_usages(db, limit_per_device)
    return [DeviceService.format_usage_session(u) for u in usages]

@router.get("/{device_id}", response_model=DeviceResponse)
async def read_device(device_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    device = await DeviceService.get_device(db, device_id)
    if device is None:
        raise HTTPException(status_code=404, detail="Device not found")
    return device

@router.get("/{device_id}/assignments", response_model=List[DeviceAssignmentResponse])
async def read_device_assignments(device_id: uuid.UUID, limit: int = 50, db: AsyncSession = Depends(get_db)):
    assignments = await DeviceService.get_device_assignments(db, device_id, limit)
    result = []
    for a in assignments:
        a_dict = {
            "id": a.id,
            "device_id": a.device_id,
            "person_id": a.person_id,
            "assigned_at": a.assigned_at,
            "unassigned_at": a.unassigned_at,
            "assignment_type": a.assignment_type,
            "notes": a.notes,
            "person_name": a.person.full_name if a.person else None,
            "person_code": a.person.person_code if a.person else None,
        }
        result.append(a_dict)
    return result

@router.get("/{device_id}/usages", response_model=List[UsageSessionResponse])
async def read_device_usages(device_id: uuid.UUID, limit: int = 50, db: AsyncSession = Depends(get_db)):
    usages = await DeviceService.get_device_usages(db, device_id, limit)
    return [DeviceService.format_usage_session(u) for u in usages]
