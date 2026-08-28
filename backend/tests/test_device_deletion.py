# Xác nhận xóa thiết bị là giao dịch nguyên tử, dọn đúng dữ liệu phụ thuộc, giữ audit
# và chỉ phát realtime sau khi service đã hoàn tất commit.
import asyncio
import os
import sys
import unittest
import uuid
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, call, patch

from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError


os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.api.v1.devices import delete_device as delete_device_route  # noqa: E402
from app.domain.enums import DeviceStatus, DeviceType  # noqa: E402
from app.models.audit_log import AuditLog  # noqa: E402
from app.models.device import Device  # noqa: E402
from app.services.device_service import DeviceService  # noqa: E402


class _ScalarResult:
    def __init__(self, value):
        self._value = value

    def scalar_one_or_none(self):
        return self._value


def _device(device_id: uuid.UUID) -> Device:
    return Device(
        id=device_id,
        device_code="CAR-DELETE-01",
        name="Xe kiểm thử xóa",
        device_type=DeviceType.VEHICLE,
        serial_number="SERIAL-DELETE-01",
        manufacturer="VMonitor",
        model="VM-01",
        firmware_version="1.0.0",
        status=DeviceStatus.OFFLINE,
        is_enabled=False,
        metadata_json={"purpose": "deletion-test"},
    )


class DeviceDeletionServiceTest(unittest.TestCase):
    def test_delete_removes_dependencies_in_order_and_keeps_audit(self):
        device_id = uuid.uuid4()
        actor_id = uuid.uuid4()
        db = AsyncMock()
        db.execute = AsyncMock(
            side_effect=[_ScalarResult(_device(device_id)), None, None, None, None, None]
        )
        db.add = Mock()
        db.commit = AsyncMock()

        deleted = asyncio.run(
            DeviceService.delete_device(
                db,
                device_id,
                actor_user_id=actor_id,
            )
        )

        self.assertEqual(
            [call.args[0].table.name for call in db.execute.await_args_list[1:]],
            [
                "device_events",
                "device_latest_state",
                "location_samples",
                "telemetry_messages",
                "devices",
            ],
        )
        db.commit.assert_awaited_once()
        audit = db.add.call_args.args[0]
        self.assertIsInstance(audit, AuditLog)
        self.assertEqual(audit.action, "DEVICE_DELETED")
        self.assertEqual(audit.actor_user_id, actor_id)
        self.assertEqual(audit.entity_id, device_id)
        self.assertEqual(audit.old_value["device_code"], "CAR-DELETE-01")
        self.assertIsNone(audit.new_value)
        self.assertEqual(
            deleted,
            {
                "id": str(device_id),
                "device_code": "CAR-DELETE-01",
                "name": "Xe kiểm thử xóa",
            },
        )

    def test_delete_missing_device_does_not_write_or_commit(self):
        db = AsyncMock()
        db.execute = AsyncMock(return_value=_ScalarResult(None))
        db.add = Mock()
        db.commit = AsyncMock()

        deleted = asyncio.run(DeviceService.delete_device(db, uuid.uuid4()))

        self.assertIsNone(deleted)
        db.add.assert_not_called()
        db.commit.assert_not_awaited()


class DeviceDeletionRouteTest(unittest.TestCase):
    def test_route_broadcasts_only_after_successful_delete(self):
        device_id = uuid.uuid4()
        actor_id = uuid.uuid4()
        db = AsyncMock()
        service = AsyncMock(
            return_value={
                "id": str(device_id),
                "device_code": "CAR-DELETE-01",
                "name": "Xe kiểm thử xóa",
            }
        )
        broadcast = AsyncMock()
        calls = Mock()
        calls.attach_mock(service, "service")
        calls.attach_mock(broadcast, "broadcast")

        with patch.object(DeviceService, "delete_device", new=service), patch(
            "app.api.v1.devices.realtime_service.broadcast_telemetry",
            new=broadcast,
        ):
            response = asyncio.run(
                delete_device_route(
                    device_id,
                    db=db,
                    current_user=SimpleNamespace(id=actor_id),
                )
            )

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        service.assert_awaited_once_with(
            db,
            device_id,
            actor_user_id=actor_id,
        )
        broadcast.assert_awaited_once_with(
            {
                "type": "DEVICE_DELETED",
                "device_id": str(device_id),
                "device_code": "CAR-DELETE-01",
            }
        )
        self.assertEqual(
            calls.mock_calls,
            [
                call.service(db, device_id, actor_user_id=actor_id),
                call.broadcast(
                    {
                        "type": "DEVICE_DELETED",
                        "device_id": str(device_id),
                        "device_code": "CAR-DELETE-01",
                    }
                ),
            ],
        )

    def test_route_returns_404_without_broadcast_for_missing_device(self):
        db = AsyncMock()
        service = AsyncMock(return_value=None)
        broadcast = AsyncMock()

        with patch.object(DeviceService, "delete_device", new=service), patch(
            "app.api.v1.devices.realtime_service.broadcast_telemetry",
            new=broadcast,
        ):
            with self.assertRaises(HTTPException) as error:
                asyncio.run(
                    delete_device_route(
                        uuid.uuid4(),
                        db=db,
                        current_user=SimpleNamespace(id=uuid.uuid4()),
                    )
                )

        self.assertEqual(error.exception.status_code, status.HTTP_404_NOT_FOUND)
        broadcast.assert_not_awaited()

    def test_route_rolls_back_conflict_without_broadcast(self):
        db = AsyncMock()
        db.rollback = AsyncMock()
        service = AsyncMock(
            side_effect=IntegrityError("DELETE devices", {}, Exception("fk conflict"))
        )
        broadcast = AsyncMock()

        with patch.object(DeviceService, "delete_device", new=service), patch(
            "app.api.v1.devices.realtime_service.broadcast_telemetry",
            new=broadcast,
        ):
            with self.assertRaises(HTTPException) as error:
                asyncio.run(
                    delete_device_route(
                        uuid.uuid4(),
                        db=db,
                        current_user=SimpleNamespace(id=uuid.uuid4()),
                    )
                )

        self.assertEqual(error.exception.status_code, status.HTTP_409_CONFLICT)
        self.assertEqual(
            error.exception.detail,
            "Thiết bị đang có dữ liệu được xử lý, vui lòng thử lại",
        )
        db.rollback.assert_awaited_once()
        broadcast.assert_not_awaited()


if __name__ == "__main__":
    unittest.main()
