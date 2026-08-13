import uuid
from datetime import datetime
from sqlalchemy import ForeignKey, String, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP
from sqlalchemy import func
from typing import Optional
from app.models.base import Base, UUIDMixin
from app.domain.enums import AssignmentType

class DeviceAssignment(Base, UUIDMixin):
    __tablename__ = "device_assignments"

    # ID của thiết bị được phân công
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)

    # ID của người được phân công sử dụng thiết bị
    person_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("people.id"), nullable=False)

    # Thời điểm bắt đầu phân công thiết bị cho người sử dụng
    assigned_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False)

    # Thời điểm kết thúc phân công; NULL nghĩa là vẫn đang phụ trách
    unassigned_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True), nullable=True)

    # Loại hình phân công thiết bị
    assignment_type: Mapped[AssignmentType] = mapped_column(Enum(AssignmentType), default=AssignmentType.RESPONSIBLE, nullable=False)

    # Ghi chú bổ sung về việc phân công
    notes: Mapped[Optional[str]] = mapped_column(String, nullable=True)

    # Thời điểm bản ghi phân công được tạo trong database
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), default=func.now(), nullable=False)

    # Relationships

    # Liên kết tới thiết bị được phân công
    device = relationship("Device", back_populates="assignments")

    # Liên kết tới người được phân công
    person = relationship("Person", back_populates="assignments")
