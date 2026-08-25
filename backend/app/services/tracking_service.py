# Nghiệp vụ GPS trung tâm: lưu mẫu lịch sử, bảo vệ latest state khỏi gói đến trễ,
# phát hiện chuyển động, cập nhật pin/online và tạo DEVICE_UPDATE/DEVICE_EVENT.
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
from app.services.system_settings_service import system_settings_service


class DeviceNotFoundError(ValueError):
    # Báo telemetry tham chiếu tới UUID thiết bị không còn tồn tại.

    pass


def _utc_datetime(value: datetime) -> datetime:
    """Chuẩn hóa thời gian thiết bị thành UTC có múi giờ."""
    # Firmware gửi timestamp không có offset được hiểu theo quy ước UTC của hệ thống.
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    # Timestamp có offset được chuyển về UTC nhưng vẫn giữ nguyên thời điểm tuyệt đối.
    return value.astimezone(timezone.utc)


class TrackingService:
    # Nguồn nghiệp vụ duy nhất cho lịch sử GPS, latest state và sự kiện di chuyển.

    @staticmethod
    async def get_location_history(
        db: AsyncSession,
        device_id: uuid.UUID,
        limit: int = 100,
    ) -> List[LocationSample]:
        # Lấy các mẫu mới nhất theo thứ tự giảm dần, có giới hạn để bảo vệ API.
        result = await db.execute(
            select(LocationSample)
            .where(LocationSample.device_id == device_id)
            .order_by(LocationSample.measured_at.desc(), LocationSample.id.desc())
            .limit(limit)
        )
        # scalars loại phần wrapper Row của SQLAlchemy, trả đúng danh sách model.
        # Thứ tự giảm dần phù hợp màn hình "mẫu gần nhất" của API ngắn.
        return list(result.scalars().all())

    @staticmethod
    async def get_location_history_range(
        db: AsyncSession,
        device_id: uuid.UUID,
        from_time: datetime,
        to_time: datetime,
        max_samples: int | None = None,
    ) -> Tuple[List[LocationSample], int, bool]:
        # Lấy hành trình tăng dần theo thời gian kèm tổng số và cờ bị cắt bớt.
        # total_count mô tả toàn bộ khoảng chọn; samples chỉ chứa tối đa limit bản ghi.
        # Frontend dùng cờ thứ ba để thông báo khi hành trình không được tải đầy đủ.
        limit = max_samples or settings.tracking_max_history_samples
        # Dùng chung bộ lọc cho truy vấn đếm và truy vấn dữ liệu để total luôn khớp.
        filters = (
            LocationSample.device_id == device_id,
            LocationSample.measured_at >= from_time,
            LocationSample.measured_at <= to_time,
        )
        count_result = await db.execute(
            select(func.count(LocationSample.id)).where(*filters)
        )
        total_count = count_result.scalar_one() or 0
        # Thứ tự tăng dần giúp frontend vẽ polyline và tính đoạn đường theo thời gian.
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
        # Lấy sự kiện gần nhất, có thể lọc theo loại nhưng không sửa dữ liệu gốc.
        query = select(DeviceEvent).where(DeviceEvent.device_id == device_id)
        # Chuẩn hóa chữ hoa để tham số `online` và `ONLINE` cho cùng kết quả.
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
        runtime_settings = await system_settings_service.get_runtime_settings()
        # Ngưỡng chuyển động có thể đổi từ phần cài đặt; không cố định trong thuật toán.
        movement_threshold = runtime_settings.movement_threshold_mps
        # `received_at` và `measured_at` phục vụ hai nghiệp vụ khác nhau: presence
        # tin đồng hồ server, còn thứ tự hành trình tin mốc đo đã chuẩn hóa UTC.
        received_at = datetime.now(timezone.utc)
        measured_at = _utc_datetime(location_in.measured_at)
        # PostGIS nhận WKT theo thứ tự longitude latitude (X Y), khác thứ tự thường
        # dùng khi hiển thị LatLng trên Flutter.
        point = f"SRID=4326;POINT({location_in.longitude} {location_in.latitude})"

        # Khóa một dòng theo thiết bị để các worker MQTT không ghi đè lẫn nhau.
        latest_result = await db.execute(
            select(DeviceLatestState)
            .where(DeviceLatestState.device_id == location_in.device_id)
            .with_for_update()
        )
        latest = latest_result.scalar_one_or_none()
        # Thiết bị cũ hoặc dữ liệu migration có thể chưa có latest_state; tạo bù
        # nhưng chỉ khi hồ sơ Device gốc vẫn tồn tại.
        if latest is None:
            # UUID không tồn tại phải bị từ chối để không tạo dòng trạng thái mồ côi.
            if await db.get(Device, location_in.device_id) is None:
                raise DeviceNotFoundError("Không tìm thấy thiết bị")
            # Dòng mới bắt đầu offline và chưa có tọa độ cho tới khi các trường dưới được cập nhật.
            latest = DeviceLatestState(device_id=location_in.device_id)
            db.add(latest)
            # flush lấy/ghi khóa liên kết trong transaction nhưng chưa công khai dữ
            # liệu cho request khác; commit chung nằm ở cuối phương thức.
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
        # Cần id của sample để latest_sample_id tham chiếu đúng trong cùng transaction.
        await db.flush()

        generated_events: List[DeviceEvent] = []
        # Giữ trạng thái cũ trước khi cập nhật để chỉ sinh ONLINE đúng lúc chuyển cạnh.
        was_online = latest.is_online

        # Trạng thái kết nối dựa trên lúc server nhận gói, không dựa trên đồng hồ thiết bị.
        # Chỉ cạnh False → True tạo event; gói liên tiếp khi đang online không tạo log lặp.
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

        # Mọi gói vị trí hợp lệ, kể cả gói đo đến trễ, đều chứng minh thiết bị vừa
        # liên lạc với server nên phải làm mới presence.
        latest.last_seen_at = received_at
        latest.is_online = True
        latest.updated_at = received_at

        # Gói đến trễ vẫn được lưu lịch sử nhưng không được ghi đè vị trí hiện tại.
        # Dấu bằng cho phép bản sửa cùng mốc đo cập nhật latest theo thứ tự xử lý sau cùng.
        is_newest_sample = (
            latest.latest_measured_at is None
            or measured_at >= latest.latest_measured_at
        )
        # Toàn bộ logic tốc độ, pin và marker hiện tại chỉ chạy cho mẫu mới nhất.
        if is_newest_sample:
            # Sự kiện bắt đầu/dừng chỉ sinh khi tốc độ đi qua ngưỡng. Hai mẫu cùng
            # phía ngưỡng không tạo sự kiện lặp ở mỗi gói telemetry.
            previous_speed = latest.current_speed_mps
            new_speed = location_in.speed_mps
            if new_speed is not None:
                if (
                    previous_speed is None
                    or previous_speed <= movement_threshold
                ) and new_speed > movement_threshold:
                    # Chuyển từ chưa có/đứng yên sang vượt ngưỡng tạo một sự kiện bắt đầu.
                    # Tốc độ m/s được đổi sang km/h chỉ để mô tả dễ đọc trong event.
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
                elif (
                    previous_speed is not None
                    and previous_speed > movement_threshold
                    and new_speed <= movement_threshold
                ):
                    # Chỉ cạnh đang chạy → bằng/dưới ngưỡng mới tạo sự kiện dừng.
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

            # Chỉ nhánh newest cập nhật các trường "hiện tại". Gói trễ vẫn tồn tại
            # trong location_samples nhưng không làm marker trên bản đồ quay về quá khứ.
            latest.current_latitude = location_in.latitude
            latest.current_longitude = location_in.longitude
            latest.current_altitude_m = location_in.altitude_m
            latest.current_speed_mps = location_in.speed_mps
            latest.current_heading_deg = location_in.heading_deg
            # Payload thiếu pin không được xóa mức pin gần nhất đã biết; giá trị 0
            # vẫn được cập nhật vì kiểm tra bằng `is not None`.
            if location_in.battery_pct is not None:
                latest.battery_pct = location_in.battery_pct
            latest.latest_measured_at = measured_at
            latest.latest_sample_id = sample.id

        await db.commit()
        # Commit một lần bảo đảm sample, latest state và mọi event cùng thành công
        # hoặc cùng rollback; caller chỉ phát realtime sau điểm này.
        await db.refresh(sample)
        # Refresh event lấy id/timestamp do database sinh trước khi phát WebSocket.
        for event in generated_events:
            await db.refresh(event)
        return sample, generated_events
