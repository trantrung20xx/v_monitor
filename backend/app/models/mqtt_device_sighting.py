# Bảng tổng hợp thiết bị MQTT chưa đăng ký. Chỉ giữ lần đầu, lần cuối, số gói và topic
# để quản trị viên nhận diện thiết bị lạ mà không lưu toàn bộ payload gây phình dữ liệu.
from datetime import datetime, timezone

from sqlalchemy import BigInteger, CheckConstraint, Index, String
from sqlalchemy.dialects.postgresql import TIMESTAMP
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class MqttDeviceSighting(Base):
    # device_code là khóa tổng hợp; first/last_seen_at tạo khoảng quan sát.
    # message_count đo tần suất và last_topic hỗ trợ chẩn đoán cấu hình firmware.
    """Dấu vết của các mã thiết bị MQTT chưa được đăng ký."""

    __tablename__ = "mqtt_device_sightings"

    device_code: Mapped[str] = mapped_column(String(50), primary_key=True)
    first_seen_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    message_count: Mapped[int] = mapped_column(
        BigInteger,
        default=1,
        nullable=False,
    )
    last_topic: Mapped[str] = mapped_column(String(255), nullable=False)

    __table_args__ = (
        CheckConstraint(
            "length(btrim(device_code)) >= 1",
            name="ck_mqtt_device_sightings_code_not_blank",
        ),
        CheckConstraint(
            "message_count >= 1",
            name="ck_mqtt_device_sightings_message_count",
        ),
        Index(
            "ix_mqtt_device_sightings_last_seen",
            "last_seen_at",
        ),
    )
