import uuid
from datetime import datetime
from sqlalchemy import ForeignKey, String, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP, JSONB
from sqlalchemy import func
from typing import Optional
from app.models.base import Base, UUIDMixin
from app.domain.enums import ProcessingStatus

class TelemetryMessage(Base, UUIDMixin):
    __tablename__ = "telemetry_messages"
    
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), index=True, nullable=False)
    
    received_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False)
    measured_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    
    protocol: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    message_type: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    schema_version: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    
    processing_status: Mapped[ProcessingStatus] = mapped_column(Enum(ProcessingStatus), default=ProcessingStatus.PENDING, nullable=False)
    processing_error: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), default=func.now(), nullable=False)
    
    # Relationships
    device = relationship("Device")
