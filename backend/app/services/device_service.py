from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import func
from sqlalchemy.orm import selectinload
from typing import List
import uuid
from app.models.device import Device
from app.models.device_latest_state import DeviceLatestState
from app.models.device_assignment import DeviceAssignment
from app.models.usage_session import UsageSession
from app.schemas.device import DeviceCreate

class DeviceService:
    @staticmethod
    async def get_devices(db: AsyncSession, skip: int = 0, limit: int = 100) -> List[dict]:
        result = await db.execute(
            select(Device)
            .options(
                selectinload(Device.latest_state),
                selectinload(Device.assignments).selectinload(DeviceAssignment.person)
            )
            .offset(skip).limit(limit)
        )
        devices = result.scalars().all()
        return [DeviceService._format_device(d) for d in devices]

    @staticmethod
    async def get_device(db: AsyncSession, device_id: uuid.UUID) -> dict:
        result = await db.execute(
            select(Device)
            .options(
                selectinload(Device.latest_state),
                selectinload(Device.assignments).selectinload(DeviceAssignment.person)
            )
            .filter(Device.id == device_id)
        )
        device = result.scalars().first()
        if device:
            return DeviceService._format_device(device)
        return None # pyright: ignore[reportReturnType]

    @staticmethod
    def _format_device(device: Device) -> dict:
        data = {
            "id": str(device.id),
            "device_code": device.device_code,
            "name": device.name,
            "device_type": device.device_type,
            "serial_number": device.serial_number,
            "manufacturer": device.manufacturer,
            "model": device.model,
            "firmware_version": device.firmware_version,
            "status": device.status,
            "metadata_json": device.metadata_json,
            "created_at": device.created_at.isoformat(),
            "updated_at": device.updated_at.isoformat(),
        }
        
        # Lấy person hiện tại nếu có
        current_assignment = next((a for a in device.assignments if a.unassigned_at is None), None)
        if current_assignment and current_assignment.person:
            data["current_person_name"] = current_assignment.person.full_name

        if device.latest_state:
            data.update({
                "is_online": device.latest_state.is_online,
                "current_latitude": device.latest_state.current_latitude,
                "current_longitude": device.latest_state.current_longitude,
                "current_altitude_m": getattr(device.latest_state, "current_altitude_m", None),
                "current_speed_mps": device.latest_state.current_speed_mps,
                "current_heading_deg": device.latest_state.current_heading_deg,
                "uav_battery_pct": device.latest_state.uav_battery_pct,
                "controller_battery_pct": device.latest_state.controller_battery_pct,
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

    @staticmethod
    async def get_device_assignments(db: AsyncSession, device_id: uuid.UUID, limit: int = 50) -> List[DeviceAssignment]:
        result = await db.execute(
            select(DeviceAssignment)
            .options(selectinload(DeviceAssignment.person))
            .filter(DeviceAssignment.device_id == device_id)
            .order_by(DeviceAssignment.assigned_at.desc())
            .limit(limit)
        )
        return list(result.scalars().all())

    @staticmethod
    async def get_device_usages(db: AsyncSession, device_id: uuid.UUID, limit: int = 50) -> List[UsageSession]:
        result = await db.execute(
            select(UsageSession)
            .options(
                selectinload(UsageSession.person),
                selectinload(UsageSession.user),
            )
            .filter(UsageSession.device_id == device_id)
            .order_by(UsageSession.started_at.desc())
            .limit(limit)
        )
        return list(result.scalars().all())

    @staticmethod
    async def get_latest_device_usages(db: AsyncSession, limit_per_device: int = 1) -> List[UsageSession]:
        usage_rank = func.row_number().over(
            partition_by=UsageSession.device_id,
            order_by=UsageSession.started_at.desc(),
        ).label("usage_rank")

        ranked_usages = select(
            UsageSession.id.label("usage_id"),
            usage_rank,
        ).subquery()

        result = await db.execute(
            select(UsageSession)
            .join(ranked_usages, UsageSession.id == ranked_usages.c.usage_id)
            .options(
                selectinload(UsageSession.person),
                selectinload(UsageSession.user),
            )
            .filter(ranked_usages.c.usage_rank <= max(limit_per_device, 1))
            .order_by(UsageSession.started_at.desc())
        )
        return list(result.scalars().all())

    @staticmethod
    def format_usage_session(usage: UsageSession) -> dict:
        person = usage.person or usage.user
        return {
            "id": usage.id,
            "device_id": usage.device_id,
            "person_id": usage.person_id,
            "started_at": usage.started_at,
            "ended_at": usage.ended_at,
            "distance_m": usage.distance_m,
            "avg_speed_mps": usage.avg_speed_mps,
            "max_speed_mps": usage.max_speed_mps,
            "moving_duration_s": usage.moving_duration_s,
            "stopped_duration_s": usage.stopped_duration_s,
            "status": usage.status,
            "end_reason": usage.end_reason,
            "person_name": person.full_name if person else None,
            "person_code": person.person_code if person else None,
        }
