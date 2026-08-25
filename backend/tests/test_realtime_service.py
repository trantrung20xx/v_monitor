# Xác nhận WebSocket lỗi hoặc chậm bị loại mà không cản các kết nối khỏe mạnh.
import asyncio
import os
import sys
import time
import unittest
from pathlib import Path
from unittest import mock


os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test",
)
os.environ.setdefault("JWT_SECRET", "x" * 48)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services.realtime_service import RealtimeService  # noqa: E402


class RealtimeServiceTest(unittest.TestCase):
    def test_removes_failed_connection_without_blocking_healthy_connection(self):
        service = RealtimeService()
        healthy = _FakeWebSocket()
        failed = _FakeWebSocket(should_fail=True)
        service.active_connections.extend([failed, healthy])

        asyncio.run(service.broadcast_telemetry({"type": "DEVICE_UPDATE"}))

        self.assertEqual(healthy.messages, [{"type": "DEVICE_UPDATE"}])
        self.assertNotIn(failed, service.active_connections)
        self.assertIn(healthy, service.active_connections)

    def test_removes_slow_connection_at_the_configured_timeout(self):
        service = RealtimeService()
        healthy = _FakeWebSocket()
        slow = _FakeWebSocket(delay_seconds=1)
        service.active_connections.extend([slow, healthy])

        started_at = time.perf_counter()
        with mock.patch(
            "app.services.realtime_service.settings.realtime_send_timeout_seconds",
            0.01,
        ):
            asyncio.run(service.broadcast_telemetry({"type": "DEVICE_UPDATE"}))
        elapsed = time.perf_counter() - started_at

        self.assertLess(elapsed, 0.2)
        self.assertEqual(healthy.messages, [{"type": "DEVICE_UPDATE"}])
        self.assertNotIn(slow, service.active_connections)
        self.assertIn(healthy, service.active_connections)


class _FakeWebSocket:
    def __init__(self, *, should_fail: bool = False, delay_seconds: float = 0):
        self.should_fail = should_fail
        self.delay_seconds = delay_seconds
        self.messages = []

    async def send_json(self, message):
        if self.delay_seconds:
            await asyncio.sleep(self.delay_seconds)
        if self.should_fail:
            raise ConnectionError("socket closed")
        self.messages.append(message)


if __name__ == "__main__":
    unittest.main()
