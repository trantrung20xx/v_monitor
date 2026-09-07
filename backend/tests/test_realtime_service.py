"""Bảo vệ đường gửi độc lập, timeout và giới hạn bộ nhớ."""
import asyncio
import json
import os
import sys
import time
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test")
os.environ.setdefault("JWT_SECRET", "x" * 48)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.services.realtime_service import RealtimeService


class Socket:
    def __init__(self, *, blocked=False):
        self.blocked = blocked
        self.messages = []
        self.received = asyncio.Event()
        self.closed = asyncio.Event()

    async def accept(self):
        pass

    async def send_text(self, message):
        if self.blocked:
            await asyncio.Event().wait()
        self.messages.append(json.loads(message))
        self.received.set()

    async def close(self, code):
        self.closed.set()


class RealtimeServiceTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.service = RealtimeService()

    async def asyncTearDown(self):
        await self.service.stop()

    async def test_publisher_returns_before_slow_socket_and_closes_it(self):
        healthy, slow = Socket(), Socket(blocked=True)
        await self.service.connect(healthy)
        await self.service.connect(slow)
        with patch("app.services.realtime_service.settings.realtime_send_timeout_seconds", 0.05):
            started = time.perf_counter()
            await self.service.broadcast_telemetry({"type": "DEVICE_EVENT", "event": {"id": "test"}})
            self.assertLess(time.perf_counter() - started, 0.02)
            await asyncio.wait_for(healthy.received.wait(), 0.03)
            self.assertFalse(slow.closed.is_set())
            await asyncio.wait_for(slow.closed.wait(), 0.2)
        self.assertNotIn(slow, self.service.active_connections)
        self.assertIn(healthy, self.service.active_connections)

    async def test_full_socket_queue_disconnects_without_unbounded_tasks(self):
        with patch("app.services.realtime_service.settings.realtime_client_queue_size", 2):
            slow = Socket(blocked=True)
            await self.service.connect(slow)
            for index in range(4):
                await self.service.broadcast_telemetry({"type": "EVENT", "id": index})
            await asyncio.wait_for(slow.closed.wait(), 0.2)
        self.assertNotIn(slow, self.service._queues)
        self.assertNotIn(slow, self.service._senders)

    async def test_thousands_of_changes_are_coalesced_by_device(self):
        await self.service.connect(Socket())
        ids = [uuid.uuid4() for _ in range(5000)]
        for _ in range(5):
            for device_id in ids:
                self.service.notify_device(device_id)
        self.assertEqual(len(self.service._dirty), 5000)
        self.assertEqual(len(self.service._senders), 1)

    async def test_pending_device_limit_requests_resync(self):
        await self.service.connect(Socket())
        with patch("app.services.realtime_service.settings.realtime_pending_device_limit", 2):
            for _ in range(3):
                self.service.notify_device(uuid.uuid4())
        self.assertEqual(len(self.service._dirty), 2)
        self.assertTrue(self.service._resync_required)

    async def test_durable_delivery_waits_for_actual_sender(self):
        socket = Socket()
        await self.service.connect(socket, supports_batches=True)
        self.assertTrue(await self.service.deliver_events([{"type": "DEVICE_EVENT", "event": {"id": "stable"}}]))
        self.assertEqual(socket.messages[0]["messages"][0]["event"]["id"], "stable")

    async def test_legacy_client_receives_original_frames_without_filling_queue_per_device(self):
        socket = Socket()
        await self.service.connect(socket)
        self.service._enqueue({"type": "DEVICE_UPDATES", "devices": [{"id": str(i)} for i in range(250)]})
        self.assertEqual(self.service._queues[socket].qsize(), 1)
        self.assertTrue(await self.service.deliver_events([{"type": "DEVICE_EVENT", "event": {"id": "stable"}}]))
        self.assertEqual(len(socket.messages), 251)
        self.assertEqual(socket.messages[0]["type"], "DEVICE_UPDATE")
        self.assertEqual(socket.messages[-1]["type"], "DEVICE_EVENT")


if __name__ == "__main__":
    unittest.main()
