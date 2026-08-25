# Xác nhận ngưỡng runtime tác động đúng presence/tracking và gói đến trễ không ghi đè latest state.
import os
import sys
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import AsyncMock, patch


os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.models.device_event import DeviceEvent  # noqa: E402
from app.models.device_latest_state import DeviceLatestState  # noqa: E402
from app.schemas.tracking import LocationSampleCreate  # noqa: E402
from app.services.presence_service import PresenceService  # noqa: E402
from app.services.system_settings_service import (  # noqa: E402
    RuntimeSystemSettings,
)
from app.services.tracking_service import TrackingService  # noqa: E402


class _ScalarResult:
    def __init__(self, value):
        self._value = value

    def scalar_one_or_none(self):
        return self._value


class _TrackingSession:
    def __init__(self, latest):
        self.latest = latest
        self.added = []

    async def execute(self, _query):
        return _ScalarResult(self.latest)

    def add(self, value):
        self.added.append(value)

    async def flush(self):
        # SQLAlchemy chỉ sinh UUID khi INSERT; fake gán tại đây để mô phỏng flush.
        for value in self.added:
            if hasattr(value, "id") and value.id is None:
                value.id = uuid.uuid4()

    async def commit(self):
        return None

    async def refresh(self, _value):
        return None


class _ListResult:
    def __init__(self, values):
        self._values = values

    def scalars(self):
        return self

    def all(self):
        return self._values


class _PresenceSession:
    def __init__(self, states):
        self.states = states
        self.added = []

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_args):
        return None

    async def execute(self, query):
        # Lấy cutoff từ bind parameter của chính câu SQL để test ranh giới thời gian
        # mà không phải chờ đồng hồ thật.
        cutoff = next(
            value
            for value in query.compile().params.values()
            if isinstance(value, datetime)
        )
        stale = [
            state
            for state in self.states
            if state.is_online
            and state.last_seen_at is not None
            and state.last_seen_at < cutoff
        ]
        return _ListResult(stale)

    def add(self, value):
        if value.id is None:
            value.id = uuid.uuid4()
        self.added.append(value)

    async def commit(self):
        return None


def _runtime(*, movement=1.0, offline=300):
    return RuntimeSystemSettings(
        offline_timeout_seconds=offline,
        movement_threshold_mps=movement,
        default_gap_threshold_seconds=300,
    )


def _sample(device_id, measured_at, speed):
    return LocationSampleCreate(
        device_id=device_id,
        measured_at=measured_at,
        latitude=21.0285,
        longitude=105.8542,
        speed_mps=speed,
        source="test",
    )


