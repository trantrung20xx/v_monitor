from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.auth_dependencies import require_current_user
from app.core.database import get_db
from app.core.security import create_access_token
from app.models.user_account import UserAccount
from app.schemas.auth import (
    ChangePasswordRequest,
    LoginRequest,
    TokenResponse,
    UserResponse,
    UserSettingsResponse,
    UserSettingsUpdate,
)
from app.services.user_service import UserService


router = APIRouter()


@router.post("/login", response_model=TokenResponse)
async def login(
    credentials: LoginRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
):
    user = await UserService.authenticate(
        db,
        credentials.username,
        credentials.password,
    )
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Username hoặc mật khẩu không chính xác",
            headers={"WWW-Authenticate": "Bearer"},
        )
    token = create_access_token(user)
    return TokenResponse(
        access_token=token,
        user=UserResponse.model_validate(user),
    )


@router.get("/me", response_model=UserResponse)
async def read_current_user(
    user: Annotated[UserAccount, Depends(require_current_user)],
):
    return user


@router.post("/change-password", status_code=status.HTTP_204_NO_CONTENT)
async def change_password(
    password_in: ChangePasswordRequest,
    user: Annotated[UserAccount, Depends(require_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    changed = await UserService.change_own_password(
        db,
        user,
        password_in.current_password,
        password_in.new_password,
    )
    if not changed:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Mật khẩu hiện tại không chính xác",
        )


@router.get("/settings", response_model=UserSettingsResponse)
async def read_current_settings(
    user: Annotated[UserAccount, Depends(require_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    return await UserService.get_settings(db, user.id)


@router.patch("/settings", response_model=UserSettingsResponse)
async def update_current_settings(
    settings_in: UserSettingsUpdate,
    user: Annotated[UserAccount, Depends(require_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    return await UserService.update_settings(db, user, settings_in)
