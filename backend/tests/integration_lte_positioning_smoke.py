"""Kiểm tra PostgreSQL/PostGIS thật cho LTE cell positioning, không dùng broker ngoài."""
import asyncio
import json
import uuid

import httpx
from sqlalchemy import func, select

from app.core.database import AsyncSessionLocal, engine
from app.domain.enums import DeviceType, ProcessingStatus, UserRole
from app.main import app
from app.models.cell_observation import CellObservation
from app.models.cell_position_estimate import CellPositionEstimate
from app.models.cell_tower import CellTower
from app.models.device_latest_state import DeviceLatestState
from app.models.location_sample import LocationSample
from app.models.telemetry_message import TelemetryMessage
from app.schemas.device import DeviceCreate
from app.services.device_service import DeviceService
from app.services.mqtt_service import mqtt_service
from app.schemas.auth import UserCreate
from app.services.user_service import UserService


DEVICE_CODE = "LTE-SMOKE-001"
TOPIC = f"v_monitor/telemetry/{DEVICE_CODE}"


def _tower(*, cell_id: int, latitude: float, longitude: float, site_key: str) -> CellTower:
    return CellTower(
        rat="LTE",
        mcc="452",
        mnc="04",
        tac=12345,
        cell_id=cell_id,
        latitude=latitude,
        longitude=longitude,
        location=f"SRID=4326;POINT({longitude} {latitude})",
        site_key=site_key,
        accuracy_m=150,
        source="integration-smoke",
        is_active=True,
    )


async def run() -> None:
    async with AsyncSessionLocal() as db:
        created = await DeviceService.create_device(
            db,
            DeviceCreate(
                device_code=DEVICE_CODE,
                name="Thiết bị kiểm tra LTE",
                device_type=DeviceType.OTHER,
            ),
        )
        device_id = uuid.UUID(created["id"])
        db.add_all(
            [
                _tower(cell_id=1001, latitude=21.0280, longitude=105.8500, site_key="site-a"),
                _tower(cell_id=1002, latitude=21.0300, longitude=105.8560, site_key="site-b"),
                _tower(cell_id=1003, latitude=21.0270, longitude=105.8540, site_key="site-c"),
            ]
        )
        await db.commit()

    payload = {
        "message_id": "lte-smoke-001",
        "measured_at": "2026-09-25T10:00:00Z",
        "cellular": {
            "rat": "LTE",
            "serving": {"mcc": "452", "mnc": "04", "tac": 12345, "cell_id": 1001, "rsrp_dbm": -89},
            "neighbors": [
                {"mcc": "452", "mnc": "04", "tac": 12345, "cell_id": 1002, "rsrp_dbm": -94},
                {"mcc": "452", "mnc": "04", "tac": 12345, "cell_id": 1003, "rsrp_dbm": -102},
                {"pci": 311, "earfcn": 1800, "rsrp_dbm": -108},
            ],
        },
    }
    await mqtt_service.process_message(TOPIC, json.dumps(payload), qos=1)
    await mqtt_service.process_message(TOPIC, json.dumps(payload), qos=1)

    async with AsyncSessionLocal() as db:
        telemetry_count = await db.scalar(select(func.count(TelemetryMessage.id)).where(TelemetryMessage.device_id == device_id))
        observation_count = await db.scalar(select(func.count(CellObservation.id)).where(CellObservation.device_id == device_id))
        estimate = (await db.execute(select(CellPositionEstimate).where(CellPositionEstimate.device_id == device_id))).scalar_one()
        state = await db.get(DeviceLatestState, device_id)
        location_count = await db.scalar(select(func.count(LocationSample.id)).where(LocationSample.device_id == device_id))
        assert telemetry_count == 1
        assert observation_count == 4
        assert estimate.status == "ESTIMATED"
        assert estimate.latitude is not None and estimate.longitude is not None
        assert estimate.matched_cell_count == 3
        assert state is not None and state.latest_cell_estimate_id == estimate.id
        assert state.current_latitude is None and state.current_longitude is None
        assert location_count == 0
        telemetry = (await db.execute(select(TelemetryMessage).where(TelemetryMessage.device_id == device_id))).scalar_one()
        assert telemetry.processing_status == ProcessingStatus.PROCESSED
        initial_estimate_id = estimate.id

    gps_payload = {
        "message_id": "lte-smoke-gps-002",
        "measured_at": "2026-09-25T10:01:00Z",
        "latitude": 21.0250,
        "longitude": 105.8530,
        "speed_mps": 0.0,
        "cellular": payload["cellular"],
    }
    await mqtt_service.process_message(TOPIC, json.dumps(gps_payload), qos=1)

    async with AsyncSessionLocal() as db:
        state = await db.get(DeviceLatestState, device_id)
        telemetry_count = await db.scalar(select(func.count(TelemetryMessage.id)).where(TelemetryMessage.device_id == device_id))
        estimate_count = await db.scalar(select(func.count(CellPositionEstimate.id)).where(CellPositionEstimate.device_id == device_id))
        location_count = await db.scalar(select(func.count(LocationSample.id)).where(LocationSample.device_id == device_id))
        assert telemetry_count == 2
        assert estimate_count == 2
        assert location_count == 1
        assert state is not None
        assert state.current_latitude == 21.0250 and state.current_longitude == 105.8530
        assert state.latest_cell_estimate_id == initial_estimate_id

    async with AsyncSessionLocal() as db:
        await UserService.create_account(
            db,
            UserCreate(
                username="lte_smoke_viewer",
                password="lte-smoke-password",
                full_name="LTE Smoke Viewer",
                role=UserRole.USER,
            ),
            actor_user_id=None,
        )

    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://lte-smoke.test",
    ) as client:
        login = await client.post(
            "/api/v1/auth/login",
            json={"username": "lte_smoke_viewer", "password": "lte-smoke-password"},
        )
        assert login.status_code == 200, login.text
        response = await client.get(
            f"/api/v1/devices/{device_id}/estimated-position",
            headers={"Authorization": f"Bearer {login.json()['access_token']}"},
        )
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["status"] == "ESTIMATED"
        assert body["latitude"] is not None and body["longitude"] is not None

    print("LTE_POSITIONING_SMOKE=passed")
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(run())
