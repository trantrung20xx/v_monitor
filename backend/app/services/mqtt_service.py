# Pipeline MQTT: callback mạng chỉ đưa gói vào hàng đợi hữu hạn; worker bất đồng bộ
# xác thực topic/payload/thiết bị, chống trùng, lưu telemetry/GPS rồi phát realtime.
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

# Paho MQTT 2.x yêu cầu chọn phiên bản callback; nhánh dự phòng giữ khả năng chạy
# với Paho 1.x mà không thay đổi chữ ký xử lý gói tin của dịch vụ.
try:
    from paho.mqtt.enums import CallbackAPIVersion

    _HAS_CALLBACK_API_VERSION = True
except ImportError:
    CallbackAPIVersion = getattr(mqtt, "CallbackAPIVersion", None)
    _HAS_CALLBACK_API_VERSION = CallbackAPIVersion is not None


def _create_mqtt_client(client_id: str) -> mqtt.Client:
    """Khởi tạo MQTT client tương thích paho-mqtt 1.x và 2.x."""
    # Paho 2.x cần khai báo VERSION2 để callback nhận ReasonCode và properties.
    if _HAS_CALLBACK_API_VERSION and CallbackAPIVersion is not None:
        return mqtt.Client(CallbackAPIVersion.VERSION2, client_id=client_id)
    # Paho 1.x không có enum callback nên dùng constructor cũ với cùng client id.
    return mqtt.Client(client_id=client_id)


def _mqtt_client_id() -> str:
    # Lấy client id cấu hình sẵn hoặc sinh id duy nhất cho tiến trình backend.
    configured = settings.mqtt_client_id
    # Cấu hình tường minh được ưu tiên để broker doanh nghiệp nhận diện client cố định.
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
    # Chuẩn hóa thời gian thiết bị đo về UTC; thiếu giá trị thì dùng lúc backend nhận.
    # Fallback giữ pipeline hoạt động với firmware cũ chưa gửi `measured_at`.
    if raw_value is None:
        return fallback
    # ISO `Z` được đổi thành offset +00:00 để datetime.fromisoformat đọc thống nhất.
    value = datetime.fromisoformat(str(raw_value).replace("Z", "+00:00"))
    # Timestamp không kèm múi giờ được quy ước là UTC, tránh phụ thuộc timezone máy chủ.
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _device_code_from_topic(topic: str) -> Optional[str]:
    # Chỉ nhận mã thiết bị từ topic đúng dạng <prefix>/<device_code>.
    prefix_parts = settings.mqtt_topic_prefix.split("/")
    topic_parts = topic.split("/")
    # Topic phải có đúng một cấp sau prefix; topic sâu hơn hoặc khác prefix không
    # được phép suy diễn thành mã thiết bị.
    if (
        len(topic_parts) != len(prefix_parts) + 1
        or topic_parts[: len(prefix_parts)] != prefix_parts
    ):
        return None
    device_code = topic_parts[-1]
    # Mã rỗng, có khoảng trắng bao quanh hoặc vượt kích thước schema đều bị loại
    # trước khi thực hiện truy vấn database.
    if not device_code or device_code != device_code.strip() or len(device_code) > 50:
        return None
    return device_code


