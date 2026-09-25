"""Danh mục cell LTE nội bộ dùng làm anchor cho ước lượng vị trí.

Đây là dữ liệu được nhập từ nguồn đã kiểm duyệt, không phải dữ liệu modem tự
gửi. Chỉ bảng này có tọa độ anchor; tách nó khỏi telemetry ngăn một thiết bị
lỗi hoặc giả mạo làm thay đổi vị trí trạm cho toàn bộ hệ thống.
"""
from datetime import datetime

from geoalchemy2 import Geography
from sqlalchemy import BigInteger, Boolean, CheckConstraint, Float, Index, Integer, String, UniqueConstraint, true
from sqlalchemy.dialects.postgresql import TIMESTAMP
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDMixin


class CellTower(Base, UUIDMixin, TimestampMixin):
    """Một sector/cell được định vị bởi catalog đã được kiểm duyệt.

    ``site_key`` gom các sector cùng site để estimator không coi nhiều sector
    tại một trạm là nhiều anchor địa lý độc lập.
    """

    __tablename__ = "cell_towers"
    __table_args__ = (
        # Identity 5 thành phần là khóa lookup chính xác của LTE. MNC là string
        # để không làm mất số 0 đầu (ví dụ "04") khi nhập từ catalog.
        UniqueConstraint("rat", "mcc", "mnc", "tac", "cell_id", name="uq_cell_towers_identity"),
        CheckConstraint("rat = 'LTE'", name="ck_cell_towers_rat_lte"),
        CheckConstraint("mcc ~ '^[0-9]{3}$'", name="ck_cell_towers_mcc"),
        CheckConstraint("mnc ~ '^[0-9]{2,3}$'", name="ck_cell_towers_mnc"),
        CheckConstraint("tac BETWEEN 0 AND 65535", name="ck_cell_towers_tac"),
        CheckConstraint("cell_id BETWEEN 0 AND 268435455", name="ck_cell_towers_cell_id"),
        CheckConstraint("latitude BETWEEN -90 AND 90", name="ck_cell_towers_latitude"),
        CheckConstraint("longitude BETWEEN -180 AND 180", name="ck_cell_towers_longitude"),
        CheckConstraint("accuracy_m IS NULL OR accuracy_m >= 0", name="ck_cell_towers_accuracy"),
        CheckConstraint("pci IS NULL OR pci BETWEEN 0 AND 503", name="ck_cell_towers_pci"),
        # Worker luôn lọc active + identity trước; index này tránh scan toàn
        # catalog khi nhiều thiết bị gửi danh sách neighbor cùng lúc.
        Index("ix_cell_towers_active_identity", "is_active", "rat", "mcc", "mnc", "tac", "cell_id"),
    )

    rat: Mapped[str] = mapped_column(String(12), nullable=False, default="LTE")
    mcc: Mapped[str] = mapped_column(String(3), nullable=False)
    mnc: Mapped[str] = mapped_column(String(3), nullable=False)
    tac: Mapped[int] = mapped_column(Integer, nullable=False)
    cell_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    # PCI/EARFCN dùng đối chiếu và phân tích chất lượng catalog, không thuộc
    # unique identity vì các giá trị này có thể được tái sử dụng ở nơi khác.
    pci: Mapped[int | None] = mapped_column(Integer, nullable=True)
    earfcn: Mapped[int | None] = mapped_column(Integer, nullable=True)
    site_key: Mapped[str | None] = mapped_column(String(128), nullable=True)
    # Lat/lon phục vụ công thức centroid; Geography phục vụ truy vấn không gian
    # sau này và phải dùng thứ tự PostGIS POINT(longitude latitude).
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    location = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=False)
    # accuracy_m là chất lượng anchor do nguồn catalog công bố, được cộng vào
    # uncertainty của estimate, không phải accuracy của modem đang scan.
    accuracy_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    source: Mapped[str | None] = mapped_column(String(100), nullable=True)
    source_updated_at: Mapped[datetime | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    # Không xóa row khi catalog thu hồi/sai: tắt active để giữ lịch sử observation
    # vẫn truy vết được nhưng worker không dùng row này cho scan mới.
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default=true())
