"""Kiểm tra HTTP/reconnect và lease outbox trên server mô phỏng đang giữ mở."""
import asyncio
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import sys
import uuid


async def run(run_dir):
    config = json.loads((run_dir / "environment.json").read_text(encoding="utf-8"))
    os.environ.update(config)
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    import httpx
    from websockets.asyncio.client import connect
    from sqlalchemy import select
    from sqlalchemy.engine import make_url
    from app.core.database import AsyncSessionLocal, engine
    from app.models.realtime_outbox import RealtimeOutbox
    from app.models.device_event import DeviceEvent
    from app.services.realtime_outbox_service import stage_device_events
    assert make_url(config["DATABASE_URL"]).database.startswith("vmonitor_perf_test_")
    url = "http://127.0.0.1:" + config["API_PORT"]
    async with httpx.AsyncClient(base_url=url, timeout=10) as client:
        response = await client.post("/api/v1/auth/login", json={"username": "perf_admin", "password": "PerfTest-only-2026!"})
        response.raise_for_status()
        token = response.json()["access_token"]
        client.headers["Authorization"] = "Bearer " + token
        async def open_socket():
            ws = await connect(url.replace("http:", "ws:") + "/api/v1/ws")
            await ws.send(json.dumps({"type": "AUTH", "access_token": token, "realtime_batches": True}))
            assert json.loads(await ws.recv())["type"] == "AUTH_OK"
            return ws
        ws = await open_socket()
        response = await client.get("/api/v1/devices/", params={"limit": 1})
        response.raise_for_status()
        device_id = response.json()[0]["id"]
        await ws.close()
        response = await client.post("/api/v1/tracking/", json={"device_id": device_id,
            "measured_at": datetime.now(timezone.utc).isoformat(), "latitude": 10.78,
            "longitude": 106.70, "speed_mps": 3.5, "source": "reconnect-test"})
        assert response.status_code == 200, response.text
        ws = await open_socket()
        response = await client.get("/api/v1/devices/", params={"limit": 5000})
        snapshot = {d["id"]: d for d in response.json()}
        assert snapshot[device_id]["current_speed_mps"] == 3.5
        response = await client.get(f"/api/v1/tracking/{device_id}/history/range", params={
            "from": (datetime.now(timezone.utc) - timedelta(days=1)).isoformat(),
            "to": (datetime.now(timezone.utc) + timedelta(seconds=5)).isoformat()})
        assert response.status_code == 200, response.text
        history = response.json()
        assert history["total_count"] == 3 and len(history["samples"]) == 3 and not history["truncated"], history
        # Mô phỏng worker cũ đã claim rồi chết: token vẫn còn, lease hết hạn phải nhận lại.
        event_id = uuid.uuid4()
        async with AsyncSessionLocal() as db:
            event = DeviceEvent(id=event_id, device_id=uuid.UUID(device_id), event_type="LEASE_RECOVERY",
                occurred_at=datetime.now(timezone.utc), source="test")
            db.add(event); stage_device_events(db, [event])
            row = next(item for item in db.new if isinstance(item, RealtimeOutbox))
            row.claim_token = uuid.uuid4()
            row.available_at = datetime.now(timezone.utc) + timedelta(seconds=0.5)
            row_id = row.id
            await db.flush()
            row_id = row.id
            await db.commit()
        async with asyncio.timeout(10):
            while True:
                frame = json.loads(await ws.recv())
                if any(item.get("event", {}).get("id") == str(event_id) for item in frame.get("messages", [])):
                    break
        await asyncio.sleep(0.2)
        async with AsyncSessionLocal() as db:
            assert await db.get(RealtimeOutbox, row_id) is None
            assert await db.get(DeviceEvent, event_id) is not None
        await ws.close()
        health = await client.get("/health")
        assert health.json()["status"] == "ok", health.text
    await engine.dispose()
    result = {"network_reconnect_rest_catchup": "passed", "rest_gps_history_samples": 3,
        "expired_outbox_lease_replayed": "passed", "health": "ok"}
    (run_dir / "recovery_results.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result))


if __name__ == "__main__":
    asyncio.run(run(Path(sys.argv[1]).resolve()))
