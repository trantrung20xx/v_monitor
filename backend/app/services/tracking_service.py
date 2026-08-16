from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import func
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
    async def get_device_events(db: AsyncSession, device_id: uuid.UUID, limit: int = 100) -> List[DeviceEvent]:
        result = await db.execute(
            select(DeviceEvent)
            .filter(DeviceEvent.device_id == device_id)
            .order_by(DeviceEvent.occurred_at.desc())
            .limit(limit)
        )
        return list(result.scalars().all())

    @staticmethod
    async def add_location(db: AsyncSession, location_in: LocationSampleCreate) -> LocationSample:
        """
        Ghi nhận một tọa độ mới vào CSDL và đồng thời cập nhật trạng thái mới nhất của thiết bị.
        """
        # Tạo chuỗi định dạng WKT (Well-Known Text) dành riêng cho cơ sở dữ liệu không gian PostGIS (SRID=4326)
        point = f"SRID=4326;POINT({location_in.longitude} {location_in.latitude})"

        # Khởi tạo bản ghi lịch sử vị trí
        sample = LocationSample(
            **location_in.model_dump(exclude={'latitude', 'longitude', 'altitude_m', 'speed_mps', 'heading_deg', 'accuracy_m', 'satellite_count', 'source'}),
            latitude=location_in.latitude,
            longitude=location_in.longitude,
            location=point, # Điểm PostGIS phục vụ truy vấn không gian sau này
            altitude_m=location_in.altitude_m,
            speed_mps=location_in.speed_mps,
            heading_deg=location_in.heading_deg,
            accuracy_m=location_in.accuracy_m,
            satellite_count=location_in.satellite_count,
            source=location_in.source,
            received_at=datetime.now(timezone.utc)
        )
        db.add(sample)

        # Truy vấn lấy dòng trạng thái hiện tại (bảng rút gọn) của thiết bị
        latest = await db.execute(select(DeviceLatestState).filter(DeviceLatestState.device_id == location_in.device_id))
        latest = latest.scalars().first()

        # Nếu thiết bị đã có dòng trạng thái, tiến hành cập nhật
        if latest:
            latest.current_latitude = location_in.latitude
            latest.current_longitude = location_in.longitude
            latest.current_speed_mps = location_in.speed_mps
            latest.current_heading_deg = location_in.heading_deg
            latest.last_seen_at = location_in.measured_at
            latest.is_online = True
            latest.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)

        # Commit giao dịch (transaction) để lưu đồng thời cả 2 bảng vào CSDL
        await db.commit()
        await db.refresh(sample)

        return sample
