from fastapi import APIRouter
from app.api.v1 import devices, tracking, websocket

api_router = APIRouter()
api_router.include_router(devices.router, prefix="/devices", tags=["devices"])
api_router.include_router(tracking.router, prefix="/tracking", tags=["tracking"])
api_router.include_router(websocket.router, prefix="", tags=["realtime"])
