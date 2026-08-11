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
    
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)
    person_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("people.id"), nullable=False)
    
    assigned_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False)
    unassigned_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    
    assignment_type: Mapped[AssignmentType] = mapped_column(Enum(AssignmentType), default=AssignmentType.RESPONSIBLE, nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), default=func.now(), nullable=False)
    
    # Relationships
    device = relationship("Device", back_populates="assignments")
    person = relationship("Person", back_populates="assignments")
