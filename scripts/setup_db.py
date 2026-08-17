import asyncio
import sys
import os

# Add backend to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'backend'))

from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy import select, func
from datetime import datetime, timezone, timedelta
import uuid

from app.core.config import settings
from app.models.base import Base
from app.models.device import Device, DeviceType, DeviceStatus
from app.models.device_latest_state import DeviceLatestState
from app.models.device_event import DeviceEvent

# Import all models here to ensure they are registered with Base.metadata
import app.models

async def setup_db():
    print(f"Connecting to database...")
    engine = create_async_engine(settings.database_url, echo=True)
    
    async with engine.begin() as conn:
        print("Creating tables...")
        await conn.run_sync(Base.metadata.create_all)
        print("Tables created successfully.")

    # Seed demo devices and events if empty
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as db:
        dev_count = await db.scalar(select(func.count(Device.id)))
        if dev_count == 0:
            print("Seeding initial devices...")
            demo_devices = [
                Device(
                    id=uuid.UUID("11111111-1111-1111-1111-111111111111"),
                    device_code="UAV-100",
                    name="Flycam giám sát 100",
                    device_type=DeviceType.UAV_CONTROLLER,
                    status=DeviceStatus.ONLINE,
                    manufacturer="DJI",
                    model="Matrice 300 RTK",
                ),
                Device(
                    id=uuid.UUID("22222222-2222-2222-2222-222222222222"),
                    device_code="CAR-01",
                    name="Xe tuần tra khu vực 1",
                    device_type=DeviceType.VEHICLE,
                    status=DeviceStatus.ONLINE,
                    manufacturer="Toyota",
                    model="Hilux Patrol",
                ),
            ]
            for d in demo_devices:
                db.add(d)
                db.add(
                    DeviceLatestState(
                        device_id=d.id,
                        is_online=True,
                        current_latitude=21.028511,
                        current_longitude=105.804817,
                        current_speed_mps=8.5,
                        current_heading_deg=45.0,
                        last_seen_at=datetime.now(timezone.utc),
                    )
                )
            await db.commit()

        # Seed sample events if empty
        event_count = await db.scalar(select(func.count(DeviceEvent.id)))
        if event_count == 0:
            print("Seeding initial sample events...")
            devices_res = await db.execute(select(Device))
            devices = devices_res.scalars().all()
            now = datetime.now(timezone.utc)

            for d in devices:
                sample_events = [
                    DeviceEvent(
                        device_id=d.id,
                        event_type="ONLINE",
                        occurred_at=now - timedelta(hours=2),
                        metadata_={"source": "system", "description": "Thiết bị kết nối trực tuyến"},
                    ),
                    DeviceEvent(
                        device_id=d.id,
                        event_type="MOVEMENT_STARTED",
                        occurred_at=now - timedelta(hours=1, minutes=45),
                        metadata_={"speed_mps": 10.2, "source": "gps", "description": "Bắt đầu di chuyển (36.7 km/h)"},
                    ),
                    DeviceEvent(
                        device_id=d.id,
                        event_type="GPS_RESTORED",
                        occurred_at=now - timedelta(hours=1, minutes=20),
                        metadata_={"satellite_count": 12, "source": "gps", "description": "Khôi phục tín hiệu GPS (12 vệ tinh)"},
                    ),
                    DeviceEvent(
                        device_id=d.id,
                        event_type="MOVEMENT_STOPPED",
                        occurred_at=now - timedelta(minutes=40),
                        metadata_={"speed_mps": 0.0, "source": "gps", "description": "Thiết bị đã dừng lại"},
                    ),
                    DeviceEvent(
                        device_id=d.id,
                        event_type="MOVEMENT_STARTED",
                        occurred_at=now - timedelta(minutes=15),
                        metadata_={"speed_mps": 8.5, "source": "gps", "description": "Tiếp tục di chuyển (30.6 km/h)"},
                    ),
                ]
                for ev in sample_events:
                    db.add(ev)
            await db.commit()
            print("Sample events seeded successfully.")

    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(setup_db())
