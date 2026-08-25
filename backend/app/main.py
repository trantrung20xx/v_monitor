# Điểm lắp ráp FastAPI: quản lý vòng đời dịch vụ nền, middleware CORS,
# router API và health check phản ánh riêng PostgreSQL với MQTT.
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.core.config import settings
from app.core.database import AsyncSessionLocal, engine
from app.services.mqtt_service import mqtt_service
from app.services.presence_service import presence_service


logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Mọi tài nguyên nền được gắn với lifespan để test, reload và shutdown đều đi
    # qua cùng một trình tự, không tạo task ngay tại thời điểm import module.
    try:
        # Presence được khởi động trước để vòng quét trạng thái sẵn sàng độc lập với broker.
        # Presence và MQTT là dịch vụ nền độc lập. MQTT mất kết nối không được
        # làm API dừng; trạng thái thật được phản ánh tại `/health` để vận hành
        # có thể phân biệt lỗi broker với lỗi HTTP hoặc PostgreSQL.
        await presence_service.start()
        try:
            await mqtt_service.start()
        except Exception:
            # Broker lỗi lúc boot không chặn REST; Paho hoặc lần restart dịch vụ có thể kết nối lại.
            logger.exception("Không thể khởi động MQTT; API vẫn tiếp tục phục vụ")
        # `yield` chuyển quyền cho FastAPI phục vụ request cho tới khi ứng dụng dừng.
        yield
    finally:
        # Mỗi tài nguyên được dọn riêng để lỗi khi dừng một dịch vụ không ngăn
        # việc đóng dịch vụ còn lại và pool PostgreSQL.
        try:
            await mqtt_service.stop()
        except Exception:
            # Shutdown tiếp tục dù network loop MQTT không dừng sạch.
            logger.exception("Không thể dừng MQTT sạch sẽ")
        try:
            await presence_service.stop()
        except Exception:
            # Không để lỗi task presence bỏ qua bước giải phóng pool PostgreSQL.
            logger.exception("Không thể dừng bộ giám sát trạng thái thiết bị")
        # Dispose đóng toàn bộ socket còn trong pool khi tiến trình kết thúc.
        await engine.dispose()


# Metadata này phục vụ OpenAPI/Swagger; `lifespan` chịu trách nhiệm vòng đời MQTT,
# presence và pool database, không thay đổi đường dẫn nghiệp vụ của router.
app = FastAPI(
    title="v_monitor Backend",
    description="Backend giám sát vị trí và trạng thái thiết bị",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS chỉ áp dụng cho trình duyệt. Native app không chịu chính sách CORS nhưng vẫn
# dùng cùng API và xác thực Bearer. credentials chỉ bật khi origin đã được liệt kê cụ thể.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=settings.cors_origin_list != ["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

from app.api.v1.router import api_router

# Tất cả route nghiệp vụ nhận chung tiền tố, mặc định là `/api/v1`; `/health`
# được giữ ngoài tiền tố để công cụ giám sát hạ tầng truy cập đơn giản.
app.include_router(api_router, prefix=settings.api_prefix)


@app.get("/health")
async def health_check():
    # Kiểm tra bằng câu SQL tối thiểu để xác nhận không chỉ engine tồn tại mà pool
    # thật sự lấy được một kết nối PostgreSQL đang hoạt động.
    database_status = "connected"
    try:
        # Session chỉ dùng cho phép thử `SELECT 1` và được đóng ngay sau khối này.
        async with AsyncSessionLocal() as db:
            await db.execute(text("SELECT 1"))
    except Exception:
        # Health trả trạng thái suy giảm thay vì ném 500 để công cụ giám sát đọc chẩn đoán.
        database_status = "unavailable"
        logger.exception("Health check không thể kết nối cơ sở dữ liệu")

    # Snapshot MQTT tách trạng thái TCP, subscribe, hàng đợi và bộ đếm xử lý để
    # phân biệt broker mất kết nối với trường hợp chưa có thiết bị gửi dữ liệu.
    mqtt_status = mqtt_service.health_snapshot()
    # API chỉ báo `ok` khi cả database và kênh nhận MQTT sẵn sàng; tiến trình vẫn
    # phục vụ với `degraded` để giao diện và vận hành còn đọc được chẩn đoán.
    # Điều kiện dùng phép AND vì thiếu một trong ba năng lực đều làm pipeline chưa hoàn chỉnh.
    healthy = (
        database_status == "connected"
        and mqtt_status["connected"]
        and mqtt_status["subscribed"]
    )
    return {
        "status": "ok" if healthy else "degraded",
        "database": database_status,
        "mqtt": mqtt_status,
    }
