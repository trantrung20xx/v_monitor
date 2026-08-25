# Nền tảng chung cho model: Base giữ metadata, UUIDMixin tạo khóa chính UUID,
# TimestampMixin chuẩn hóa thời điểm tạo/cập nhật theo UTC.
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID
from datetime import datetime, timezone
from sqlalchemy.dialects.postgresql import TIMESTAMP
import uuid

class Base(DeclarativeBase):
    # Registry metadata chung để Alembic phát hiện toàn bộ bảng đã import.
    pass



class TimestampMixin:
    # Hai mốc UTC được gắn cho mọi model kế thừa; onupdate chạy khi ORM phát lệnh UPDATE.
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        default=lambda: datetime.now(timezone.utc)
    )                                                       # Thời điểm tạo bản ghi theo UTC

    updated_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc)
    )                                                       # Thời điểm cập nhật cuối theo UTC

class UUIDMixin:
    # UUID v4 được sinh tại ứng dụng trước INSERT, phù hợp tạo bản ghi phân tán.
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4
    )                                                       # UUID định danh duy nhất của bản ghi
