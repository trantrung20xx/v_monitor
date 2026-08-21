import uuid
from typing import Optional

from sqlalchemy import CheckConstraint, Float, ForeignKey, Integer, SmallInteger
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin


class SystemSetting(Base, TimestampMixin):
    """Cấu hình nghiệp vụ dùng chung, luôn được lưu tại dòng có khóa id bằng 1."""

    __tablename__ = "system_settings"

    id: Mapped[int] = mapped_column(
        SmallInteger,
        primary_key=True,
        default=1,
    )
    offline_timeout_seconds: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=300,
    )
    movement_threshold_mps: Mapped[float] = mapped_column(
        Float,
        nullable=False,
        default=0.5,
    )
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

    updater = relationship("UserAccount")

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
