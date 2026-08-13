from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import DateTime, ForeignKey, Float, Boolean, Integer
from sqlalchemy.dialects.postgresql import UUID
from datetime import datetime, timezone
import uuid

from app.models.base import Base, TimestampMixin


class DeviceLatestState(Base, TimestampMixin):
    __tablename__ = "device_latest_state"                 # Tên bảng trong PostgreSQL

    device_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),                                # Lưu UUID native của PostgreSQL
        ForeignKey("devices.id", ondelete="CASCADE"),      # Liên kết tới devices.id; xóa device thì xóa state
        primary_key=True                                   # Mỗi device chỉ có một latest state
    )

    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),                           # Kiểu datetime có thông tin múi giờ
        default=lambda: datetime.now(timezone.utc)         # Thời điểm gần nhất nhận dữ liệu
    )

    is_online: Mapped[bool] = mapped_column(
        Boolean,
        default=False                                       # Mặc định thiết bị offline
    )

    current_latitude: Mapped[float | None] = mapped_column(
        Float,
        nullable=True                                       # Vĩ độ GPS hiện tại
    )

    current_longitude: Mapped[float | None] = mapped_column(
        Float,
        nullable=True                                       # Kinh độ GPS hiện tại
    )

    current_speed_mps: Mapped[float | None] = mapped_column(
        Float,
        nullable=True                                       # Vận tốc hiện tại (m/s)
    )

    current_heading_deg: Mapped[float | None] = mapped_column(
        Float,
        nullable=True                                       # Hướng di chuyển hiện tại (độ)
    )

    uav_battery_pct: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True                                       # Pin UAV (%)
    )

    controller_battery_pct: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True                                       # Pin tay cầm (%)
    )

    device = relationship(
        "Device",
        back_populates="latest_state"                       # Quan hệ ngược tới Device
    )
