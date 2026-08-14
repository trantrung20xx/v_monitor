from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from app.core.config import settings

# Khởi tạo engine kết nối bất đồng bộ (async) tới PostgreSQL
# Tối ưu hóa Connection Pooling (pool_size, max_overflow) để chịu tải cao
engine = create_async_engine(
    settings.database_url,
    echo=False, # Tắt in log SQL ra console để tăng hiệu năng production
    future=True,
    pool_size=20,          # Số kết nối tối đa luôn duy trì trong Pool
    max_overflow=10,       # Số kết nối vượt mức có thể tạo thêm khi quá tải
    pool_recycle=1800,     # Khởi tạo lại kết nối sau mỗi 30 phút để tránh lỗi timeout
)

# Tạo một factory (nhà máy) chuyên sản xuất các Session (phiên làm việc) với cơ sở dữ liệu
AsyncSessionLocal = async_sessionmaker(
    bind=engine, 
    class_=AsyncSession, 
    expire_on_commit=False # Không tự động làm hết hạn các đối tượng sau khi commit (giúp tiết kiệm truy vấn)
)

# Generator (hàm sinh) cung cấp Session cho từng Request của FastAPI
# Đảm bảo Session luôn được đóng an toàn sau khi sử dụng xong
async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
