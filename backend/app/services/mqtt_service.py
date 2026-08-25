import asyncio
from datetime import datetime, timezone
import json
import logging
import os
import socket
from typing import Optional

import paho.mqtt.client as mqtt
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import IntegrityError

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.domain.enums import ProcessingStatus
from app.models.device import Device
from app.models.mqtt_device_sighting import MqttDeviceSighting
from app.models.telemetry_message import TelemetryMessage
from app.schemas.device import DeviceResponse
from app.schemas.tracking import LocationSampleCreate
from app.services.device_service import DeviceService
from app.services.realtime_service import realtime_service
from app.services.tracking_service import TrackingService


logger = logging.getLogger(__name__)

try:
    from paho.mqtt.enums import CallbackAPIVersion

    _HAS_CALLBACK_API_VERSION = True
except ImportError:
    CallbackAPIVersion = getattr(mqtt, "CallbackAPIVersion", None)
    _HAS_CALLBACK_API_VERSION = CallbackAPIVersion is not None


def _create_mqtt_client(client_id: str) -> mqtt.Client:
    """Khởi tạo MQTT client tương thích paho-mqtt 1.x và 2.x."""
    if _HAS_CALLBACK_API_VERSION and CallbackAPIVersion is not None:
        return mqtt.Client(CallbackAPIVersion.VERSION2, client_id=client_id)
    return mqtt.Client(client_id=client_id)


def _mqtt_client_id() -> str:
    configured = settings.mqtt_client_id
    if configured:
        return configured

    # Hostname phân biệt các máy hoặc container; PID phân biệt nhiều tiến trình
    # backend trên cùng một máy. Client id duy nhất ngăn broker ngắt kết nối một
    # instance khi instance khác đăng nhập bằng cùng định danh.
    hostname = "".join(
        character if character.isalnum() or character in {"-", "_"} else "-"
        for character in socket.gethostname()
    ).strip("-")
    safe_hostname = hostname or "host"
    return f"v_monitor_backend_{safe_hostname}_{os.getpid()}"[:128]


def _parse_measured_at(raw_value, fallback: datetime) -> datetime:
    if raw_value is None:
        return fallback
    value = datetime.fromisoformat(str(raw_value).replace("Z", "+00:00"))
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _device_code_from_topic(topic: str) -> Optional[str]:
    prefix_parts = settings.mqtt_topic_prefix.split("/")
    topic_parts = topic.split("/")
    if (
        len(topic_parts) != len(prefix_parts) + 1
        or topic_parts[: len(prefix_parts)] != prefix_parts
    ):
        return None
    device_code = topic_parts[-1]
    if not device_code or device_code != device_code.strip() or len(device_code) > 50:
        return None
    return device_code


