from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from contextlib import asynccontextmanager
from app.services.mqtt_service import mqtt_service

# Quản lý vòng đời của ứng dụng FastAPI.
# Các lệnh trước từ khóa `yield` sẽ chạy khi server khởi động (Startup).
# Các lệnh sau từ khóa `yield` sẽ chạy khi server chuẩn bị tắt (Shutdown).
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Khởi động dịch vụ MQTT chạy ngầm để liên tục lắng nghe dữ liệu từ thiết bị
    try:
        await mqtt_service.start()
    except Exception as e:
        print(f"Lỗi khi khởi động dịch vụ MQTT: {e}")

    yield

    # Ngắt kết nối MQTT an toàn khi tắt server để không bị treo luồng (thread)
    await mqtt_service.stop()

# Khởi tạo đối tượng ứng dụng FastAPI chính
app = FastAPI(
    title="v_monitor Backend",
    description="Hệ thống Backend API quản lý và theo dõi thiết bị",
    version="1.0.0",
    lifespan=lifespan
)

# Cấu hình CORS (Cross-Origin Resource Sharing)
# Cho phép ứng dụng Frontend (Flutter Web/Mobile) gọi API từ các domain khác mà không bị chặn
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # Trong môi trường thực tế, nên giới hạn domain cụ thể thay vì "*"
    allow_credentials=True,
    allow_methods=["*"], # Cho phép mọi phương thức (GET, POST, PUT, DELETE, v.v.)
    allow_headers=["*"], # Cho phép mọi headers
)

# Đăng ký các router (đường dẫn API) từ thư mục api/v1
from app.api.v1.router import api_router
app.include_router(api_router, prefix="/api/v1")

# Endpoint để kiểm tra xem server có đang hoạt động hay không
@app.get("/health")
async def health_check():
    return {"status": "ok"}
