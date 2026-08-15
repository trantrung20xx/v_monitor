import uuid
from datetime import datetime

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP, JSONB
from sqlalchemy import func
from typing import Optional

from app.models.base import Base, UUIDMixin


class AuditLog(Base, UUIDMixin):
    __tablename__ = "audit_logs"                              # Tên bảng lưu lịch sử thao tác

    actor_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        nullable=True
    )                                                         # ID người/hệ thống thực hiện thao tác

    action: Mapped[str] = mapped_column(
        String,
        nullable=False
    )                                                         # Loại thao tác được thực hiện

    entity_type: Mapped[str] = mapped_column(
        String,
        nullable=False
    )                                                         # Loại đối tượng bị tác động

    entity_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False
    )                                                         # ID của đối tượng bị tác động

    occurred_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        index=True,
        nullable=False
    )                                                         # Thời điểm thao tác xảy ra

    old_value: Mapped[Optional[dict]] = mapped_column(
        JSONB,
        nullable=True
    )                                                         # Dữ liệu của đối tượng trước khi thay đổi

    new_value: Mapped[Optional[dict]] = mapped_column(
        JSONB,
        nullable=True
    )                                                         # Dữ liệu của đối tượng sau khi thay đổi

    metadata_: Mapped[Optional[dict]] = mapped_column(
        "metadata",
        JSONB,
        nullable=True
    )                                                         # Thông tin bổ sung cho sự kiện

    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        default=func.now(),
        nullable=False
    )                                                         # Thời điểm bản ghi audit được tạo
