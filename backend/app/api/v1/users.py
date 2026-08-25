# API quản trị tài khoản nội bộ: liệt kê, tạo, sửa và đặt lại mật khẩu.
# Toàn bộ router yêu cầu ADMIN; tài khoản hiện tại dùng nhóm API auth riêng.
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
    # Phân trang có trần 1000 để màn quản trị không tải vô hạn trong một request.
    return await UserService.list_accounts(db, skip=skip, limit=limit)


@router.post("/", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    account_in: UserCreate,
    admin: Annotated[UserAccount, Depends(require_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    # Admin hiện tại được ghi thành actor của audit; lỗi trùng từ service chuyển
    # thành 409 vì request hợp lệ về cấu trúc nhưng xung đột dữ liệu hiện có.
    try:
        # Service chịu trách nhiệm hash mật khẩu; route không đọc hoặc lưu password_hash.
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
    # Service bảo vệ quản trị viên hoạt động cuối cùng và thu hồi token khi quyền
    # hoặc trạng thái đăng nhập thay đổi.
    try:
        # actor là admin đang thực hiện thao tác, entity là user_id trong path.
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
    # UUID đúng định dạng nhưng không có bản ghi được chuyển thành 404.
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
    # Đặt lại mật khẩu đồng thời xóa khóa tạm và tăng token_version, buộc mọi phiên
    # cũ của tài khoản mục tiêu đăng nhập lại.
    user = await UserService.reset_password(
        db,
        user_id,
        password_in.new_password,
        actor_user_id=admin.id,
    )
    # Service trả None khi tài khoản biến mất hoặc chưa từng tồn tại.
    if user is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy tài khoản")
