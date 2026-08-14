import json
import logging
import asyncio
from datetime import datetime, timezone
import paho.mqtt.client as mqtt
from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.schemas.tracking import LocationSampleCreate
from app.services.tracking_service import TrackingService
from uuid import UUID

logger = logging.getLogger(__name__)

# Lớp dịch vụ quản lý kết nối MQTT (Message Queuing Telemetry Transport).
# Giao tiếp với các thiết bị vật lý (UAV, Xe) để nhận dữ liệu GPS liên tục.
class MQTTService:
    def __init__(self):
        # Khởi tạo client paho-mqtt
        self.client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2,
            client_id="v_monitor_backend",
        )

        # Đăng ký các hàm callback xử lý sự kiện của MQTT
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
        self.client.on_disconnect = self.on_disconnect

        # Lưu lại event loop của asyncio vì thư viện paho-mqtt chạy trên một thread riêng (đồng bộ)
        # Việc lưu loop giúp đẩy các hàm bất đồng bộ (async db operations) ngược lại luồng chính của FastAPI
        self.loop = None

    def on_connect(self, client, userdata, flags, reason_code, properties):
        # reason_code không lỗi nghĩa là kết nối thành công tới broker
        if not reason_code.is_failure:
            logger.info("Đã kết nối thành công tới MQTT broker")
            # Theo dõi tất cả các tin nhắn gửi tới chủ đề (topic) bắt đầu bằng v_monitor/telemetry/
            client.subscribe("v_monitor/telemetry/#", qos=1)
        else:
            logger.error(
                "Kết nối tới MQTT broker thất bại, "
                f"mã lỗi: {reason_code}"
            )

    def on_message(self, client, userdata, msg):
        # Decode gói tin từ byte sang chuỗi JSON (UTF-8)
        payload_str = msg.payload.decode('utf-8')
        logger.info(f"Nhận được tin nhắn trên {msg.topic}: {payload_str}")

        # Chuyển công việc xử lý cơ sở dữ liệu (cần await) vào lại event loop chính của FastAPI
        if self.loop and self.loop.is_running():
            asyncio.run_coroutine_threadsafe(self.process_message(msg.topic, payload_str), self.loop)

    def on_disconnect(self, client, userdata, flags, reason_code, properties):
        logger.info("Đã ngắt kết nối khỏi MQTT broker")

    async def process_message(self, topic: str, payload_str: str):
        try:
            # Parse chuỗi JSON thành Dictionary Python
            data = json.loads(payload_str)

            # Phân tách chủ đề để lấy ID thiết bị, ví dụ: v_monitor/telemetry/CAR-001
            parts = topic.split('/')
            if len(parts) >= 3:
                device_code = parts[2]

                # Kiểm tra nếu gói tin có chứa tọa độ (latitude, longitude)
                if 'latitude' in data and 'longitude' in data:
                    # Mở kết nối cơ sở dữ liệu để truy vấn device_id và lưu
                    from app.models.device import Device
                    from sqlalchemy.future import select
                    async with AsyncSessionLocal() as db:
                        # Truy vấn lấy device_id từ device_code
                        device_result = await db.execute(select(Device.id).filter(Device.device_code == device_code))
                        device_id = device_result.scalar_one_or_none()
                        
                        if not device_id:
                            logger.warning(f"Bỏ qua dữ liệu MQTT: Không tìm thấy thiết bị với mã '{device_code}'")
                            return

                        # Chuẩn hóa thời gian gửi từ thiết bị, hoặc dùng thời gian hiện tại nếu không có
                        measured_at = data.get('measured_at')
                        if measured_at:
                            parsed_time = datetime.fromisoformat(measured_at.replace('Z', '+00:00'))
                        else:
                            parsed_time = datetime.now(timezone.utc)

                        # Tạo model Pydantic chứa dữ liệu nhận được
                        location_data = LocationSampleCreate(
                            device_id=device_id,
                            measured_at=parsed_time,
                            latitude=data['latitude'],
                            longitude=data['longitude'],
                            altitude_m=data.get('altitude_m'),
                            speed_mps=data.get('speed_mps'),
                            heading_deg=data.get('heading_deg'),
                            source="mqtt"
                        )

                        await TrackingService.add_location(db, location_data)
                        
                        # Lấy bản ghi thiết bị mới nhất (kèm latest_state và current_person) để đẩy qua WebSocket
                        from app.services.device_service import DeviceService
                        from app.schemas.device import DeviceResponse
                        from app.services.realtime_service import realtime_service
                        
                        updated_device = await DeviceService.get_device(db, device_id)
                        if updated_device:
                            device_resp = DeviceResponse.model_validate(updated_device)
                            message = {
                                "type": "DEVICE_UPDATE",
                                "device": json.loads(device_resp.model_dump_json())
                            }
                            await realtime_service.broadcast_telemetry(message)

                        logger.info(f"Đã xử lý thành công dữ liệu vị trí từ {device_code} và đẩy qua WebSockets")

        except Exception as e:
            logger.error(f"Lỗi khi xử lý tin nhắn MQTT: {e}", exc_info=True)

    async def start(self):
        # Lấy event loop hiện tại của FastAPI để chuẩn bị gọi các hàm async từ paho-mqtt
        self.loop = asyncio.get_running_loop()
        logger.info(
            "Bắt đầu khởi động MQTT client kết nối tới "
            f"{settings.mqtt_host}:{settings.mqtt_port}"
        )

        if settings.mqtt_username:
            self.client.username_pw_set(
                settings.mqtt_username,
                settings.mqtt_password,
            )

        if settings.mqtt_use_tls:
            self.client.tls_set()

        # Kết nối tới Broker (chạy không đồng bộ để không chặn luồng chính)
        self.client.connect_async(
            settings.mqtt_host,
            port=settings.mqtt_port
        )

        # Bắt đầu vòng lặp mạng của MQTT (chạy trên một thread ẩn của paho-mqtt)
        self.client.loop_start()

    async def stop(self):
        # Dừng vòng lặp và ngắt kết nối an toàn khi server FastAPI tắt
        self.client.loop_stop()
        self.client.disconnect()

# Khởi tạo một đối tượng duy nhất (Singleton) để dùng chung trên toàn ứng dụng
mqtt_service = MQTTService()
