from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Float, Index, Integer, false, text
from sqlalchemy.dialects.postgresql import TIMESTAMP
from sqlalchemy.dialects.postgresql import UUID
from datetime import datetime
import uuid

from app.models.base import Base, TimestampMixin


class DeviceLatestState(Base, TimestampMixin):
    __tablename__ = "device_latest_state"                 # Tên bảng trong PostgreSQL

    device_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),                                # Lưu UUID native của PostgreSQL
        ForeignKey("devices.id", ondelete="CASCADE"),      # Liên kết tới devices.id; xóa device thì xóa state
        primary_key=True                                   # Mỗi device chỉ có một latest state
    )

    last_seen_at: Mapped[datetime | None] = mapped_column(
        TIMESTAMP(timezone=True),
        nullable=True                                      # Thời điểm server nhận dữ liệu gần nhất
    )

    latest_measured_at: Mapped[datetime | None] = mapped_column(
        TIMESTAMP(timezone=True),
        nullable=True                                      # Thời điểm đo của mẫu mới nhất
    )

    latest_sample_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("location_samples.id", ondelete="SET NULL"),
        nullable=True,
    )

    is_online: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        server_default=false(),                             # Mặc định thiết bị offline
    )

    current_latitude: Mapped[float | None] = mapped_column(
        Float,
        nullable=True                                       # Vĩ độ GPS hiện tại
    )

    current_longitude: Mapped[float | None] = mapped_column(
        Float,
        nullable=True                                       # Kinh độ GPS hiện tại
    )

    current_altitude_m: Mapped[float | None] = mapped_column(
        Float,
        nullable=True                                       # Độ cao GPS hiện tại (m)
    )

    current_speed_mps: Mapped[float | None] = mapped_column(
        Float,
        nullable=True                                       # Vận tốc hiện tại (m/s)
    )

    current_heading_deg: Mapped[float | None] = mapped_column(
        Float,
        nullable=True                                       # Hướng di chuyển hiện tại (độ)
    )

    # Phần trăm pin của thiết bị trong bảng devices. null nghĩa là thiết bị
    # chưa gửi thông tin pin, không phải mức pin bằng 0.
    battery_pct: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
    )

    device = relationship(
        "Device",
        back_populates="latest_state"                       # Quan hệ ngược tới Device
    )

    __table_args__ = (
        CheckConstraint(
            "current_latitude IS NULL OR current_latitude BETWEEN -90 AND 90",
            name="ck_device_latest_state_latitude",
        ),
        CheckConstraint(
            "current_longitude IS NULL OR current_longitude BETWEEN -180 AND 180",
            name="ck_device_latest_state_longitude",
        ),
        CheckConstraint(
            "current_speed_mps IS NULL OR current_speed_mps >= 0",
            name="ck_device_latest_state_speed",
        ),
        CheckConstraint(
            "current_heading_deg IS NULL OR "
            "(current_heading_deg >= 0 AND current_heading_deg < 360)",
            name="ck_device_latest_state_heading",
        ),
        CheckConstraint(
            "battery_pct IS NULL OR battery_pct BETWEEN 0 AND 100",
            name="ck_device_latest_state_battery",
        ),
        Index(
            "ix_device_latest_state_online_seen",
            "last_seen_at",
            postgresql_where=text("is_online"),
        ),
    )