class TrackingRuntimeSettingsTest(unittest.IsolatedAsyncioTestCase):
    async def test_movement_events_use_runtime_threshold_without_duplicates(self):
        device_id = uuid.uuid4()
        start = datetime(2026, 8, 21, 1, 0, tzinfo=timezone.utc)
        latest = DeviceLatestState(
            device_id=device_id,
            is_online=True,
            latest_measured_at=start - timedelta(seconds=1),
            current_speed_mps=0.0,
        )
        session = _TrackingSession(latest)
        event_types = []

        with patch(
            "app.services.tracking_service.system_settings_service.get_runtime_settings",
            new=AsyncMock(return_value=_runtime(movement=1.0)),
        ):
            for index, speed in enumerate([0.4, 0.8, 1.0, 1.2, 1.4, 0.9]):
                _, events = await TrackingService.add_location(
                    session,
                    _sample(device_id, start + timedelta(seconds=index), speed),
                )
                event_types.extend(event.event_type for event in events)

        self.assertEqual(event_types.count("MOVEMENT_STARTED"), 1)
        self.assertEqual(event_types.count("MOVEMENT_STOPPED"), 1)

    async def test_new_runtime_threshold_is_read_without_backend_restart(self):
        device_id = uuid.uuid4()
        start = datetime(2026, 8, 21, 2, 0, tzinfo=timezone.utc)
        latest = DeviceLatestState(
            device_id=device_id,
            is_online=True,
            latest_measured_at=start - timedelta(seconds=1),
            current_speed_mps=0.0,
        )
        session = _TrackingSession(latest)
        runtime_values = [_runtime(movement=1.0), _runtime(movement=2.0)]

        with patch(
            "app.services.tracking_service.system_settings_service.get_runtime_settings",
            new=AsyncMock(side_effect=runtime_values),
        ):
            _, first_events = await TrackingService.add_location(
                session,
                _sample(device_id, start, 1.2),
            )
            _, second_events = await TrackingService.add_location(
                session,
                _sample(device_id, start + timedelta(seconds=1), 0.5),
            )

        self.assertIn("MOVEMENT_STARTED", [event.event_type for event in first_events])
        # Với ngưỡng cũ 1.0, chuyển 1.2 -> 0.5 sẽ tạo MOVEMENT_STOPPED. Không
        # có sự kiện ở đây chứng minh mẫu thứ hai đã dùng ngay ngưỡng mới 2.0.
        self.assertNotIn(
            "MOVEMENT_STOPPED",
            [event.event_type for event in second_events],
        )
        self.assertEqual(latest.current_speed_mps, 0.5)

    async def test_late_sample_is_stored_but_does_not_replace_latest_state(self):
        device_id = uuid.uuid4()
        newer_time = datetime(2026, 8, 21, 3, 0, tzinfo=timezone.utc)
        latest = DeviceLatestState(
            device_id=device_id,
            is_online=True,
            latest_measured_at=newer_time,
            current_latitude=21.0,
            current_longitude=105.0,
            current_speed_mps=2.5,
        )
        session = _TrackingSession(latest)

        with patch(
            "app.services.tracking_service.system_settings_service.get_runtime_settings",
            new=AsyncMock(return_value=_runtime()),
        ):
            sample, events = await TrackingService.add_location(
                session,
                _sample(device_id, newer_time - timedelta(minutes=1), 0.0),
            )

        self.assertIn(sample, session.added)
        self.assertEqual(events, [])
        self.assertEqual(latest.latest_measured_at, newer_time)
        self.assertEqual(latest.current_speed_mps, 2.5)
        self.assertEqual(latest.current_latitude, 21.0)


class PresenceRuntimeSettingsTest(unittest.IsolatedAsyncioTestCase):
    async def test_controlled_cutoff_and_single_offline_event(self):
        now = datetime(2026, 8, 21, 4, 0, tzinfo=timezone.utc)
        online = DeviceLatestState(
            device_id=uuid.uuid4(),
            is_online=True,
            last_seen_at=now - timedelta(seconds=299),
        )
        stale = DeviceLatestState(
            device_id=uuid.uuid4(),
            is_online=True,
            last_seen_at=now - timedelta(seconds=301),
        )
        session = _PresenceSession([online, stale])
        broadcast = AsyncMock()

        with (
            patch(
                "app.services.presence_service.AsyncSessionLocal",
                return_value=session,
            ),
            patch(
                "app.services.presence_service.system_settings_service.get_runtime_settings",
                new=AsyncMock(return_value=_runtime(offline=300)),
            ),
            patch(
                "app.services.presence_service.realtime_service.broadcast_telemetry",
                new=broadcast,
            ),
        ):
            first_count = await PresenceService().mark_stale_devices_offline(now=now)
            second_count = await PresenceService().mark_stale_devices_offline(now=now)

        self.assertTrue(online.is_online)
        self.assertFalse(stale.is_online)
        self.assertEqual(first_count, 1)
        self.assertEqual(second_count, 0)
        self.assertEqual(
            len([value for value in session.added if isinstance(value, DeviceEvent)]),
            1,
        )
        broadcast.assert_awaited_once()

    async def test_changed_timeout_is_used_without_restart(self):
        now = datetime(2026, 8, 21, 5, 0, tzinfo=timezone.utc)
        state = DeviceLatestState(
            device_id=uuid.uuid4(),
            is_online=True,
            last_seen_at=now - timedelta(seconds=500),
        )
        session = _PresenceSession([state])

        with (
            patch(
                "app.services.presence_service.AsyncSessionLocal",
                return_value=session,
            ),
            patch(
                "app.services.presence_service.system_settings_service.get_runtime_settings",
                new=AsyncMock(return_value=_runtime(offline=600)),
            ),
        ):
            changed = await PresenceService().mark_stale_devices_offline(now=now)

        self.assertEqual(changed, 0)
        self.assertTrue(state.is_online)


if __name__ == "__main__":
    unittest.main()
