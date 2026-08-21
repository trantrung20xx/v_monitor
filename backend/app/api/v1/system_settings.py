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
    return await system_settings_service.get_settings(db)


@router.patch("/settings", response_model=SystemSettingsResponse)
async def update_system_settings(
    settings_in: SystemSettingsUpdate,
    admin: Annotated[UserAccount, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    updated = await system_settings_service.update_settings(
        db,
        settings_in,
        actor=admin,
    )
    payload = SystemSettingsResponse.model_validate(updated).model_dump()
    await realtime_service.broadcast_telemetry(
        {"type": "SYSTEM_SETTINGS_UPDATED", "settings": payload}
    )
    return updated
