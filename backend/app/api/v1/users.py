import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.auth_dependencies import require_admin
from app.core.database import get_db
from app.models.user_account import UserAccount
from app.schemas.auth import (
    ResetPasswordRequest,
    UserCreate,
    UserResponse,
    UserUpdate,
)
from app.services.user_service import (
    DuplicateAccountError,
    LastAdministratorError,
    UserService,
)


router = APIRouter()


@router.get("/", response_model=list[UserResponse])
async def list_users(
    _: Annotated[UserAccount, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=1000),
):
    return await UserService.list_accounts(db, skip=skip, limit=limit)


@router.post("/", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    account_in: UserCreate,
    admin: Annotated[UserAccount, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    try:
        return await UserService.create_account(
            db,
            account_in,
            actor_user_id=admin.id,
        )
    except DuplicateAccountError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc


@router.patch("/{user_id}", response_model=UserResponse)
async def update_user(
    user_id: uuid.UUID,
    account_in: UserUpdate,
    admin: Annotated[UserAccount, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    try:
        user = await UserService.update_account(
            db,
            user_id,
            account_in,
            actor_user_id=admin.id,
        )
    except (DuplicateAccountError, LastAdministratorError) as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    if user is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy tài khoản")
    return user


@router.post("/{user_id}/reset-password", status_code=status.HTTP_204_NO_CONTENT)
async def reset_user_password(
    user_id: uuid.UUID,
    password_in: ResetPasswordRequest,
    admin: Annotated[UserAccount, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    user = await UserService.reset_password(
        db,
        user_id,
        password_in.new_password,
        actor_user_id=admin.id,
    )
    if user is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy tài khoản")
