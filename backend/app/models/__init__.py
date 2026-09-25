# Đăng ký toàn bộ model với SQLAlchemy metadata. Các import nhìn như không dùng
# nhưng bắt buộc để Alembic nhìn thấy đủ bảng và quan hệ khi kiểm tra migration.
from app.models.base import Base
from app.models.device import Device
from app.models.location_sample import LocationSample
from app.models.device_event import DeviceEvent
from app.models.device_latest_state import DeviceLatestState
from app.models.telemetry_message import TelemetryMessage
from app.models.audit_log import AuditLog
from app.models.user_account import UserAccount, UserSetting
from app.models.system_setting import SystemSetting
from app.models.mqtt_device_sighting import MqttDeviceSighting
from app.models.realtime_outbox import RealtimeOutbox
# Import tại đây bảo đảm Alembic Base.metadata nhìn thấy ba bảng LTE khi tạo
# schema/autogenerate; không import chúng sẽ khiến migration bootstrap thiếu bảng.
from app.models.cell_tower import CellTower
from app.models.cell_observation import CellObservation
from app.models.cell_position_estimate import CellPositionEstimate
