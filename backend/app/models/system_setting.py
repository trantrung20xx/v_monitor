# Bản ghi cấu hình vận hành duy nhất: thời gian ngoại tuyến, ngưỡng di chuyển và ngưỡng đứt quãng.
# updated_by liên kết người quản trị đã thay đổi để phục vụ kiểm toán.
import uuid
from typing import Optional

from sqlalchemy import CheckConstraint, Float, ForeignKey, Integer, SmallInteger
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin


class SystemSetting(Base, TimestampMixin):
    # id cố định duy trì một hàng; ba ngưỡng điều khiển presence, movement và tách chặng.
    # updated_by liên kết ADMIN gần nhất đã sửa cấu hình.
    """Cấu hình nghiệp vụ dùng chung, luôn được lưu tại dòng có khóa id bằng 1."""

    __tablename__ = "system_settings"

    # Khóa 1 cố định biến bảng thành singleton nhưng vẫn tận dụng transaction/row lock.
    id: Mapped[int] = mapped_column(
        SmallInteger,
        primary_key=True,
        default=1,
    )
    # Khoảng không nhận telemetry trước khi PresenceService chuyển online → offline.
    offline_timeout_seconds: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=300,
    )
    # Tốc độ chuẩn m/s phân định bắt đầu/dừng di chuyển trong TrackingService.
    movement_threshold_mps: Mapped[float] = mapped_column(
        Float,
        nullable=False,
        default=0.5,
    )
    # Khoảng trống thời gian mặc định dùng để tách các đoạn hành trình ở frontend.
    default_gap_threshold_seconds: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=300,
    )
    updated_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("user_accounts.id", ondelete="SET NULL"),
        nullable=True,
    )

    # Quan hệ tùy chọn tới ADMIN sửa gần nhất, phục vụ truy vết giao diện/audit.
    updater = relationship("UserAccount")

    # Constraint lặp lại biên Pydantic tại database để bảo vệ mọi đường ghi dữ liệu.
    __table_args__ = (
        CheckConstraint("id = 1", name="ck_system_settings_singleton"),
        CheckConstraint(
            "offline_timeout_seconds BETWEEN 30 AND 86400",
            name="ck_system_settings_offline_timeout",
        ),
        CheckConstraint(
            "movement_threshold_mps BETWEEN 0.0 AND 10.0",
            name="ck_system_settings_movement_threshold",
        ),
        CheckConstraint(
            "default_gap_threshold_seconds BETWEEN 60 AND 3600",
            name="ck_system_settings_gap_threshold",
        ),
    )
