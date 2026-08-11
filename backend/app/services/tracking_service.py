from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from typing import List
import uuid
from datetime import datetime, timezone
from app.models.location_sample import LocationSample
from app.models.device_latest_state import DeviceLatestState
from app.schemas.tracking import LocationSampleCreate

class TrackingService:
    @staticmethod
    async def get_location_history(db: AsyncSession, device_id: uuid.UUID, limit: int = 100) -> List[LocationSample]:
        result = await db.execute(
            select(LocationSample)
            .filter(LocationSample.device_id == device_id)
            .order_by(LocationSample.measured_at.desc())
            .limit(limit)
        )
        return result.scalars().all()

    @staticmethod
    async def add_location(db: AsyncSession, location_in: LocationSampleCreate) -> LocationSample:
        # Create WKT point for PostGIS
        point = f"SRID=4326;POINT({location_in.longitude} {location_in.latitude})"
        
        sample = LocationSample(
            **location_in.model_dump(exclude={'latitude', 'longitude', 'altitude_m', 'speed_mps', 'heading_deg', 'accuracy_m', 'satellite_count', 'source'}),
            latitude=location_in.latitude,
            longitude=location_in.longitude,
            location=point,
            altitude_m=location_in.altitude_m,
            speed_mps=location_in.speed_mps,
            heading_deg=location_in.heading_deg,
            accuracy_m=location_in.accuracy_m,
            satellite_count=location_in.satellite_count,
            source=location_in.source,
            received_at=datetime.now(timezone.utc)
        )
        db.add(sample)
        
        # Update latest state
        latest = await db.execute(select(DeviceLatestState).filter(DeviceLatestState.device_id == location_in.device_id))
        latest = latest.scalars().first()
        if latest:
            latest.current_latitude = location_in.latitude
            latest.current_longitude = location_in.longitude
            latest.current_speed_mps = location_in.speed_mps
            latest.current_heading_deg = location_in.heading_deg
            latest.last_seen_at = location_in.measured_at.replace(tzinfo=None) if location_in.measured_at else None
            latest.is_online = True
            latest.updated_at = datetime.utcnow()
            
        await db.commit()
        await db.refresh(sample)
        return sample
