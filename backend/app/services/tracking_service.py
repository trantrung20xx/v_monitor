from datetime import datetime, timezone
from typing import List, Tuple
import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.device import Device
from app.models.device_event import DeviceEvent
from app.models.device_latest_state import DeviceLatestState
from app.models.location_sample import LocationSample
from app.schemas.tracking import LocationSampleCreate


class DeviceNotFoundError(ValueError):
    pass


def _utc_datetime(value: datetime) -> datetime:
    """Chuẩn hóa thời gian thiết bị thành UTC có múi giờ."""
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


class TrackingService:
    @staticmethod
    async def get_location_history(
        db: AsyncSession,
        device_id: uuid.UUID,
        limit: int = 100,
    ) -> List[LocationSample]:
        result = await db.execute(
            select(LocationSample)
            .where(LocationSample.device_id == device_id)
            .order_by(LocationSample.measured_at.desc(), LocationSample.id.desc())
            .limit(limit)
        )
        return list(result.scalars().all())

    @staticmethod
    async def get_location_history_range(
        db: AsyncSession,
        device_id: uuid.UUID,
        from_time: datetime,
        to_time: datetime,
        max_samples: int | None = None,
    ) -> Tuple[List[LocationSample], int, bool]:
        limit = max_samples or settings.tracking_max_history_samples
        filters = (
            LocationSample.device_id == device_id,
            LocationSample.measured_at >= from_time,
            LocationSample.measured_at <= to_time,
        )
        count_result = await db.execute(
            select(func.count(LocationSample.id)).where(*filters)
        )
        total_count = count_result.scalar_one() or 0
        result = await db.execute(
            select(LocationSample)
            .where(*filters)
            .order_by(LocationSample.measured_at.asc(), LocationSample.id.asc())
            .limit(limit)
        )
        samples = list(result.scalars().all())
        return samples, total_count, total_count > len(samples)

    @staticmethod
    async def get_device_events(
        db: AsyncSession,
        device_id: uuid.UUID,
        limit: int = 100,
        event_type: str | None = None,
    ) -> List[DeviceEvent]:
        query = select(DeviceEvent).where(DeviceEvent.device_id == device_id)
        if event_type:
            query = query.where(DeviceEvent.event_type == event_type.upper())
        result = await db.execute(
            query.order_by(DeviceEvent.occurred_at.desc(), DeviceEvent.id.desc())
            .limit(limit)
        )
        return list(result.scalars().all())

    @staticmethod
    async def add_location(
        db: AsyncSession,
        location_in: LocationSampleCreate,
        source_message_id: uuid.UUID | None = None,
    ) -> Tuple[LocationSample, List[DeviceEvent]]:
        """Lưu mẫu, sự kiện và trạng thái mới nhất trong đúng một giao dịch."""
        received_at = datetime.now(timezone.utc)
        measured_at = _utc_datetime(location_in.measured_at)
        point = f"SRID=4326;POINT({location_in.longitude} {location_in.latitude})"

        # Khóa một dòng theo thiết bị để các worker MQTT không ghi đè lẫn nhau.
        latest_result = await db.execute(
            select(DeviceLatestState)
            .where(DeviceLatestState.device_id == location_in.device_id)
            .with_for_update()
        )
        latest = latest_result.scalar_one_or_none()
        if latest is None:
            if await db.get(Device, location_in.device_id) is None:
                raise DeviceNotFoundError("Không tìm thấy thiết bị")
            latest = DeviceLatestState(device_id=location_in.device_id)
            db.add(latest)
            await db.flush()

        # location_samples chỉ lưu lịch sử tọa độ. Mức pin là trạng thái tức thời
        # của thiết bị nên được tách khỏi mẫu GPS và chỉ cập nhật ở latest_state.
        sample_data = location_in.model_dump(exclude={"battery_pct"})
        sample_data["measured_at"] = measured_at
        sample = LocationSample(
            **sample_data,
            location=point,
            source_message_id=source_message_id,
            received_at=received_at,
        )
        db.add(sample)
        await db.flush()

        generated_events: List[DeviceEvent] = []
        was_online = latest.is_online

        # Trạng thái kết nối dựa trên lúc server nhận gói, không dựa trên đồng hồ thiết bị.
        if not was_online:
            online_event = DeviceEvent(
                device_id=location_in.device_id,
                event_type="ONLINE",
                occurred_at=received_at,
                location=point,
                source=location_in.source,
                description="Thiết bị kết nối trực tuyến",
            )
            db.add(online_event)
            generated_events.append(online_event)

        latest.last_seen_at = received_at
        latest.is_online = True
        latest.updated_at = received_at

        # Gói đến trễ vẫn được lưu lịch sử nhưng không được ghi đè vị trí hiện tại.
        is_newest_sample = (
            latest.latest_measured_at is None
            or measured_at >= latest.latest_measured_at
        )
        if is_newest_sample:
            previous_speed = latest.current_speed_mps
            new_speed = location_in.speed_mps
            if new_speed is not None:
                if (previous_speed is None or previous_speed <= 0.5) and new_speed > 0.5:
                    speed_kmh = round(new_speed * 3.6, 1)
                    event = DeviceEvent(
                        device_id=location_in.device_id,
                        event_type="MOVEMENT_STARTED",
                        occurred_at=measured_at,
                        location=point,
                        source=location_in.source,
                        description=f"Bắt đầu di chuyển ({speed_kmh} km/h)",
                        metadata_={
                            "speed_mps": new_speed,
                            "heading_deg": location_in.heading_deg,
                        },
                    )
                    db.add(event)
                    generated_events.append(event)
                elif previous_speed is not None and previous_speed > 0.5 and new_speed <= 0.5:
                    event = DeviceEvent(
                        device_id=location_in.device_id,
                        event_type="MOVEMENT_STOPPED",
                        occurred_at=measured_at,
                        location=point,
                        source=location_in.source,
                        description="Thiết bị đã dừng lại",
                        metadata_={
                            "speed_mps": new_speed,
                        },
                    )
                    db.add(event)
                    generated_events.append(event)

            latest.current_latitude = location_in.latitude
            latest.current_longitude = location_in.longitude
            latest.current_altitude_m = location_in.altitude_m
            latest.current_speed_mps = location_in.speed_mps
            latest.current_heading_deg = location_in.heading_deg
            if location_in.battery_pct is not None:
                latest.battery_pct = location_in.battery_pct
            latest.latest_measured_at = measured_at
            latest.latest_sample_id = sample.id

        await db.commit()
        await db.refresh(sample)
        for event in generated_events:
            await db.refresh(event)
        return sample, generated_events
