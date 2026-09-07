"""Thông báo chờ phát; lịch sử nghiệp vụ vẫn nằm trong device_events."""
import uuid
from datetime import datetime, timezone

from sqlalchemy import Index
from sqlalchemy.dialects.postgresql import JSONB, TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, UUIDMixin


class RealtimeOutbox(Base, UUIDMixin):
    __tablename__ = "realtime_outbox"

    # Nội dung sẽ gửi qua WebSocket, gồm ID sự kiện để nhận biết nếu bị gửi lặp.
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    # Mốc sớm nhất được lấy dòng này để gửi. Ví dụ available_at = 10:00:25 thì
    # trước 10:00:25 mọi lượt gửi đều bỏ qua. Khi nhận xử lý, mốc này được đẩy tới
    # hết thời gian tạm giữ (lease); khi gửi lỗi, được đổi thành giờ hẹn thử lại.
    available_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    # Mã lượt gửi đang phụ trách dòng này. Chỉ lượt còn giữ đúng mã mới được sửa/xóa.
    # Khi available_at tới hạn, lượt khác có thể nhận lại và thay mã, kể cả mã cũ
    # chưa được xóa vì chương trình đã dừng giữa chừng.
    claim_token: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))

    __table_args__ = (Index("ix_realtime_outbox_available", "available_at", "created_at"),)
