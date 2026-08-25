import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.services.mqtt_service import mqtt_service
from app.services.presence_service import presence_service


logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Hai dịch vụ nền độc lập: nhận telemetry và phát hiện thiết bị mất kết nối.
    await presence_service.start()
    try:
        await mqtt_service.start()
    except Exception:
        logger.exception("Không thể khởi động MQTT; API vẫn tiếp tục phục vụ")
    yield
    await mqtt_service.stop()
    await presence_service.stop()


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
