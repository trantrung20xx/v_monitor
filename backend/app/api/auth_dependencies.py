import uuid
from typing import Annotated, Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import AsyncSessionLocal, get_db
from app.core.security import TokenValidationError, decode_access_token
from app.domain.enums import UserRole
from app.models.user_account import UserAccount


_bearer = HTTPBearer(auto_error=False)


def _authentication_error() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Thông tin đăng nhập không hợp lệ hoặc đã bị thu hồi",
        headers={"WWW-Authenticate": "Bearer"},
    )


async def _load_user_from_token(
    token: str,
    db: AsyncSession,
) -> UserAccount:
    try:
        payload = decode_access_token(token)
        user_id = uuid.UUID(str(payload["sub"]))
        token_version = int(payload["ver"])
    except (TokenValidationError, KeyError, TypeError, ValueError):
        raise _authentication_error()

    user = await db.get(UserAccount, user_id)
    if (
        user is None
        or not user.is_active
        or user.token_version != token_version
    ):
        raise _authentication_error()
    return user


async def get_optional_current_user(
    credentials: Annotated[
        Optional[HTTPAuthorizationCredentials],
        Depends(_bearer),
    ],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Optional[UserAccount]:
    if credentials is None:
        return None
    return await _load_user_from_token(credentials.credentials, db)


async def require_current_user(
    user: Annotated[Optional[UserAccount], Depends(get_optional_current_user)],
) -> UserAccount:
    if user is None:
        raise _authentication_error()
    return user


async def require_viewer_if_enabled(
    user: Annotated[Optional[UserAccount], Depends(get_optional_current_user)],
) -> Optional[UserAccount]:
    if settings.auth_required and user is None:
        raise _authentication_error()
    return user


def _require_admin_role(user: UserAccount) -> UserAccount:
    if user.role != UserRole.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Chỉ tài khoản quản trị được phép thực hiện thao tác này",
        )
    return user


async def require_admin(
    user: Annotated[UserAccount, Depends(require_current_user)],
) -> UserAccount:
    return _require_admin_role(user)


async def require_admin_if_enabled(
    user: Annotated[Optional[UserAccount], Depends(get_optional_current_user)],
) -> Optional[UserAccount]:
    if not settings.auth_required:
        return user
    if user is None:
        raise _authentication_error()
    return _require_admin_role(user)


async def authenticate_websocket_token(token: Optional[str]) -> Optional[UserAccount]:
    # Mỗi lần gọi đều đọc user_accounts để thay đổi mật khẩu, quyền hoặc trạng
    # thái tài khoản có hiệu lực ngay mà không cần bảng phiên hay blacklist.
    if not token:
        if settings.auth_required:
            raise _authentication_error()
        return None
    async with AsyncSessionLocal() as db:
        return await _load_user_from_token(token, db)
