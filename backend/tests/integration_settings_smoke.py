"""Mô phỏng Settings trên PostgreSQL dùng một lần và pipeline runtime thật."""

import asyncio
import json
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import WebSocketDisconnect
from sqlalchemy import func, select

from app.api.v1.websocket import websocket_endpoint
from app.core.database import AsyncSessionLocal, engine
from app.domain.enums import DeviceStatus, DeviceType, ProcessingStatus, UserRole
from app.main import app
from app.models.audit_log import AuditLog
from app.models.device import Device
from app.models.device_event import DeviceEvent
from app.models.device_latest_state import DeviceLatestState
from app.models.location_sample import LocationSample
from app.models.telemetry_message import TelemetryMessage
from app.schemas.auth import UserCreate
from app.services.mqtt_service import mqtt_service
from app.services.presence_service import PresenceService
from app.services.realtime_service import realtime_service
from app.services.system_settings_service import system_settings_service
from app.services.user_service import UserService


ADMIN_PASSWORD = "admin-pass-2026"
USER_PASSWORD = "viewer-pass-2026"


class _BroadcastSocket:
    def __init__(self):
        self.messages: list[dict] = []

    async def send_json(self, message):
        self.messages.append(message)


class _EndpointSocket:
    def __init__(self, incoming):
        self.incoming = iter(incoming)
        self.messages: list[dict] = []
        self.close_code = None
        self.accepted = False

    async def accept(self):
        self.accepted = True

    async def receive_text(self):
        try:
            return next(self.incoming)
        except StopIteration as exc:
            raise WebSocketDisconnect() from exc

    async def send_json(self, message):
        self.messages.append(message)

    async def close(self, code):
        self.close_code = code


async def _create_accounts_and_device():
    async with AsyncSessionLocal() as db:
        admin = await UserService.create_account(
            db,
            UserCreate(
                username="settings_admin",
                password=ADMIN_PASSWORD,
                full_name="Quản trị Settings",
                role=UserRole.ADMIN,
            ),
            actor_user_id=None,
        )
        await UserService.create_account(
            db,
            UserCreate(
                username="settings_viewer",
                password=USER_PASSWORD,
                full_name="Người xem Settings",
                role=UserRole.USER,
            ),
            actor_user_id=admin.id,
        )
        device = Device(
            device_code="SETTINGS-SMOKE-001",
            name="Thiết bị mô phỏng Settings",
            device_type=DeviceType.VEHICLE,
            status=DeviceStatus.ACTIVE,
        )
        db.add(device)
        await db.commit()
        await db.refresh(device)
        return device.id