class MQTTService:
    def __init__(self):
        self._client_id = _mqtt_client_id()
        self.client = _create_mqtt_client(client_id=self._client_id)
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
        self.client.on_disconnect = self.on_disconnect
        self.loop: Optional[asyncio.AbstractEventLoop] = None
        self.queue: Optional[asyncio.Queue[tuple[str, str, int]]] = None
        self.workers: list[asyncio.Task] = []
        self._started = False
        self._connected = False
        self._subscribed = False
        self._received_count = 0
        self._processed_count = 0
        self._unknown_device_count = 0
        self._disabled_device_count = 0
        self._dropped_count = 0
        self._last_received_at: Optional[datetime] = None
        self._last_processed_at: Optional[datetime] = None

    def on_connect(self, client, userdata, flags, reason_code, properties=None):
        if hasattr(reason_code, "is_failure"):
            is_success = not reason_code.is_failure
        elif isinstance(reason_code, int):
            is_success = reason_code == 0
        else:
            is_success = str(reason_code).lower() in {"0", "success"}

        if is_success:
            self._connected = True
            logger.info("Đã kết nối thành công tới MQTT broker")
            result, _ = client.subscribe(
                f"{settings.mqtt_topic_prefix}/#",
                qos=1,
            )
            self._subscribed = result == mqtt.MQTT_ERR_SUCCESS
            if not self._subscribed:
                logger.error("Không thể đăng ký topic MQTT, mã lỗi: %s", result)
        else:
            self._connected = False
            self._subscribed = False
            logger.error("Kết nối MQTT thất bại, mã lỗi: %s", reason_code)

    def _enqueue_message(self, topic: str, payload: str, qos: int) -> None:
        if self.queue is None:
            return
        try:
            self.queue.put_nowait((topic, payload, qos))
        except asyncio.QueueFull:
            self._dropped_count += 1
            # Hàng đợi hữu hạn bảo vệ bộ nhớ khi lưu lượng vượt quá khả năng xử lý.
            logger.error(
                "Hàng đợi MQTT đã đầy (%s bản tin), bỏ bản tin trên topic %s",
                settings.mqtt_queue_size,
                topic,
            )

    def on_message(self, client, userdata, msg):
        self._received_count += 1
        self._last_received_at = datetime.now(timezone.utc)
        try:
            payload = msg.payload.decode("utf-8")
        except UnicodeDecodeError:
            logger.warning("Bỏ qua bản tin MQTT không phải UTF-8 trên %s", msg.topic)
            return
        if self.loop and self.loop.is_running():
            self.loop.call_soon_threadsafe(
                self._enqueue_message,
                msg.topic,
                payload,
                int(getattr(msg, "qos", 0)),
            )

    def on_disconnect(self, client, userdata, flags, reason_code=None, properties=None):
        self._connected = False
        self._subscribed = False
        logger.info("Đã ngắt kết nối khỏi MQTT broker")

    async def _worker(self, worker_index: int) -> None:
        assert self.queue is not None
        while True:
            topic, payload, qos = await self.queue.get()
            try:
                await self.process_message(topic, payload, qos=qos)
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Worker MQTT %s gặp lỗi ngoài dự kiến", worker_index)
            finally:
                self.queue.task_done()

    async def process_message(
        self,
        topic: str,
        payload_str: str,
        *,
        qos: int = 0,
    ) -> None:
        try:
            data = json.loads(payload_str)
        except json.JSONDecodeError:
            logger.warning("Bỏ qua bản tin MQTT không phải JSON hợp lệ")
            return
        if not isinstance(data, dict):
            logger.warning("Bỏ qua bản tin MQTT vì payload không phải object")
            return

        device_code = _device_code_from_topic(topic)
        if device_code is None:
            logger.warning("Bỏ qua bản tin MQTT vì topic không đúng định dạng")
            return

        async with AsyncSessionLocal() as db:
            device_result = await db.execute(
                select(Device.id, Device.is_enabled).where(
                    Device.device_code == device_code
                )
            )
            device_row = device_result.one_or_none()
            if device_row is None:
                now = datetime.now(timezone.utc)
                statement = insert(MqttDeviceSighting).values(
                    device_code=device_code,
                    first_seen_at=now,
                    last_seen_at=now,
                    message_count=1,
                    last_topic=topic[:255],
                )
                statement = statement.on_conflict_do_update(
                    index_elements=[MqttDeviceSighting.device_code],
                    set_={
                        "last_seen_at": now,
                        "message_count": MqttDeviceSighting.message_count + 1,
                        "last_topic": topic[:255],
                    },
                )
                await db.execute(statement)
                await db.commit()
                self._unknown_device_count += 1
                logger.warning(
                    "Thiết bị MQTT '%s' chưa được đăng ký; đã ghi nhận vào danh sách chờ",
                    device_code,
                )
                return

            device_id, is_enabled = device_row
            if not is_enabled:
                self._disabled_device_count += 1
                logger.info("Bỏ qua telemetry của thiết bị đang tạm khóa '%s'", device_code)
                return

            received_at = datetime.now(timezone.utc)
            has_location = "latitude" in data and "longitude" in data
            message_type = str(
                data.get("message_type") or ("location" if has_location else "unknown")
            )[:50]
            schema_value = data.get("schema_version")
            external_value = data.get("message_id")
            external_message_id = (
                str(external_value)[:128] if external_value is not None else None
            )
            telemetry = TelemetryMessage(
                device_id=device_id,
                external_message_id=external_message_id,
                topic=topic[:255],
                qos=qos if qos in {0, 1, 2} else None,
                received_at=received_at,
                message_type=message_type,
                protocol="mqtt",
                schema_version=str(schema_value)[:32]
                if schema_value is not None
                else None,
                payload=data,
                processing_status=ProcessingStatus.PENDING,
            )
            db.add(telemetry)
            try:
                await db.commit()
            except IntegrityError:
                await db.rollback()
                if external_message_id is not None:
                    logger.info(
                        "Bỏ qua bản tin MQTT phát lại %s của thiết bị %s",
                        external_message_id,
                        device_code,
                    )
                    return
                raise
            await db.refresh(telemetry)
            telemetry_id = telemetry.id

            if not has_location:
                telemetry.processing_status = ProcessingStatus.SKIPPED
                telemetry.processed_at = datetime.now(timezone.utc)
                await db.commit()
                self._processed_count += 1
                self._last_processed_at = telemetry.processed_at
                return

            try:
                measured_at = _parse_measured_at(data.get("measured_at"), received_at)
                location = LocationSampleCreate(
                    device_id=device_id,
                    measured_at=measured_at,
                    latitude=data["latitude"],
                    longitude=data["longitude"],
                    altitude_m=data.get("altitude_m"),
                    speed_mps=data.get("speed_mps"),
                    heading_deg=data.get("heading_deg"),
                    accuracy_m=data.get("accuracy_m"),
                    satellite_count=data.get("satellite_count"),
                    source="mqtt",
                    battery_pct=data.get("battery_pct"),
                )
                telemetry.measured_at = measured_at
                telemetry.processing_status = ProcessingStatus.PROCESSED
                telemetry.processing_error = None
                telemetry.processed_at = datetime.now(timezone.utc)
                _, generated_events = await TrackingService.add_location(
                    db,
                    location,
                    source_message_id=telemetry_id,
                )
            except (ValidationError, ValueError, TypeError, IntegrityError) as exc:
                await db.rollback()
                failed = await db.get(TelemetryMessage, telemetry_id)
                if failed is not None:
                    failed.processing_status = ProcessingStatus.FAILED
                    failed.processing_error = str(exc)[:2000]
                    failed.processed_at = datetime.now(timezone.utc)
                    await db.commit()
                logger.warning("Telemetry không hợp lệ từ %s: %s", device_code, exc)
                return
            except Exception as exc:
                await db.rollback()
                failed = await db.get(TelemetryMessage, telemetry_id)
                if failed is not None:
                    failed.processing_status = ProcessingStatus.FAILED
                    failed.processing_error = str(exc)[:2000]
                    failed.processed_at = datetime.now(timezone.utc)
                    await db.commit()
                logger.exception("Lỗi xử lý telemetry từ %s", device_code)
                return

            updated_device = await DeviceService.get_device(db, device_id)
            if updated_device:
                response = DeviceResponse.model_validate(updated_device)
                await realtime_service.broadcast_telemetry(
                    {
                        "type": "DEVICE_UPDATE",
                        "device": json.loads(response.model_dump_json()),
                    }
                )
            for event in generated_events:
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
            self._processed_count += 1
            self._last_processed_at = datetime.now(timezone.utc)

    def health_snapshot(self) -> dict:
        return {
            "connected": self._connected,
            "subscribed": self._subscribed,
            "topic": f"{settings.mqtt_topic_prefix}/#",
            "client_id": self._client_id,
            "queue_size": self.queue.qsize() if self.queue is not None else 0,
            "queue_capacity": settings.mqtt_queue_size,
            "received_count": self._received_count,
            "processed_count": self._processed_count,
            "unknown_device_count": self._unknown_device_count,
            "disabled_device_count": self._disabled_device_count,
            "dropped_count": self._dropped_count,
            "last_message_received_at": self._last_received_at.isoformat()
            if self._last_received_at
            else None,
            "last_message_processed_at": self._last_processed_at.isoformat()
            if self._last_processed_at
            else None,
        }

    async def start(self) -> None:
        if self._started:
            return
        self.loop = asyncio.get_running_loop()
        self.queue = asyncio.Queue(maxsize=settings.mqtt_queue_size)
        self.workers = [
            asyncio.create_task(self._worker(index), name=f"mqtt-worker-{index}")
            for index in range(settings.mqtt_worker_count)
        ]
        try:
            if settings.mqtt_username:
                self.client.username_pw_set(
                    settings.mqtt_username,
                    settings.mqtt_password,
                )
            if settings.mqtt_use_tls:
                self.client.tls_set()
            self.client.reconnect_delay_set(
                min_delay=settings.mqtt_reconnect_min_delay_seconds,
                max_delay=settings.mqtt_reconnect_max_delay_seconds,
            )
            if hasattr(self.client, "connect_timeout"):
                self.client.connect_timeout = settings.mqtt_connect_timeout_seconds
            self.client.connect_async(
                settings.mqtt_host,
                port=settings.mqtt_port,
                keepalive=settings.mqtt_keepalive_seconds,
            )
            loop_result = self.client.loop_start()
            if loop_result not in {None, mqtt.MQTT_ERR_SUCCESS}:
                raise RuntimeError(
                    f"Không thể khởi động network loop MQTT, mã lỗi {loop_result}"
                )
        except Exception:
            try:
                self.client.disconnect()
                self.client.loop_stop()
            except Exception:
                logger.exception("Không thể dọn MQTT client sau lỗi khởi động")
            for worker in self.workers:
                worker.cancel()
            await asyncio.gather(*self.workers, return_exceptions=True)
            self.workers.clear()
            self.queue = None
            raise
        self._started = True
        logger.info(
            "Đã khởi động %s worker MQTT, dung lượng hàng đợi %s",
            settings.mqtt_worker_count,
            settings.mqtt_queue_size,
        )

    async def stop(self) -> None:
        if not self._started:
            return
        # Ngắt broker trước rồi mới dừng network loop để gói DISCONNECT có cơ
        # hội được gửi, tránh broker giữ phiên cũ cho tới khi hết keepalive.
        self.client.disconnect()
        self.client.loop_stop()
        if self.queue is not None:
            try:
                await asyncio.wait_for(self.queue.join(), timeout=10)
            except asyncio.TimeoutError:
                logger.warning("Hết thời gian chờ xử lý hàng đợi MQTT khi tắt ứng dụng")
        for worker in self.workers:
            worker.cancel()
        await asyncio.gather(*self.workers, return_exceptions=True)
        self.workers.clear()
        self.queue = None
        self._started = False
        self._connected = False
        self._subscribed = False


mqtt_service = MQTTService()
