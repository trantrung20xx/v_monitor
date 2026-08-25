"""Kiểm tra luồng MQTT và quản lý thiết bị trên database kiểm thử cô lập."""

import asyncio
import json
import uuid

from sqlalchemy import func, select

from app.core.database import AsyncSessionLocal, engine
from app.domain.enums import DeviceType
from app.models.device import Device
from app.models.device_latest_state import DeviceLatestState
from app.models.location_sample import LocationSample
from app.models.mqtt_device_sighting import MqttDeviceSighting
from app.models.telemetry_message import TelemetryMessage
from app.schemas.device import DeviceCreate, DeviceUpdate
from app.services.device_service import DeviceService
from app.services.mqtt_service import mqtt_service


DEVICE_CODE = "DEVICE-MANAGEMENT-SMOKE"
TOPIC = f"v_monitor/telemetry/{DEVICE_CODE}"


async def run() -> None:
    payload = {
        "message_id": "device-management-smoke-001",
        "measured_at": "2026-08-24T04:00:00Z",
        "latitude": 21.0285,
        "longitude": 105.8048,
    }

    await mqtt_service.process_message(TOPIC, json.dumps(payload), qos=1)
    await mqtt_service.process_message(TOPIC, json.dumps(payload), qos=1)
    async with AsyncSessionLocal() as db:
        sighting = await db.get(MqttDeviceSighting, DEVICE_CODE)
        assert sighting is not None
        assert sighting.message_count == 2

        created = await DeviceService.create_device(
            db,
            DeviceCreate(
                device_code=DEVICE_CODE,
                name="Thiết bị kiểm tra quản lý",
                device_type=DeviceType.OTHER,
                is_enabled=False,
            ),
        )
        device_id = uuid.UUID(created["id"])
        assert await db.get(MqttDeviceSighting, DEVICE_CODE) is None

    # Thiết bị bị khóa không được tạo telemetry hay cập nhật vị trí.
    await mqtt_service.process_message(TOPIC, json.dumps(payload), qos=1)
    async with AsyncSessionLocal() as db:
        telemetry_count = await db.scalar(
            select(func.count(TelemetryMessage.id)).where(
                TelemetryMessage.device_id == device_id
            )
        )
        assert telemetry_count == 0
        updated = await DeviceService.update_device(
            db,
            device_id,
            DeviceUpdate(is_enabled=True),
        )
        assert updated is not None and updated["is_enabled"] is True

    # QoS 1 phát lại cùng message_id chỉ tạo một telemetry và một mẫu vị trí.
    await mqtt_service.process_message(TOPIC, json.dumps(payload), qos=1)
    await mqtt_service.process_message(TOPIC, json.dumps(payload), qos=1)
    async with AsyncSessionLocal() as db:
        telemetry_count = await db.scalar(
            select(func.count(TelemetryMessage.id)).where(
                TelemetryMessage.device_id == device_id
            )
        )
        location_count = await db.scalar(
            select(func.count(LocationSample.id)).where(
                LocationSample.device_id == device_id
            )
        )
        latest = await db.get(DeviceLatestState, device_id)
        assert telemetry_count == 1
        assert location_count == 1
        assert latest is not None and latest.is_online is True

        updated = await DeviceService.update_device(
            db,
            device_id,
            DeviceUpdate(name="Thiết bị đã chỉnh sửa", is_enabled=False),
        )
        assert updated is not None
        assert updated["name"] == "Thiết bị đã chỉnh sửa"
        assert updated["is_enabled"] is False
        refreshed_latest = await db.get(DeviceLatestState, device_id)
        assert refreshed_latest is not None and refreshed_latest.is_online is False
        device = await db.get(Device, device_id)
        assert device is not None and device.is_enabled is False

    print("DEVICE_MANAGEMENT_SMOKE=passed")
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(run())
