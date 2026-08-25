# Bảng lịch sử GPS bất biến: mỗi hàng là một phép đo tại measured_at.
# Tọa độ dùng cho bản đồ; tốc độ/hướng/độ chính xác/vệ tinh mô tả chất lượng và chuyển động.
import uuid
from datetime import datetime
from sqlalchemy import CheckConstraint, Float, ForeignKey, Index, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID, TIMESTAMP
from sqlalchemy import func
from geoalchemy2 import Geography
from typing import Optional
from app.models.base import Base, UUIDMixin

class LocationSample(Base, UUIDMixin):
    # measured_at là lúc đo, received_at là lúc nhận; source/source_message_id truy gói nguồn.
    # accuracy_m và satellite_count mô tả chất lượng, không dùng thay cho tọa độ.
    __tablename__ = "location_samples"
    # Chỉ mục (device, measured_at, id) phục vụ cả lịch sử tăng/giảm thời gian;
    # id phá hòa khi hai mẫu có cùng measured_at để thứ tự luôn xác định.
    __table_args__ = (
        Index(
            "ix_location_samples_device_measured_id",
            "device_id",
            "measured_at",
            "id",
        ),
        UniqueConstraint(
            "source_message_id",
            name="uq_location_samples_source_message_id",
        ),
        CheckConstraint(
            "latitude BETWEEN -90 AND 90",
            name="ck_location_samples_latitude",
        ),
        CheckConstraint(
            "longitude BETWEEN -180 AND 180",
            name="ck_location_samples_longitude",
        ),
        CheckConstraint(
            "speed_mps IS NULL OR speed_mps >= 0",
            name="ck_location_samples_speed",
        ),
        CheckConstraint(
            "heading_deg IS NULL OR (heading_deg >= 0 AND heading_deg < 360)",
            name="ck_location_samples_heading",
        ),
        CheckConstraint(
            "accuracy_m IS NULL OR accuracy_m >= 0",
            name="ck_location_samples_accuracy",
        ),
        CheckConstraint(
            "satellite_count IS NULL OR satellite_count >= 0",
            name="ck_location_samples_satellites",
        ),
    )
    
    # Mỗi mẫu luôn thuộc thiết bị đã đăng ký; khóa ngoại từ chối UUID không tồn tại.
    device_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("devices.id"), nullable=False)
    
    # measured_at sắp xếp hành trình theo đồng hồ thiết bị; received_at đo lúc backend
    # tiếp nhận và giúp đánh giá độ trễ truyền tin.
    measured_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), index=True, nullable=False)
    received_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False)
    
    # latitude/longitude thuận tiện cho API; location geography hỗ trợ phép toán và
    # chỉ mục không gian PostGIS. Ba trường biểu diễn cùng một điểm đo.
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    location = mapped_column(Geography(geometry_type='POINT', srid=4326), nullable=False)
    
    # Các thuộc tính GPS tùy chọn giữ nguyên đơn vị chuẩn của domain: mét, m/s, độ.
    # null nghĩa là thiết bị không cung cấp, không được diễn giải thành số 0.
    altitude_m: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    speed_mps: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    heading_deg: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    accuracy_m: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    satellite_count: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    
    # source mô tả kênh nghiệp vụ; source_message_id liên kết ngược telemetry MQTT
    # và đồng thời chống một telemetry tạo hai mẫu vị trí.
    source: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    source_message_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("telemetry_messages.id", ondelete="SET NULL"),
        nullable=True,
    )
    
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), default=func.now(), nullable=False)
    
    # Các quan hệ dữ liệu
    device = relationship("Device")
