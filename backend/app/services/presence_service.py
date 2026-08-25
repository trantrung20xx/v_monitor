# Dịch vụ nền xác định thiết bị ngoại tuyến từ last_seen_at và ngưỡng runtime.
# Mỗi lần chuyển trạng thái chỉ ghi một sự kiện và phát realtime, không dùng để cấp quyền gửi.
import asyncio
from datetime import datetime, timedelta, timezone
import logging

from sqlalchemy import select

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.device_event import DeviceEvent
from app.models.device_latest_state import DeviceLatestState
from app.services.realtime_service import realtime_service
from app.services.system_settings_service import system_settings_service


logger = logging.getLogger(__name__)


class PresenceService:
    # Quét latest state theo chu kỳ và phát hiện cạnh chuyển online sang offline.

    def __init__(self) -> None:
        # stop_event cho phép đánh thức vòng chờ khi tắt ứng dụng; task giữ đúng một
        # tiến trình quét nền thay vì tạo timer mới sau mỗi chu kỳ.
        self._stop_event = asyncio.Event()
        self._task: asyncio.Task | None = None

    async def mark_stale_devices_offline(
        self,
        *,
        now: datetime | None = None,
    ) -> int:
        # Đánh dấu các thiết bị quá hạn và trả số trạng thái thực sự đã thay đổi.
        current_time = now or datetime.now(timezone.utc)
        runtime_settings = await system_settings_service.get_runtime_settings()
        # cutoff dựa trên thời gian backend nhận gói gần nhất, tránh sai lệch đồng hồ GPS.
        # `now` có thể truyền từ test để kiểm tra biên thời gian một cách xác định.
        # Thiết bị có last_seen_at đúng bằng cutoff chưa bị coi là quá hạn do truy vấn dùng `<`.
        cutoff = current_time - timedelta(
            seconds=runtime_settings.offline_timeout_seconds
        )
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(DeviceLatestState)
                .where(
                    # Chỉ quét dòng đang online và có mốc nhận gói; thiết bị chưa từng
                    # gửi dữ liệu không sinh sự kiện OFFLINE giả.
                    DeviceLatestState.is_online.is_(True),
                    DeviceLatestState.last_seen_at.is_not(None),
                    DeviceLatestState.last_seen_at < cutoff,
                )
                .order_by(DeviceLatestState.last_seen_at.asc())
                    .limit(settings.device_list_max_limit)
                    # Nhiều instance backend có thể cùng quét; skip_locked bảo đảm một
                    # dòng chỉ do một instance xử lý trong cùng thời điểm.
                    .with_for_update(skip_locked=True)
            )
            states = list(result.scalars().all())
            events: list[DeviceEvent] = []
            for state in states:
                # Chuyển cờ trước khi tạo event để cùng transaction lưu một snapshot nhất quán.
                state.is_online = False
                state.updated_at = current_time
                point = None
                # Event chỉ có geometry khi cả hai thành phần tọa độ gần nhất đều tồn tại.
                if state.current_latitude is not None and state.current_longitude is not None:
                    point = (
                        f"SRID=4326;POINT({state.current_longitude} "
                        f"{state.current_latitude})"
                    )
                event = DeviceEvent(
                    device_id=state.device_id,
                    event_type="OFFLINE",
                    occurred_at=current_time,
                    location=point,
                    source="system",
                    description="Thiết bị mất kết nối",
                    metadata_={
                        # Metadata giữ mốc liên lạc cuối giúp giải thích vì sao thiết bị
                        # bị chuyển ngoại tuyến tại thời điểm hiện tại.
                        "last_seen_at": state.last_seen_at.isoformat()
                        if state.last_seen_at
                        else None
                    },
                )
                db.add(event)
                events.append(event)
            # Trả sớm trước commit khi truy vấn không tìm thấy cạnh trạng thái cần đổi.
            if not states:
                # Không commit khi không có thay đổi để tránh transaction ghi dư.
                return 0
            # Commit toàn bộ cờ offline và event trước khi phát WebSocket.
            await db.commit()
            # Phát từng event sau commit; REST vẫn có trạng thái đúng nếu socket bỏ lỡ.
            for event in events:
                await realtime_service.broadcast_telemetry(
                    {
                        "type": "DEVICE_EVENT",
                        "event": {
                            "id": str(event.id),
                            "device_id": str(event.device_id),
                            "event_type": event.event_type,
                            "occurred_at": event.occurred_at.isoformat(),
                            "source": event.source,
                            "description": event.description,
                        },
                    }
                )
            return len(states)

    async def _run(self) -> None:
        # Lặp quét có bắt lỗi; một lần lỗi database không làm chết tác vụ nền.
        while not self._stop_event.is_set():
            try:
                changed = await self.mark_stale_devices_offline()
                # Không ghi log ở mỗi chu kỳ rỗng để tránh làm nhiễu log vận hành.
                if changed:
                    logger.info("Đã chuyển %s thiết bị sang ngoại tuyến", changed)
            except Exception:
                # Exception được giữ trong vòng lặp; chu kỳ tiếp theo vẫn thử lại database.
                logger.exception("Lỗi khi quét trạng thái thiết bị ngoại tuyến")
            try:
                # Chờ event dừng hoặc hết chu kỳ, không dùng sleep để shutdown phản hồi ngay.
                await asyncio.wait_for(
                    self._stop_event.wait(),
                    timeout=settings.device_offline_scan_interval_seconds,
                )
            except asyncio.TimeoutError:
                # Timeout là tín hiệu bắt đầu vòng quét kế tiếp, không phải lỗi dịch vụ.
                pass

    async def start(self) -> None:
        # Khởi động đúng một task theo dõi presence cho mỗi tiến trình API.
        if self._task and not self._task.done():
            return
        self._stop_event.clear()
        self._task = asyncio.create_task(self._run(), name="device-presence-monitor")

    async def stop(self) -> None:
        # Báo dừng và chờ task kết thúc để shutdown FastAPI không bỏ task nền.
        self._stop_event.set()
        # Task đang wait sẽ được event đánh thức; task đang query sẽ kết thúc transaction
        # trước khi trả về.
        if self._task:
            await self._task
            self._task = None


# Singleton được start/stop cùng lifespan của ứng dụng.
presence_service = PresenceService()
