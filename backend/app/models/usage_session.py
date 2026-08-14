import uuid
from datetime import datetime
from sqlalchemy import ForeignKey, String, Float, Integer, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP
from geoalchemy2 import Geography
from typing import Optional
from app.models.base import Base, UUIDMixin, TimestampMixin
from app.domain.enums import UsageStatus

class UsageSession(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "usage_sessions"

    # ID của thiết bị được sử dụng
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), index=True, nullable=False)

    # ID người dùng/thao tác viên trong phiên, nếu DB có ghi nhận
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("people.id"), nullable=True)

    # ID người chịu trách nhiệm thiết bị trong phiên, nếu DB có ghi nhận
    responsible_person_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("people.id"), nullable=True)

    # Thời điểm bắt đầu sử dụng thiết bị
    started_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), index=True, nullable=False)

    # Thời điểm kết thúc sử dụng thiết bị
    ended_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True), nullable=True)

    # Vị trí bắt đầu phiên sử dụng
    start_location = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=True)

    # Vị trí kết thúc phiên sử dụng
    end_location = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=True)

    # Tổng quãng đường di chuyển trong phiên (m)
    distance_m: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Vận tốc trung bình trong phiên (m/s)
    avg_speed_mps: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Vận tốc lớn nhất trong phiên (m/s)
    max_speed_mps: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Tổng thời gian thiết bị đang di chuyển (giây)
    moving_duration_s: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    # Tổng thời gian thiết bị dừng (giây)
    stopped_duration_s: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    # Đường đi tổng hợp của phiên sử dụng
    route_geometry = mapped_column(Geography(geometry_type="LINESTRING", srid=4326), nullable=True)

    # Trạng thái của phiên sử dụng
    status: Mapped[UsageStatus] = mapped_column(Enum(UsageStatus), default=UsageStatus.ACTIVE, nullable=False)

    # Lý do kết thúc phiên sử dụng
    end_reason: Mapped[Optional[str]] = mapped_column(String, nullable=True)

    # Relationships

    # Liên kết tới thiết bị được sử dụng
    device = relationship("Device")

    # Liên kết tới người chịu trách nhiệm thiết bị
    person = relationship("Person", foreign_keys=[responsible_person_id])

    # Liên kết tới người dùng/thao tác viên, khi dữ liệu có phân biệt vai trò
    user = relationship("Person", foreign_keys=[user_id])

    @property
    def person_id(self) -> Optional[uuid.UUID]:
        return self.responsible_person_id or self.user_id