class MQTTService:
    # Quản lý kết nối broker và pipeline xử lý tuần tự theo hàng đợi hữu hạn.

    def __init__(self):
        # client/loop thuộc lớp kết nối; queue/workers tách callback mạng đồng bộ khỏi
        # các thao tác database bất đồng bộ để không chặn luồng của thư viện Paho.
        self._client_id = _mqtt_client_id()
        self.client = _create_mqtt_client(client_id=self._client_id)
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
        self.client.on_disconnect = self.on_disconnect
        self.loop: Optional[asyncio.AbstractEventLoop] = None
        self.queue: Optional[asyncio.Queue[tuple[str, str, int]]] = None
        self.workers: list[asyncio.Task] = []
        # Ba cờ phản ánh ba mức khác nhau: dịch vụ đã start, TCP/MQTT đã kết nối và
        # broker đã chấp nhận subscribe. Health check dùng riêng từng cờ để chẩn đoán.
        self._started = False
        self._connected = False
        self._subscribed = False
        # Bộ đếm chỉ phục vụ quan sát từ lúc tiến trình khởi động, không phải số liệu
        # lịch sử lâu dài và không thay thế các bảng telemetry/sighting trong database.
        self._received_count = 0
        self._processed_count = 0
        self._unknown_device_count = 0
        self._disabled_device_count = 0
        self._dropped_count = 0
        self._last_received_at: Optional[datetime] = None
        self._last_processed_at: Optional[datetime] = None

    def on_connect(self, client, userdata, flags, reason_code, properties=None):
        # Đánh dấu kết nối và đăng ký toàn bộ topic con ngay khi broker chấp nhận.
        # Paho 1.x trả mã số, Paho 2.x trả ReasonCode; cả hai được quy về boolean.
        # ReasonCode mới cung cấp thuộc tính is_failure nên được xử lý trước.
        if hasattr(reason_code, "is_failure"):
            is_success = not reason_code.is_failure
        # Callback cũ dùng số 0 cho kết nối thành công.
        elif isinstance(reason_code, int):
            is_success = reason_code == 0
        # Nhánh chuỗi là lớp phòng vệ cho mock/test hoặc biến thể thư viện khác.
        else:
            is_success = str(reason_code).lower() in {"0", "success"}

        # Chỉ subscribe sau khi broker xác nhận phiên kết nối hợp lệ.
        if is_success:
            self._connected = True
            logger.info("Đã kết nối thành công tới MQTT broker")
            # Wildcard `#` chỉ xuất hiện phía subscribe để nhận mọi device_code dưới prefix.
            result, _ = client.subscribe(
                f"{settings.mqtt_topic_prefix}/#",
                qos=1,
            )
            # Kết nối TCP thành công chưa đủ; health chỉ sẵn sàng khi subscribe được chấp nhận.
            self._subscribed = result == mqtt.MQTT_ERR_SUCCESS
            if not self._subscribed:
                logger.error("Không thể đăng ký topic MQTT, mã lỗi: %s", result)
        else:
            # Xóa cả hai cờ vì không có phiên broker thì subscription cũ không còn giá trị.
            self._connected = False
            self._subscribed = False
            logger.error("Kết nối MQTT thất bại, mã lỗi: %s", reason_code)

    def _enqueue_message(self, topic: str, payload: str, qos: int) -> None:
        # Đưa gói vào queue mà không chờ; từ chối có kiểm soát khi queue đã đầy.
        # Queue chưa tồn tại nghĩa dịch vụ chưa start hoặc đã stop; callback cũ bị bỏ qua.
        if self.queue is None:
            return
        try:
            # put_nowait giữ callback mạng không bị chặn bởi tốc độ xử lý database.
            self.queue.put_nowait((topic, payload, qos))
        except asyncio.QueueFull:
            # Bộ đếm dropped giúp health cảnh báo quá tải dù payload không được lưu.
            self._dropped_count += 1
            # Hàng đợi hữu hạn bảo vệ bộ nhớ khi lưu lượng vượt quá khả năng xử lý.
            logger.error(
                "Hàng đợi MQTT đã đầy (%s bản tin), bỏ bản tin trên topic %s",
                settings.mqtt_queue_size,
                topic,
            )

    def on_message(self, client, userdata, msg):
        # Callback rất ngắn của Paho: giải mã UTF-8 rồi chuyển gói sang event loop.
        # Bộ đếm received tăng trước giải mã nên health phản ánh cả gói lỗi encoding;
        # processed chỉ tăng sau khi pipeline đã phân loại và hoàn tất nhánh hợp lệ.
        self._received_count += 1
        self._last_received_at = datetime.now(timezone.utc)
        try:
            # JSON chỉ được giải mã sau khi byte payload đã xác nhận là UTF-8.
            payload = msg.payload.decode("utf-8")
        except UnicodeDecodeError:
            # Không đưa byte lỗi vào event loop vì json.loads chắc chắn không xử lý được.
            logger.warning("Bỏ qua bản tin MQTT không phải UTF-8 trên %s", msg.topic)
            return
        if self.loop and self.loop.is_running():
            # Callback chạy trên thread mạng của Paho; call_soon_threadsafe là cầu
            # nối duy nhất được phép chạm asyncio.Queue thuộc event loop FastAPI.
            # Chỉ sao chép topic, chuỗi payload và QoS; không truyền object msg qua thread.
            self.loop.call_soon_threadsafe(
                self._enqueue_message,
                msg.topic,
                payload,
                int(getattr(msg, "qos", 0)),
            )

    def on_disconnect(self, client, userdata, flags, reason_code=None, properties=None):
        # Xóa trạng thái kết nối thật; Paho tự reconnect theo backoff đã cấu hình.
        self._connected = False
        self._subscribed = False
        logger.info("Đã ngắt kết nối khỏi MQTT broker")

    async def _worker(self, worker_index: int) -> None:
        # Lấy từng gói khỏi queue, cô lập lỗi và luôn báo hoàn tất cho queue.join().
        assert self.queue is not None
        while True:
            # `get` chờ không tiêu tốn CPU khi chưa có gói; mỗi worker xử lý một gói tại một thời điểm.
            topic, payload, qos = await self.queue.get()
            try:
                await self.process_message(topic, payload, qos=qos)
            except asyncio.CancelledError:
                # Tín hiệu hủy khi shutdown phải được phát tiếp để task kết thúc đúng chuẩn.
                raise
            except Exception:
                # Lỗi của một gói bị cô lập, vòng lặp vẫn tiếp tục nhận gói sau.
                logger.exception("Worker MQTT %s gặp lỗi ngoài dự kiến", worker_index)
            finally:
                # task_done luôn chạy để queue.join không treo kể cả nhánh lỗi hoặc hủy.
                self.queue.task_done()

    async def process_message(
        self,
        topic: str,
        payload_str: str,
        *,
        qos: int = 0,
    ) -> None:
        # Xác thực, phân loại, lưu một gói MQTT rồi phát thay đổi hợp lệ qua realtime.
        # Payload phải là JSON object; dữ liệu khác bị bỏ trước khi mở transaction DB.
        try:
            # Parse trước database để payload hỏng không chiếm connection pool.
            data = json.loads(payload_str)
        except json.JSONDecodeError:
            logger.warning("Bỏ qua bản tin MQTT không phải JSON hợp lệ")
            return
        # Array, số hoặc chuỗi JSON không có các trường telemetry nên bị từ chối.
        if not isinstance(data, dict):
            logger.warning("Bỏ qua bản tin MQTT vì payload không phải object")
            return

        # Mã thiết bị lấy từ topic thay vì tin trường tùy ý trong payload. Cách này
        # giữ một nguồn định danh thống nhất với ACL broker triển khai sau này.
        device_code = _device_code_from_topic(topic)
        if device_code is None:
            logger.warning("Bỏ qua bản tin MQTT vì topic không đúng định dạng")
            return

        async with AsyncSessionLocal() as db:
            # Topic chỉ xác định ứng viên. Quyền nhận telemetry luôn lấy từ hồ sơ
            # thiết bị thật trong database, không dựa vào trạng thái online/offline.
            device_result = await db.execute(
                select(Device.id, Device.is_enabled).where(
                    Device.device_code == device_code
                )
            )
            # one_or_none bảo đảm mã thiết bị duy nhất theo constraint của bảng devices.
            device_row = device_result.one_or_none()
            if device_row is None:
                # Thiết bị lạ chỉ cập nhật một bản thống kê gộp theo device_code.
                # Không tạo Device và không lưu toàn bộ payload chưa được tin cậy.
                # Upsert giúp hàng nghìn lần gửi từ cùng thiết bị chỉ chiếm một dòng.
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
                # Commit sighting độc lập vì nhánh này kết thúc và không có telemetry
                # hay latest state nào được phép tạo.
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
                # Tạm khóa là quyết định quản trị: vẫn nhận ở broker nhưng không ghi
                # telemetry, không cập nhật latest state và không phát lên giao diện.
                self._disabled_device_count += 1
                logger.info("Bỏ qua telemetry của thiết bị đang tạm khóa '%s'", device_code)
                return

            # `received_at` là thời gian đáng tin của server, dùng cho presence;
            # `measured_at` phía dưới là thời gian đo của thiết bị, dùng cho hành trình.
            received_at = datetime.now(timezone.utc)
            # Gói không có đủ latitude/longitude vẫn được lưu làm telemetry SKIPPED
            # để phản ánh dữ liệu đã nhận nhưng không thể tạo một mẫu vị trí.
            has_location = "latitude" in data and "longitude" in data
            # message_type do thiết bị gửi được ưu tiên; nếu thiếu thì suy ra từ tọa độ.
            message_type = str(
                data.get("message_type") or ("location" if has_location else "unknown")
            )[:50]
            # Các trường mô tả được giới hạn độ dài trước khi lưu; payload gốc vẫn
            # được giữ trong JSONB để chẩn đoán và mở rộng schema về sau.
            schema_value = data.get("schema_version")
            external_value = data.get("message_id")
            # message_id được chuyển thành chuỗi để hỗ trợ UUID hoặc mã số từ firmware cũ.
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
            # Commit bản telemetry PENDING trước khi xử lý vị trí để mọi gói đã nhận
            # đều có dấu vết, kể cả khi bước validation/tracking phía sau thất bại.
            db.add(telemetry)
            try:
                # Constraint chống trùng được kiểm tra tại commit, an toàn với nhiều worker đồng thời.
                await db.commit()
            except IntegrityError:
                # Session lỗi phải rollback trước khi có thể dùng lại cho truy vấn tiếp theo.
                await db.rollback()
                if external_message_id is not None:
                    # Unique(device_id, external_message_id) biến lần phát lại QoS 1
                    # thành thao tác bỏ qua an toàn, không tạo vị trí hoặc sự kiện trùng.
                    # Không tăng processed vì đây là bản phát lại, không phải mẫu mới.
                    logger.info(
                        "Bỏ qua bản tin MQTT phát lại %s của thiết bị %s",
                        external_message_id,
                        device_code,
                    )
                    return
                raise
            # Refresh lấy id do database sinh để liên kết source_message_id của mẫu vị trí.
            await db.refresh(telemetry)
            telemetry_id = telemetry.id

            if not has_location:
                # SKIPPED là gói hợp lệ về transport nhưng không mang tọa độ; không
                # phải lỗi hệ thống và không tác động online/latest state.
                telemetry.processing_status = ProcessingStatus.SKIPPED
                telemetry.processed_at = datetime.now(timezone.utc)
                await db.commit()
                self._processed_count += 1
                self._last_processed_at = telemetry.processed_at
                return

            try:
                # Pydantic kiểm tra biên tọa độ và kiểu dữ liệu trước khi service cập
                # nhật lịch sử/latest state trong cùng transaction nghiệp vụ.
                # Thời gian đo được chuẩn hóa trước để cả telemetry và location dùng
                # đúng một mốc UTC.
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
                # TrackingService commit telemetry đang attach, mẫu GPS, latest state
                # và event trong cùng transaction.
                _, generated_events = await TrackingService.add_location(
                    db,
                    location,
                    source_message_id=telemetry_id,
                )
            except (ValidationError, ValueError, TypeError, IntegrityError) as exc:
                # Nhóm lỗi dữ liệu dự kiến được ghi FAILED kèm thông điệp ngắn; worker
                # tiếp tục xử lý gói kế tiếp thay vì làm chết pipeline.
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
                # Lỗi ngoài dự kiến vẫn được rollback, đánh dấu FAILED và ghi stack trace
                # ở server để telemetry không bị kẹt vĩnh viễn tại trạng thái PENDING.
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
            # Chỉ phát realtime sau khi database commit thành công. REST vẫn là nguồn
            # tải lại chính xác nếu frontend mất một bản tin WebSocket.
            # DEVICE_UPDATE mang snapshot đầy đủ để DashboardCubit thay đúng một item
            # mà không cần gọi lại danh sách toàn bộ thiết bị.
            if updated_device:
                response = DeviceResponse.model_validate(updated_device)
                await realtime_service.broadcast_telemetry(
                    {
                        "type": "DEVICE_UPDATE",
                        "device": json.loads(response.model_dump_json()),
                    }
                )
            # Event được phát riêng để màn hình lịch sử/sự kiện cập nhật theo đúng
            # loại thông điệp mà không phải suy luận từ thay đổi tốc độ.
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
        # Trả snapshot chỉ-đọc để /health phân biệt lỗi broker, subscribe và quá tải.
        # qsize là số gói đang chờ trong RAM; capacity là trần cấu hình để tính mức tải.
        # Các timestamp dùng UTC ISO giúp hệ thống giám sát so sánh không phụ thuộc múi giờ.
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
        # Khởi tạo queue/workers rồi bắt đầu network loop và kết nối broker nền.
        # Guard chống lifespan/test gọi start lặp và tạo nhiều nhóm worker trùng nhau.
        if self._started:
            return
        # Queue và worker được tạo lại theo mỗi vòng start/stop, không giữ task đã
        # thuộc event loop cũ khi test hoặc reload ứng dụng.
        self.loop = asyncio.get_running_loop()
        self.queue = asyncio.Queue(maxsize=settings.mqtt_queue_size)
        self.workers = [
            asyncio.create_task(self._worker(index), name=f"mqtt-worker-{index}")
            for index in range(settings.mqtt_worker_count)
        ]
        try:
            # Chỉ gọi username_pw_set khi username có cấu hình; broker test ẩn danh vẫn hoạt động.
            if settings.mqtt_username:
                self.client.username_pw_set(
                    settings.mqtt_username,
                    settings.mqtt_password,
                )
            # TLS là tùy chọn cấu hình, không ảnh hưởng luồng xử lý telemetry phía sau.
            if settings.mqtt_use_tls:
                self.client.tls_set()
            # Paho tự tăng thời gian chờ giữa các lần reconnect trong giới hạn này.
            self.client.reconnect_delay_set(
                min_delay=settings.mqtt_reconnect_min_delay_seconds,
                max_delay=settings.mqtt_reconnect_max_delay_seconds,
            )
            # Một số phiên bản Paho không có thuộc tính này nên cần kiểm tra khả năng trước.
            if hasattr(self.client, "connect_timeout"):
                self.client.connect_timeout = settings.mqtt_connect_timeout_seconds
            # connect_async kết hợp loop_start để khởi động không chặn lifespan API;
            # kết quả kết nối thật được callback on_connect cập nhật vào health.
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
            # Dọn theo thứ tự client trước, worker sau để không nhận thêm gói khi rollback start.
            try:
                self.client.disconnect()
                self.client.loop_stop()
            except Exception:
                # Lỗi dọn client được ghi nhận nhưng không che exception khởi động ban đầu.
                logger.exception("Không thể dọn MQTT client sau lỗi khởi động")
            # Hủy mọi worker đã tạo để không để task mồ côi khi start thất bại giữa chừng.
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
        # Ngừng nhận gói mới, chờ queue có giới hạn rồi hủy worker sạch sẽ.
        # Guard giúp shutdown gọi lặp an toàn khi start trước đó chưa thành công.
        if not self._started:
            return
        # Ngắt broker trước rồi mới dừng network loop để gói DISCONNECT có cơ
        # hội được gửi, tránh broker giữ phiên cũ cho tới khi hết keepalive.
        self.client.disconnect()
        self.client.loop_stop()
        if self.queue is not None:
            try:
                # Cho worker tối đa 10 giây xử lý hết gói đã nhận trước khi hủy.
                await asyncio.wait_for(self.queue.join(), timeout=10)
            except asyncio.TimeoutError:
                # Hết thời gian chỉ ghi cảnh báo; shutdown không được treo vô hạn.
                logger.warning("Hết thời gian chờ xử lý hàng đợi MQTT khi tắt ứng dụng")
        # Cancel sau queue.join để gói đang chờ có cơ hội hoàn tất trước.
        for worker in self.workers:
            worker.cancel()
        # return_exceptions hấp thụ CancelledError của từng worker trong quá trình dọn.
        await asyncio.gather(*self.workers, return_exceptions=True)
        self.workers.clear()
        self.queue = None
        self._started = False
        self._connected = False
        self._subscribed = False


# Singleton dùng chung suốt vòng đời FastAPI; lifespan chịu trách nhiệm start/stop.
mqtt_service = MQTTService()
