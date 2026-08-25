from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import settings

# `pool_pre_ping` kiểm tra kết nối trước khi cấp cho request. Nếu PostgreSQL,
# firewall hoặc dịch vụ cloud đã đóng một socket nhàn rỗi, SQLAlchemy loại bỏ
# socket hỏng và mở kết nối mới thay vì để request đầu tiên nhận lỗi mạng.
# Các giới hạn pool lấy từ `.env` để thay đổi theo tài nguyên máy mà không sửa code.
engine = create_async_engine(
    settings.database_url,
    echo=False,
    pool_pre_ping=True,
    pool_size=settings.database_pool_size,
    max_overflow=settings.database_max_overflow,
    pool_timeout=settings.database_pool_timeout_seconds,
    pool_recycle=settings.database_pool_recycle_seconds,
    connect_args={"timeout": settings.database_connect_timeout_seconds},
)

# Mỗi request nhận một AsyncSession độc lập. `expire_on_commit=False` giữ dữ
# liệu vừa ghi trong bộ nhớ để tránh truy vấn lại không cần thiết sau commit.
AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


# Context manager của SQLAlchemy tự đóng session ở cả nhánh thành công lẫn lỗi;
# không gọi `close()` lần hai để vòng đời kết nối ngắn gọn và nhất quán.
async def get_db():
    async with AsyncSessionLocal() as session:
        yield session
