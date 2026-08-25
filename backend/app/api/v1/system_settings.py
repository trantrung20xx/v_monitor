# API cấu hình vận hành dùng chung toàn hệ thống. USER được đọc để hiển thị đúng
# trạng thái; chỉ ADMIN được thay đổi ngưỡng và mọi thay đổi đều có audit log.
from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.auth_dependencies import require_admin, require_current_user
from app.core.database import get_db
from app.models.user_account import UserAccount
from app.schemas.system_settings import (
    SystemSettingsResponse,
    SystemSettingsUpdate,
)
from app.services.realtime_service import realtime_service
from app.services.system_settings_service import system_settings_service


router = APIRouter()


@router.get("/settings", response_model=SystemSettingsResponse)
async def read_system_settings(
    _: Annotated[UserAccount, Depends(require_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    # Mọi tài khoản hợp lệ được đọc để client dùng cùng ngưỡng khi resolve trạng thái.
    # Service tự tạo dòng singleton mặc định nếu database cũ chưa có bản ghi.
    return await system_settings_service.get_settings(db)


@router.patch("/settings", response_model=SystemSettingsResponse)
async def update_system_settings(
    settings_in: SystemSettingsUpdate,
    admin: Annotated[UserAccount, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    # Chỉ ADMIN qua dependency. Service khóa dòng, ghi audit, commit và cập nhật cache
    # trước khi route phát cấu hình đã chuẩn hóa tới mọi frontend.
    updated = await system_settings_service.update_settings(
        db,
        settings_in,
        actor=admin,
    )
    # Schema response loại thuộc tính ORM và tạo payload JSON ổn định cho WebSocket.
    payload = SystemSettingsResponse.model_validate(updated).model_dump()
    await realtime_service.broadcast_telemetry(
        {"type": "SYSTEM_SETTINGS_UPDATED", "settings": payload}
    )
    return updated
