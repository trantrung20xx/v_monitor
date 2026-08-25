# Công cụ kiểm tra tích hợp: đọc cấu hình MQTT giống backend rồi phát một chuỗi GPS
# giả lập QoS 1. Tệp không được import hoặc chạy trong tiến trình production.
import json
import os
import time
import random
import uuid
from datetime import datetime, timezone
from pathlib import Path
import paho.mqtt.client as mqtt

# Hỗ trợ tương thích cả paho-mqtt 1.x và 2.x, tránh cảnh báo type checker
try:
    from paho.mqtt.enums import CallbackAPIVersion
    _HAS_CALLBACK_API_VERSION = True
except ImportError:
    CallbackAPIVersion = getattr(mqtt, "CallbackAPIVersion", None)
    _HAS_CALLBACK_API_VERSION = CallbackAPIVersion is not None


def create_mqtt_client(client_id: str) -> mqtt.Client:
    # Chọn API callback phù hợp với phiên bản paho-mqtt đang cài trên máy kiểm thử.
    if _HAS_CALLBACK_API_VERSION and CallbackAPIVersion is not None:
        return mqtt.Client(
            CallbackAPIVersion.VERSION2,
            client_id=client_id,
        )
    return mqtt.Client(client_id=client_id)


def load_backend_env():
    # Đọc .env tối giản và chỉ đặt biến chưa có để biến môi trường của shell luôn ưu tiên.
    env_path = Path(__file__).resolve().parents[1] / "backend" / ".env"
    if not env_path.exists():
        return

    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


load_backend_env()

# Broker, xác thực, topic và nhịp phát đều có thể đổi qua biến môi trường; giá trị
# mặc định phục vụ kiểm tra cục bộ với mã UAV-100.
BROKER = os.getenv("MQTT_HOST", "broker.emqx.io")
PORT = int(os.getenv("MQTT_PORT", "1883"))
USE_TLS = os.getenv("MQTT_USE_TLS", "false").lower() == "true"
USERNAME = os.getenv("MQTT_USERNAME") or None
PASSWORD = os.getenv("MQTT_PASSWORD") or None
DEVICE_CODE = os.getenv("DEVICE_CODE", "UAV-100")
TOPIC_PREFIX = os.getenv("MQTT_TOPIC_PREFIX", "v_monitor/telemetry").strip("/")
TOPIC = os.getenv("MQTT_TOPIC", f"{TOPIC_PREFIX}/{DEVICE_CODE}")
COUNT = int(os.getenv("MQTT_COUNT", "5"))
INTERVAL_SECONDS = float(os.getenv("MQTT_INTERVAL_SECONDS", "1"))


def on_connect(client, userdata, flags, reason_code, properties=None):
    # Chỉ phát sau khi broker xác nhận kết nối; mỗi mẫu mới có message_id riêng.
    print(
        f"Connected to MQTT broker {BROKER}:{PORT} "
        f"with result code {reason_code}"
    )
    is_failure = getattr(reason_code, "is_failure", False) if hasattr(reason_code, "is_failure") else (reason_code != 0 if isinstance(reason_code, int) else False)
    if is_failure:
        client.disconnect()
        return
    
    lat = 21.028511
    lng = 105.804817
    
    for _ in range(COUNT):
        lat += random.uniform(-0.0001, 0.0001)
        lng += random.uniform(-0.0001, 0.0001)
        
        payload = {
            "message_id": str(uuid.uuid4()),
            "latitude": lat,
            "longitude": lng,
            "altitude_m": random.uniform(10, 50),
            "speed_mps": random.uniform(0, 15),
            "heading_deg": random.uniform(0, 360),
            "measured_at": datetime.now(timezone.utc)
            .isoformat()
            .replace("+00:00", "Z"),
        }
        
        print(f"Publishing to {TOPIC}: {payload}")
        client.publish(TOPIC, json.dumps(payload), qos=1)
        time.sleep(INTERVAL_SECONDS)
        
    client.disconnect()


# Client test không reconnect vô hạn; kết thúc sau COUNT mẫu hoặc khi gặp lỗi.
client = create_mqtt_client(client_id="v_monitor_test_publisher")
client.on_connect = on_connect
if USERNAME:
    client.username_pw_set(USERNAME, PASSWORD)
if USE_TLS:
    client.tls_set()

print(f"Connecting to {BROKER}:{PORT}...")
try:
    client.connect(BROKER, PORT, 60)
    client.loop_forever()
except Exception as e:
    print(f"Error connecting to MQTT: {e}")
