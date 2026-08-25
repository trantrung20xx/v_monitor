# Router gốc của phiên bản API v1. Mỗi router con giữ một nhóm nghiệp vụ độc lập
# nhưng cùng được gắn dưới API_PREFIX do cấu hình backend quy định.
from fastapi import APIRouter
from app.api.v1 import auth, devices, geocoding, system_settings, tracking, users, websocket

api_router = APIRouter()
# Thứ tự include không thay đổi hợp đồng URL; prefix phân tách rõ từng miền nghiệp vụ.
api_router.include_router(devices.router, prefix="/devices", tags=["devices"])
api_router.include_router(tracking.router, prefix="/tracking", tags=["tracking"])
api_router.include_router(geocoding.router, prefix="/geocoding", tags=["geocoding"])
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(users.router, prefix="/users", tags=["users"])
api_router.include_router(
    system_settings.router,
    prefix="/system",
    tags=["system-settings"],
)
# WebSocket dùng `/ws` trực tiếp dưới API_PREFIX nên router con không cần prefix riêng.
api_router.include_router(websocket.router, prefix="", tags=["realtime"])
