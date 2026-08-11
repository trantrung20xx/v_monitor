from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings

from contextlib import asynccontextmanager
from app.services.mqtt_service import mqtt_service

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    try:
        await mqtt_service.start()
    except Exception as e:
        print(f"Failed to start MQTT service: {e}")
    yield
    # Shutdown
    await mqtt_service.stop()

app = FastAPI(
    title="v_monitor Backend",
    description="Backend API for device tracking & monitoring",
    version="1.0.0",
    lifespan=lifespan
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

from app.api.v1.router import api_router
app.include_router(api_router, prefix="/api/v1")

@app.get("/health")
async def health_check():
    return {"status": "ok"}
