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
    def __init__(self) -> None:
        self._stop_event = asyncio.Event()
        self._task: asyncio.Task | None = None

    async def mark_stale_devices_offline(
        self,
        *,
        now: datetime | None = None,
    ) -> int:
        current_time = now or datetime.now(timezone.utc)
        runtime_settings = await system_settings_service.get_runtime_settings()
        cutoff = current_time - timedelta(
            seconds=runtime_settings.offline_timeout_seconds
        )
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(DeviceLatestState)
                .where(
                    DeviceLatestState.is_online.is_(True),
                    DeviceLatestState.last_seen_at.is_not(None),
                    DeviceLatestState.last_seen_at < cutoff,
                )
                .order_by(DeviceLatestState.last_seen_at.asc())
                .limit(settings.device_list_max_limit)
                .with_for_update(skip_locked=True)
            )
            states = list(result.scalars().all())
            events: list[DeviceEvent] = []
            for state in states:
                state.is_online = False
                state.updated_at = current_time
                point = None
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
                        "last_seen_at": state.last_seen_at.isoformat()
                        if state.last_seen_at
                        else None
                    },
                )
                db.add(event)
                events.append(event)
            if not states:
                return 0
            await db.commit()
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
        while not self._stop_event.is_set():
            try:
                changed = await self.mark_stale_devices_offline()
                if changed:
                    logger.info("Đã chuyển %s thiết bị sang ngoại tuyến", changed)
            except Exception:
                logger.exception("Lỗi khi quét trạng thái thiết bị ngoại tuyến")
            try:
                await asyncio.wait_for(
                    self._stop_event.wait(),
                    timeout=settings.device_offline_scan_interval_seconds,
                )
            except asyncio.TimeoutError:
                pass

    async def start(self) -> None:
        if self._task and not self._task.done():
            return
        self._stop_event.clear()
        self._task = asyncio.create_task(self._run(), name="device-presence-monitor")

    async def stop(self) -> None:
        self._stop_event.set()
        if self._task:
            await self._task
            self._task = None


presence_service = PresenceService()
