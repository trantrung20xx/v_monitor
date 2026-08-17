from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from typing import List, Tuple
import uuid
from datetime import datetime, timezone
from app.models.location_sample import LocationSample
from app.models.device_latest_state import DeviceLatestState
from app.models.device_event import DeviceEvent
from app.schemas.tracking import LocationSampleCreate
from app.core.config import settings

# Lớp dịch vụ chuyên phụ trách các nghiệp vụ liên quan đến Theo dõi (Tracking) thiết bị.
# Xử lý logic ghi nhận vị trí mới và trích xuất lịch sử di chuyển.
class TrackingService:
    @staticmethod
    async def get_location_history(db: AsyncSession, device_id: uuid.UUID, limit: int = 100) -> List[LocationSample]:
        """
        Lấy danh sách lịch sử vị trí của một thiết bị.
        Sắp xếp theo thời gian giảm dần (mới nhất xếp trước) và giới hạn số lượng kết quả.
        """
        result = await db.execute(
            select(LocationSample)
            .filter(LocationSample.device_id == device_id)
            .order_by(LocationSample.measured_at.desc())
            .limit(limit)
        )
        return list(result.scalars().all())

    @staticmethod
    async def get_location_history_range(
        db: AsyncSession,
        device_id: uuid.UUID,
        from_time: datetime,
        to_time: datetime,
        max_samples: int | None = None
    ) -> Tuple[List[LocationSample], int, bool]:
        """
        Lấy toàn bộ lịch sử vị trí GPS của thiết bị trong khoảng [from_time, to_time].
        Sắp xếp tăng dần theo measured_at ASC, id ASC để đảm bảo thứ tự thời gian chính xác và ổn định tuyệt đối.
        Trả về: (samples, total_count, is_truncated)
        """
        limit = max_samples or settings.tracking_max_history_samples

        # Đếm tổng số bản ghi trong khoảng thời gian
        count_query = select(func.count(LocationSample.id)).filter(
            LocationSample.device_id == device_id,
            LocationSample.measured_at >= from_time,
            LocationSample.measured_at <= to_time
        )
        count_res = await db.execute(count_query)
        total_count = count_res.scalar_one_or_none() or 0

        # Lấy các mẫu GPS được sort tăng dần theo measured_at và id
        query = (
            select(LocationSample)
            .filter(
                LocationSample.device_id == device_id,
                LocationSample.measured_at >= from_time,
                LocationSample.measured_at <= to_time
            )
            .order_by(LocationSample.measured_at.asc(), LocationSample.id.asc())
            .limit(limit)
        )
        result = await db.execute(query)
        samples = list(result.scalars().all())

        is_truncated = total_count > len(samples)
        return samples, total_count, is_truncated

    @staticmethod
    async def get_device_events(
        db: AsyncSession,
        device_id: uuid.UUID,
        limit: int = 100,
        event_type: str | None = None,
    ) -> List[DeviceEvent]:
        query = select(DeviceEvent).filter(DeviceEvent.device_id == device_id)
        if event_type:
            query = query.filter(DeviceEvent.event_type == event_type.upper())
        query = query.order_by(DeviceEvent.occurred_at.desc()).limit(limit)
        result = await db.execute(query)
        return list(result.scalars().all())

    @staticmethod
    async def add_location(
        db: AsyncSession,
        location_in: LocationSampleCreate,
    ) -> Tuple[LocationSample, List[DeviceEvent]]:
        """
        Ghi nhận một tọa độ mới vào CSDL, tự động phát hiện sự kiện thay đổi trạng thái,
        cập nhật trạng thái mới nhất của thiết bị và lưu đồng thời các bảng.
        """
        # Tạo chuỗi định dạng WKT (Well-Known Text) dành riêng cho cơ sở dữ liệu không gian PostGIS (SRID=4326)
        point = f"SRID=4326;POINT({location_in.longitude} {location_in.latitude})"

        # Khởi tạo bản ghi lịch sử vị trí
        sample = LocationSample(
            **location_in.model_dump(
                exclude={
                    'latitude',
                    'longitude',
                    'altitude_m',
                    'speed_mps',
                    'heading_deg',
                    'accuracy_m',
                    'satellite_count',
                    'source',
                }
            ),
            latitude=location_in.latitude,
            longitude=location_in.longitude,
            location=point,  # Điểm PostGIS phục vụ truy vấn không gian
            altitude_m=location_in.altitude_m,
            speed_mps=location_in.speed_mps,
            heading_deg=location_in.heading_deg,
            accuracy_m=location_in.accuracy_m,
            satellite_count=location_in.satellite_count,
            source=location_in.source,
            received_at=datetime.now(timezone.utc),
        )
        db.add(sample)

        # Truy vấn lấy dòng trạng thái hiện tại của thiết bị
        latest_res = await db.execute(
            select(DeviceLatestState).filter(
                DeviceLatestState.device_id == location_in.device_id
            )
        )
        latest = latest_res.scalars().first()

        generated_events: List[DeviceEvent] = []

        # 1. Phát hiện sự kiện ONLINE (Khi thiết bị vừa kết nối lại sau khi offline)
        was_online = latest.is_online if latest else False
        if not was_online:
            online_event = DeviceEvent(
                device_id=location_in.device_id,
                event_type="ONLINE",
                occurred_at=location_in.measured_at,
                location=point,
                metadata_={
                    "source": location_in.source,
                    "description": "Thiết bị kết nối trực tuyến",
                },
            )
            db.add(online_event)
            generated_events.append(online_event)

        # 2. Phát hiện chuyển đổi trạng thái di chuyển (Bắt đầu chạy / Dừng lại)
        prev_speed = latest.current_speed_mps if latest else None
        new_speed = location_in.speed_mps
        if new_speed is not None:
            if (prev_speed is None or prev_speed <= 0.5) and new_speed > 0.5:
                speed_kmh = round(new_speed * 3.6, 1)
                move_event = DeviceEvent(
                    device_id=location_in.device_id,
                    event_type="MOVEMENT_STARTED",
                    occurred_at=location_in.measured_at,
                    location=point,
                    metadata_={
                        "speed_mps": new_speed,
                        "heading_deg": location_in.heading_deg,
                        "source": location_in.source,
                        "description": f"Bắt đầu di chuyển ({speed_kmh} km/h)",
                    },
                )
                db.add(move_event)
                generated_events.append(move_event)
            elif (prev_speed is not None and prev_speed > 0.5) and new_speed <= 0.5:
                stop_event = DeviceEvent(
                    device_id=location_in.device_id,
                    event_type="MOVEMENT_STOPPED",
                    occurred_at=location_in.measured_at,
                    location=point,
                    metadata_={
                        "speed_mps": new_speed,
                        "source": location_in.source,
                        "description": "Thiết bị đã dừng lại",
                    },
                )
                db.add(stop_event)
                generated_events.append(stop_event)

        # Cập nhật bảng latest_state
        if latest:
            latest.current_latitude = location_in.latitude
            latest.current_longitude = location_in.longitude
            latest.current_speed_mps = location_in.speed_mps
            latest.current_heading_deg = location_in.heading_deg
            latest.last_seen_at = location_in.measured_at
            latest.is_online = True
            latest.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)

        # Commit giao dịch lưu location, state và các event phát sinh
        await db.commit()
        await db.refresh(sample)
        for event in generated_events:
            await db.refresh(event)

        return sample, generated_events