async def _login(client, username, password):
    response = await client.post(
        "/api/v1/auth/login",
        json={"username": username, "password": password},
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


async def _exercise_api(device_id):
    transport = httpx.ASGITransport(app=app)
    broadcast_socket = _BroadcastSocket()
    await realtime_service.connect(broadcast_socket, already_accepted=True)
    try:
        async with httpx.AsyncClient(
            transport=transport,
            base_url="http://settings.test",
        ) as client:
            admin_token = await _login(
                client,
                "settings_admin",
                ADMIN_PASSWORD,
            )
            user_token = await _login(
                client,
                "settings_viewer",
                USER_PASSWORD,
            )
            admin_headers = {"Authorization": f"Bearer {admin_token}"}
            user_headers = {"Authorization": f"Bearer {user_token}"}

            assert (
                await client.get("/api/v1/system/settings", headers=user_headers)
            ).status_code == 200
            assert (
                await client.get("/api/v1/system/settings", headers=admin_headers)
            ).status_code == 200
            assert (
                await client.get("/api/v1/system/settings")
            ).status_code == 401
            assert (
                await client.patch(
                    "/api/v1/system/settings",
                    headers=user_headers,
                    json={"movement_threshold_mps": 1.0},
                )
            ).status_code == 403
            assert (
                await client.patch(
                    "/api/v1/system/settings",
                    headers=admin_headers,
                    json={"offline_timeout_seconds": 29},
                )
            ).status_code == 422

            patched = await client.patch(
                "/api/v1/system/settings",
                headers=admin_headers,
                json={"movement_threshold_mps": 1.0},
            )
            assert patched.status_code == 200, patched.text
            assert patched.json() == {
                "offline_timeout_seconds": 300,
                "movement_threshold_mps": 1.0,
                "default_gap_threshold_seconds": 300,
            }

            await client.patch(
                "/api/v1/auth/settings",
                headers=user_headers,
                json={
                    "preferences": {
                        "map_type": "street",
                        "speed_unit": "kmh",
                        "existing_key": "keep",
                    }
                },
            )
            merged = await client.patch(
                "/api/v1/auth/settings",
                headers=user_headers,
                json={"preferences": {"map_type": "satellite"}},
            )
            assert merged.status_code == 200, merged.text
            assert merged.json()["preferences"] == {
                "map_type": "satellite",
                "speed_unit": "kmh",
                "existing_key": "keep",
            }

            # Endpoint WebSocket được gọi trực tiếp với token thật để kiểm tra
            # AUTH/AUTH_OK và heartbeat PING/PONG mà không mở broker MQTT.
            endpoint_socket = _EndpointSocket(
                [
                    json.dumps(
                        {"type": "AUTH", "access_token": admin_token}
                    ),
                    json.dumps({"type": "PING"}),
                ]
            )
            await websocket_endpoint(endpoint_socket)
            assert endpoint_socket.accepted
            assert [message["type"] for message in endpoint_socket.messages] == [
                "AUTH_OK",
                "PONG",
            ]
            invalid_socket = _EndpointSocket([json.dumps({"type": "PING"})])
            await websocket_endpoint(invalid_socket)
            assert invalid_socket.close_code == 4401

        assert any(
            message.get("type") == "SYSTEM_SETTINGS_UPDATED"
            and message["settings"]["movement_threshold_mps"] == 1.0
            for message in broadcast_socket.messages
        )

        await _exercise_mqtt_and_presence(device_id, broadcast_socket)
        return broadcast_socket.messages
    finally:
        realtime_service.disconnect(broadcast_socket)


async def _exercise_mqtt_and_presence(device_id, socket):
    base_time = datetime(2026, 8, 21, 6, 0, tzinfo=timezone.utc)
    for index, speed in enumerate([0.4, 0.8, 1.0, 1.2, 1.4, 0.9]):
        await mqtt_service.process_message(
            "v_monitor/telemetry/SETTINGS-SMOKE-001",
            json.dumps(
                {
                    "message_id": f"settings-{index}",
                    "measured_at": (
                        base_time + timedelta(seconds=index)
                    ).isoformat(),
                    "latitude": 21.0285 + index / 10000,
                    "longitude": 105.8542 + index / 10000,
                    "speed_mps": speed,
                    "battery_pct": 80,
                }
            ),
            qos=1,
        )

    async with AsyncSessionLocal() as db:
        event_types = list(
            (
                await db.execute(
                    select(DeviceEvent.event_type).where(
                        DeviceEvent.device_id == device_id
                    )
                )
            ).scalars()
        )
        assert event_types.count("MOVEMENT_STARTED") == 1
        assert event_types.count("MOVEMENT_STOPPED") == 1
        latest = await db.get(DeviceLatestState, device_id)
        newest_time = latest.latest_measured_at
        assert latest.current_speed_mps == 0.9

    # Gói đến trễ đi qua chính MQTTService: vẫn lưu telemetry/location nhưng
    # không được ghi đè latest state.
    await mqtt_service.process_message(
        "v_monitor/telemetry/SETTINGS-SMOKE-001",
        json.dumps(
            {
                "message_id": "settings-late",
                "measured_at": (base_time - timedelta(minutes=1)).isoformat(),
                "latitude": 20.0,
                "longitude": 104.0,
                "speed_mps": 5.0,
            }
        ),
        qos=1,
    )

    controlled_now = datetime(2026, 8, 21, 7, 0, tzinfo=timezone.utc)
    async with AsyncSessionLocal() as db:
        latest = await db.get(DeviceLatestState, device_id)
        assert latest.latest_measured_at == newest_time
        assert latest.current_speed_mps == 0.9
        location_count = await db.scalar(
            select(func.count(LocationSample.id)).where(
                LocationSample.device_id == device_id
            )
        )
        telemetry_count = await db.scalar(
            select(func.count(TelemetryMessage.id)).where(
                TelemetryMessage.device_id == device_id,
                TelemetryMessage.processing_status == ProcessingStatus.PROCESSED,
            )
        )
        assert location_count == 7
        assert telemetry_count == 7
        latest.last_seen_at = controlled_now - timedelta(seconds=301)
        latest.is_online = True
        await db.commit()

    changed_first = await PresenceService().mark_stale_devices_offline(
        now=controlled_now
    )
    changed_second = await PresenceService().mark_stale_devices_offline(
        now=controlled_now
    )
    assert changed_first == 1
    assert changed_second == 0
    assert any(
        message.get("type") == "DEVICE_UPDATE" for message in socket.messages
    )
    assert any(
        message.get("type") == "DEVICE_EVENT" for message in socket.messages
    )


async def _verify_database_state():
    system_settings_service.invalidate_cache()
    runtime = await system_settings_service.get_runtime_settings()
    assert runtime.movement_threshold_mps == 1.0
    async with AsyncSessionLocal() as db:
        audits = list(
            (
                await db.execute(
                    select(AuditLog).where(
                        AuditLog.action == "SYSTEM_SETTINGS_UPDATED"
                    )
                )
            ).scalars()
        )
        assert len(audits) == 1
        assert audits[0].actor_user_id is not None
        assert audits[0].old_value["movement_threshold_mps"] == 0.5
        assert audits[0].new_value["movement_threshold_mps"] == 1.0


async def main():
    device_id = await _create_accounts_and_device()
    messages = await _exercise_api(device_id)
    await _verify_database_state()
    await engine.dispose()
    print(
        json.dumps(
            {
                "api_admin_get": 200,
                "api_user_get": 200,
                "api_user_patch": 403,
                "api_validation": 422,
                "movement_started": 1,
                "movement_stopped": 1,
                "offline_events": 1,
                "late_packet_preserved": True,
                "websocket_types": sorted(
                    {message.get("type") for message in messages}
                ),
                "persistence_after_cache_reload": True,
                "preferences_merge": True,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    asyncio.run(main())
