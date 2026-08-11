from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload
from typing import List
import uuid
from app.models.device import Device
from app.models.device_latest_state import DeviceLatestState
from app.schemas.device import DeviceCreate

class DeviceService:
    @staticmethod
    async def get_devices(db: AsyncSession, skip: int = 0, limit: int = 100) -> List[dict]:
        result = await db.execute(select(Device).options(selectinload(Device.latest_state)).offset(skip).limit(limit))
        devices = result.scalars().all()
        return [DeviceService._format_device(d) for d in devices]

    @staticmethod
    async def get_device(db: AsyncSession, device_id: uuid.UUID) -> dict:
        result = await db.execute(select(Device).options(selectinload(Device.latest_state)).filter(Device.id == device_id))
        device = result.scalars().first()
        if device:
            return DeviceService._format_device(device)
        return None

    @staticmethod
    def _format_device(device: Device) -> dict:
        data = {
            "id": str(device.id),
            "device_code": device.device_code,
            "name": device.name,
            "device_type": device.device_type,
            "status": device.status,
            "created_at": device.created_at.isoformat(),
            "updated_at": device.updated_at.isoformat(),
        }
        if device.latest_state:
            data.update({
                "is_online": device.latest_state.is_online,
                "current_latitude": device.latest_state.current_latitude,
                "current_longitude": device.latest_state.current_longitude,
                "current_speed_mps": device.latest_state.current_speed_mps,
                "current_heading_deg": device.latest_state.current_heading_deg,
                "controller_battery_pct": device.latest_state.controller_battery_pct,
                "uav_battery_pct": device.latest_state.uav_battery_pct,
                "last_seen_at": device.latest_state.last_seen_at.isoformat() if device.latest_state.last_seen_at else None
            })
        return data

    @staticmethod
    async def create_device(db: AsyncSession, device_in: DeviceCreate) -> dict:
        device = Device(**device_in.model_dump())
        db.add(device)
        await db.commit()
        await db.refresh(device)
        
        # Initialize latest state
        latest_state = DeviceLatestState(device_id=device.id)
        db.add(latest_state)
        await db.commit()
        
        device.latest_state = latest_state
        return DeviceService._format_device(device)
