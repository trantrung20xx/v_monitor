"""Mô phỏng trên DB mới, MQTT/HTTP/WebSocket qua TCP thật; không sửa DB gốc.

Chạy từ root: .venv/Scripts/python.exe backend/tests/integration_realtime_performance.py
Thêm --keep-server để kiểm tra Flutter trên API thử nghiệm sau khi các assert đạt.
Broker chạy bằng uv --with amqtt trong môi trường riêng.
"""
import argparse
import asyncio
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
ARTIFACTS = ROOT.parent / "build" / "performance"
PASSWORD = "PerfTest-only-2026!"


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


async def provision(args):
    import asyncpg
    from sqlalchemy.engine import make_url
    from app.core.config import settings
    base = make_url(settings.database_url)
    if base.host not in {"localhost", "127.0.0.1", "::1"}:
        raise RuntimeError("Only a local PostgreSQL server may create the isolated test database")
    name = "vmonitor_perf_test_" + uuid.uuid4().hex[:12]
    connection = await asyncpg.connect(host=base.host, port=base.port or 5432,
        user=base.username, password=base.password, database=base.database, timeout=5)
    try:
        await connection.execute(f'CREATE DATABASE "{name}"')
    finally:
        await connection.close()
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    run_dir = ARTIFACTS / name
    run_dir.mkdir()
    overrides = {
        "DATABASE_URL": base.set(database=name).render_as_string(hide_password=False),
        "JWT_SECRET": uuid.uuid4().hex + uuid.uuid4().hex,
        "AUTH_REQUIRED": "true", "API_RELOAD": "false", "API_HOST": "127.0.0.1",
        "API_PORT": str(free_port()), "MQTT_HOST": "127.0.0.1", "MQTT_PORT": str(free_port()),
        "MQTT_USERNAME": "", "MQTT_PASSWORD": "", "MQTT_USE_TLS": "false",
        "MQTT_TOPIC_PREFIX": "vmonitor_perf/telemetry", "MQTT_CLIENT_ID": "perf_backend_" + uuid.uuid4().hex[:8],
        "GEOCODING_PROVIDER": "photon", "GEOCODING_BASE_URL": f"http://127.0.0.1:{free_port()}",
        "GEOCODING_MAX_PENDING": "4", "GEOCODING_REQUEST_TIMEOUT_SECONDS": "0.4",
        "GEOCODING_RETRY_ATTEMPTS": "1", "REALTIME_SEND_TIMEOUT_SECONDS": "0.5",
        "REALTIME_OUTBOX_RETRY_SECONDS": "0.1", "REALTIME_OUTBOX_POLL_SECONDS": "0.05",
        "PYTHONIOENCODING": "utf-8", "PERF_RUN_DIR": str(run_dir),
    }
    # File này ở build/ đã ignore; không in URL/password ra log.
    (run_dir / "environment.json").write_text(json.dumps(overrides), encoding="utf-8")
    env = {**os.environ, **overrides}
    for command in (["upgrade", "head"], ["downgrade", "d8e9f0a1b2c3"], ["upgrade", "head"]):
        result = subprocess.run([sys.executable, "-m", "alembic", *command], cwd=ROOT, env=env,
            capture_output=True, text=True, encoding="utf-8")
        (run_dir / ("migration_" + "_".join(command) + ".log")).write_text(result.stdout + result.stderr, encoding="utf-8")
        if result.returncode:
            raise RuntimeError("Migration failed; see isolated run migration log")
    print(json.dumps({"database": name, "api_port": overrides["API_PORT"], "artifacts": str(run_dir)}), flush=True)
    child_args = [sys.executable, "-u", str(Path(__file__).resolve()), "--exercise", "--devices", str(args.devices)]
    if args.keep_server:
        child_args.append("--keep-server")
    output = (run_dir / "exercise.log").open("w", encoding="utf-8")
    process = subprocess.Popen(child_args, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    try:
        announced = False
        while process.poll() is None:
            if not announced and (run_dir / "results.json").exists():
                print((run_dir / "results.json").read_text(encoding="utf-8"), flush=True)
                print("TEST_UI_API_READY http://127.0.0.1:" + overrides["API_PORT"], flush=True)
                announced = True
            await asyncio.sleep(0.5)
        output.close()
        print((run_dir / "exercise.log").read_text(encoding="utf-8")[-8000:], flush=True)
        return process.returncode
    finally:
        if process.poll() is None:
            process.terminate()


async def exercise(args):
    import httpx
    import uvicorn
    from websockets.asyncio.client import connect
    import paho.mqtt.client as mqtt
    from sqlalchemy import func, insert, select, text, update
    from app.core.config import settings
    from app.core.database import AsyncSessionLocal, engine
    from app.core.security import hash_password
    from app.domain.enums import DeviceStatus, DeviceType, UserRole
    from app.models.device import Device
    from app.models.device_latest_state import DeviceLatestState
    from app.models.device_event import DeviceEvent
    from app.models.location_sample import LocationSample
    from app.models.telemetry_message import TelemetryMessage
    from app.models.user_account import UserAccount
    from app.models.realtime_outbox import RealtimeOutbox
    from app.services.realtime_outbox_service import realtime_outbox_service, stage_device_events
    from app.services.realtime_service import realtime_service
    from app.services.mqtt_service import mqtt_service
    from app.main import app
    from sqlalchemy.engine import make_url
    database_name = make_url(settings.database_url).database
    assert database_name.startswith("vmonitor_perf_test_")
    run_dir = Path(os.environ["PERF_RUN_DIR"])
    report = {"database": database_name, "device_ids": args.devices, "transport": "real MQTT broker + PostgreSQL/PostGIS + HTTP + WebSocket on loopback"}
    ids = [uuid.uuid4() for _ in range(args.devices)]
    async with AsyncSessionLocal() as db:
        db.add(UserAccount(username="perf_admin", full_name="Kiểm thử hiệu năng", role=UserRole.ADMIN,
            password_hash=hash_password(PASSWORD)))
        await db.execute(insert(Device), [{"id": id_, "device_code": f"PERF-{i:05d}",
            "name": f"Thiết bị mô phỏng {i:05d}", "device_type": DeviceType.VEHICLE,
            "status": DeviceStatus.ACTIVE, "is_enabled": True} for i, id_ in enumerate(ids)])
        await db.execute(insert(DeviceLatestState), [{"device_id": id_} for id_ in ids])
        await db.commit()

    provider_delay = 0.0
    async def provider(reader, writer):
        try:
            await reader.readuntil(b"\r\n\r\n")
            await asyncio.sleep(provider_delay)
            body = json.dumps({"features": [{"properties": {"street": "Đường kiểm thử", "city": "Hồ Chí Minh"}}]}).encode()
            writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)
            await writer.drain()
        except (ConnectionError, asyncio.IncompleteReadError):
            pass
        finally:
            writer.close()
            await writer.wait_closed()
    from urllib.parse import urlparse
    provider_server = await asyncio.start_server(provider, "127.0.0.1", urlparse(settings.geocoding_base_url).port)
    broker_log = (run_dir / "broker.log").open("w", encoding="utf-8")
    broker = subprocess.Popen(["uv", "run", "--python", "3.13", "--with", "amqtt", "python",
        str(ROOT / "tests" / "performance_broker.py")], env={**os.environ, "PERF_MQTT_PORT": str(settings.mqtt_port)},
        stdout=broker_log, stderr=subprocess.STDOUT,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=settings.api_port,
        log_level="warning", access_log=False))
    server_task = asyncio.create_task(server.serve())
    publisher = None
    receiver = None
    legacy_receiver = None
    legacy_ws = None
    ws = None
    url = f"http://127.0.0.1:{settings.api_port}"
    try:
        async with httpx.AsyncClient(base_url=url, timeout=10) as client:
            for _ in range(200):
                if server.started and mqtt_service.health_snapshot()["connected"]:
                    break
                await asyncio.sleep(0.1)
            assert server.started and mqtt_service.health_snapshot()["connected"], "Backend/broker not ready"
            response = await client.post("/api/v1/auth/login", json={"username": "perf_admin", "password": PASSWORD})
            assert response.status_code == 200, response.status_code
            token = response.json()["access_token"]
            client.headers["Authorization"] = "Bearer " + token
            ws = await connect(f"ws://127.0.0.1:{settings.api_port}/api/v1/ws", max_size=8_000_000)
            await ws.send(json.dumps({"type": "AUTH", "access_token": token, "realtime_batches": True}))
            assert json.loads(await ws.recv())["type"] == "AUTH_OK"
            updates = {}
            events = {}
            frames = 0
            async def receive():
                nonlocal frames
                async for raw in ws:
                    message = json.loads(raw)
                    frames += 1
                    if message["type"] == "DEVICE_UPDATES":
                        for d in message["devices"]:
                            updates[d["id"]] = d
                    elif message["type"] == "REALTIME_BATCH":
                        for item in message["messages"]:
                            if item["type"] == "DEVICE_EVENT":
                                events[item["event"]["id"]] = item["event"]
            receiver = asyncio.create_task(receive())
            legacy_updates = {}
            legacy_events = {}
            legacy_ws = await connect(f"ws://127.0.0.1:{settings.api_port}/api/v1/ws", max_size=8_000_000)
            await legacy_ws.send(json.dumps({"type": "AUTH", "access_token": token}))
            assert json.loads(await legacy_ws.recv())["type"] == "AUTH_OK"
            async def receive_legacy():
                async for raw in legacy_ws:
                    item = json.loads(raw)
                    if item["type"] == "DEVICE_UPDATE":
                        legacy_updates[item["device"]["id"]] = item["device"]
                    elif item["type"] == "DEVICE_EVENT":
                        legacy_events[item["event"]["id"]] = item["event"]
            legacy_receiver = asyncio.create_task(receive_legacy())

            publisher = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="perf_publisher_" + uuid.uuid4().hex[:8])
            publisher.max_inflight_messages_set(1000)
            publisher.connect("127.0.0.1", settings.mqtt_port)
            publisher.loop_start()
            now = datetime.now(timezone.utc)
            started = time.perf_counter()
            expected = args.devices * 2
            def publish():
                sent = []
                for step in range(2):
                    for index in range(args.devices):
                        payload = {"message_id": f"sample-{index}-{step}",
                            "measured_at": (now + timedelta(seconds=step)).isoformat(),
                            "latitude": 10.77 + (index % 100) * 0.0001,
                            "longitude": 106.69 + (index // 100) * 0.0001 + step * 0.00001,
                            "speed_mps": step * 2.0, "battery_pct": 80}
                        sent.append(publisher.publish(f"{settings.mqtt_topic_prefix}/PERF-{index:05d}", json.dumps(payload), qos=1))
                for message in sent:
                    message.wait_for_publish(timeout=30)
                    assert message.is_published()
            await asyncio.to_thread(publish)
            deadline = time.monotonic() + 180
            while time.monotonic() < deadline:
                if mqtt_service.health_snapshot()["processed_count"] >= expected and len(updates) == args.devices:
                    break
                await asyncio.sleep(0.1)
            elapsed = time.perf_counter() - started
            async with AsyncSessionLocal() as db:
                counts = {name: await db.scalar(select(func.count()).select_from(model)) for name, model in (
                    ("locations", LocationSample), ("telemetry", TelemetryMessage), ("events", DeviceEvent))}
                newest = await db.scalar(select(func.count()).select_from(DeviceLatestState).where(DeviceLatestState.current_speed_mps == 2))
            assert counts["locations"] == expected and counts["telemetry"] == expected, counts
            assert newest == args.devices, newest
            for _ in range(200):
                if (len(events) >= expected and all(d["current_speed_mps"] == 2 for d in updates.values())
                    and len(legacy_events) == expected and len(legacy_updates) == args.devices
                    and all(d["current_speed_mps"] == 2 for d in legacy_updates.values())):
                    break
                await asyncio.sleep(0.05)
            assert len(events) == expected, len(events)
            assert len(updates) == args.devices and all(d["current_speed_mps"] == 2 for d in updates.values())
            assert len(legacy_events) == expected and len(legacy_updates) == args.devices
            assert all(d["current_speed_mps"] == 2 for d in legacy_updates.values())
            report["ingestion"] = {**counts, "latest_states": newest, "elapsed_seconds": round(elapsed, 3),
                "observed_messages_per_second": round(expected / elapsed, 1), "websocket_frames": frames,
                "distinct_websocket_events": len(events), "dropped": mqtt_service.health_snapshot()["dropped_count"]}
            report["legacy_websocket"] = {"events": len(legacy_events), "latest_states": len(legacy_updates)}
            assert report["ingestion"]["dropped"] == 0
            print(json.dumps({"ingestion": report["ingestion"]}), flush=True)

            # Dừng bộ phát, commit sự kiện, thử rollback, rồi khởi động bộ phát mới.
            await realtime_outbox_service.stop()
            replay_id = uuid.uuid4()
            rollback_id = uuid.uuid4()
            async with AsyncSessionLocal() as db:
                event = DeviceEvent(id=replay_id, device_id=ids[0], event_type="TEST_REPLAY",
                    occurred_at=datetime.now(timezone.utc), source="test", description="Kiểm tra phát lại")
                db.add(event)
                stage_device_events(db, [event])
                await db.commit()
            async with AsyncSessionLocal() as db:
                event = DeviceEvent(id=rollback_id, device_id=ids[0], event_type="TEST_ROLLBACK",
                    occurred_at=datetime.now(timezone.utc), source="test")
                db.add(event); stage_device_events(db, [event]); await db.flush(); await db.rollback()
                assert await db.get(DeviceEvent, rollback_id) is None
            await realtime_outbox_service.start()
            for _ in range(100):
                if str(replay_id) in events:
                    break
                await asyncio.sleep(0.05)
            assert str(replay_id) in events and str(rollback_id) not in events
            report["outbox_replay_and_rollback"] = "passed"

            # Provider chậm: request có token, DB không bị giữ trong lúc chờ địa chỉ.
            provider_delay = 1.0
            requests = [asyncio.create_task(client.get("/api/v1/geocoding/reverse", params={"latitude": i / 10, "longitude": 106})) for i in range(20)]
            await asyncio.sleep(0.1)
            api_started = time.perf_counter()
            response = await client.get("/api/v1/devices/", params={"limit": 10})
            api_elapsed = time.perf_counter() - api_started
            async with AsyncSessionLocal() as db:
                held_auth = await db.scalar(text("SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND state='idle in transaction' AND query LIKE '%user_accounts%'"))
            geocoding_results = await asyncio.gather(*requests)
            assert response.status_code == 200 and api_elapsed < 1.0
            assert held_auth == 0, held_auth
            assert all(r.status_code == 503 for r in geocoding_results)
            report["slow_geocoding"] = {"requests": 20, "address_status": 503, "devices_api_seconds": round(api_elapsed, 3), "held_auth_transactions": held_auth}
            provider_delay = 0
            response = await client.get("/api/v1/geocoding/reverse", params={"latitude": 10.7, "longitude": 106.7})
            assert response.status_code == 200
            response = await client.patch("/api/v1/system/settings", json={"dashboard_update_interval_ms": 750})
            assert response.status_code == 200 and response.json()["dashboard_update_interval_ms"] == 750
            invalid = await client.patch("/api/v1/system/settings", json={"dashboard_update_interval_ms": 1})
            assert invalid.status_code == 422
            report["runtime_interval_persistence_validation"] = "passed"
            (run_dir / "results.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
            print("REAL_INTEGRATION_CHECKS_PASSED " + str(run_dir / "results.json"), flush=True)
            if args.keep_server:
                print(f"TEST_UI_API_READY {url} username=perf_admin", flush=True)
                while not (run_dir / "stop-server").exists():
                    await asyncio.sleep(0.5)
    finally:
        if publisher:
            publisher.disconnect(); publisher.loop_stop()
        if ws:
            await ws.close()
        if legacy_ws:
            await legacy_ws.close()
        if legacy_receiver:
            await asyncio.gather(legacy_receiver, return_exceptions=True)
        if receiver:
            await asyncio.gather(receiver, return_exceptions=True)
        server.should_exit = True
        await server_task
        provider_server.close(); await provider_server.wait_closed()
        (run_dir / "stop-broker").touch()
        await asyncio.to_thread(broker.wait, 15)
        broker_log.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--exercise", action="store_true")
    parser.add_argument("--keep-server", action="store_true")
    parser.add_argument("--devices", type=int, default=5000)
    options = parser.parse_args()
    if not 1 <= options.devices <= 5000:
        parser.error("devices must be between 1 and 5000")
    if options.exercise:
        asyncio.run(exercise(options))
    else:
        sys.exit(asyncio.run(provision(options)))
