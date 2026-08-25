# Nhật ký kiểm toán thay đổi quan trọng: ai thực hiện, hành động nào, đối tượng nào
# và giá trị trước/sau. Dữ liệu này dùng truy vết, không dùng làm trạng thái hiện tại.
import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP, JSONB
from sqlalchemy import func
from typing import Optional

from app.models.base import Base, UUIDMixin


class AuditLog(Base, UUIDMixin):
    # actor/action/entity xác định ai làm gì với đối tượng nào; occurred_at là lúc thao tác.
    # old/new_value lưu chênh lệch; metadata_ giữ ngữ cảnh; created_at là lúc ghi database.
    __tablename__ = "audit_logs"                              # Tên bảng lưu lịch sử thao tác

    actor_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("user_accounts.id", ondelete="SET NULL"),
        nullable=True,
    )                                                         # Tài khoản thực hiện thao tác

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

    # SET NULL ở actor_user_id giữ lịch sử ngay cả khi tài khoản thực hiện bị xóa.
    actor_user = relationship("UserAccount")

    # Hai chỉ mục phục vụ hai hướng tra cứu chính: lịch sử theo người thực hiện và
    # lịch sử theo đối tượng bị thay đổi, đều có thứ tự thời gian.
    __table_args__ = (
        Index(
            "ix_audit_logs_actor_occurred",
            "actor_user_id",
            "occurred_at",
        ),
        Index(
            "ix_audit_logs_entity_occurred",
            "entity_type",
            "entity_id",
            "occurred_at",
        ),
    )
