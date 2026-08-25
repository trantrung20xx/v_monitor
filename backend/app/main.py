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
    try:
        # Presence và MQTT là dịch vụ nền độc lập. MQTT mất kết nối không được
        # làm API dừng; trạng thái thật được phản ánh tại `/health` để vận hành
        # có thể phân biệt lỗi broker với lỗi HTTP hoặc PostgreSQL.
        await presence_service.start()
        try:
            await mqtt_service.start()
        except Exception:
            logger.exception("Không thể khởi động MQTT; API vẫn tiếp tục phục vụ")
        yield
    finally:
        # Mỗi tài nguyên được dọn riêng để lỗi khi dừng một dịch vụ không ngăn
        # việc đóng dịch vụ còn lại và pool PostgreSQL.
        try:
            await mqtt_service.stop()
        except Exception:
            logger.exception("Không thể dừng MQTT sạch sẽ")
        try:
            await presence_service.stop()
        except Exception:
            logger.exception("Không thể dừng bộ giám sát trạng thái thiết bị")
        await engine.dispose()


app = FastAPI(
    title="v_monitor Backend",
    description="Backend giám sát vị trí và trạng thái thiết bị",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=settings.cors_origin_list != ["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

from app.api.v1.router import api_router

app.include_router(api_router, prefix=settings.api_prefix)


@app.get("/health")
async def health_check():
    database_status = "connected"
    try:
        async with AsyncSessionLocal() as db:
            await db.execute(text("SELECT 1"))
    except Exception:
        database_status = "unavailable"
        logger.exception("Health check không thể kết nối cơ sở dữ liệu")

    mqtt_status = mqtt_service.health_snapshot()
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
