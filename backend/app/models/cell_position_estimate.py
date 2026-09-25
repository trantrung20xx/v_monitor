"""Kết quả vị trí ước lượng từ radio scan, tách biệt hoàn toàn với GPS history.

Estimate luôn gắn với đúng một telemetry để tái lập được đầu vào. Nó không phải
LocationSample và không được dùng để thay thế GPS current/history của client cũ.
"""
import uuid
from datetime import datetime

from geoalchemy2 import Geography
from sqlalchemy import CheckConstraint, Float, ForeignKey, Index, Integer, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, UUIDMixin


class CellPositionEstimate(Base, UUIDMixin):
    __tablename__ = "cell_position_estimates"
    __table_args__ = (
        # Một telemetry LTE chỉ sinh tối đa một kết quả, kể cả khi estimate là
        # NO_MATCH hoặc REJECTED_ACCURACY. Điều này hỗ trợ idempotency QoS 1.
        UniqueConstraint("telemetry_message_id", name="uq_cell_position_estimates_message"),
        CheckConstraint("status IN ('ESTIMATED', 'NO_MATCH', 'REJECTED_ACCURACY')", name="ck_cell_position_estimates_status"),
        CheckConstraint("latitude IS NULL OR latitude BETWEEN -90 AND 90", name="ck_cell_position_estimates_latitude"),
        CheckConstraint("longitude IS NULL OR longitude BETWEEN -180 AND 180", name="ck_cell_position_estimates_longitude"),
        CheckConstraint("(latitude IS NULL) = (longitude IS NULL)", name="ck_cell_position_estimates_coordinate_pair"),
        CheckConstraint("accuracy_m IS NULL OR accuracy_m >= 0", name="ck_cell_position_estimates_accuracy"),
        CheckConstraint("confidence BETWEEN 0 AND 1", name="ck_cell_position_estimates_confidence"),
        # Dùng lấy estimate mới nhất theo thời điểm modem đo mà không quét lịch sử.
        Index("ix_cell_position_estimates_device_measured", "device_id", "measured_at", "id"),
    )

    device_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("devices.id", ondelete="CASCADE"), nullable=False
    )
    telemetry_message_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("telemetry_messages.id", ondelete="CASCADE"), nullable=False
    )
    measured_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False)
    received_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False)
    # method version hóa thuật toán để kết quả lịch sử vẫn giải thích được sau khi
    # thuật toán thay đổi; status quyết định lat/lon có được công bố hay không.
    method: Mapped[str] = mapped_column(String(80), nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False)
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    location = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=True)
    accuracy_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    # confidence xếp hạng UX, còn accuracy_m là phạm vi bất định thực tế hơn;
    # cả hai được lưu cùng diagnostics để truy vết quyết định estimator.
    confidence: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    matched_cell_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    diagnostics_json: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
