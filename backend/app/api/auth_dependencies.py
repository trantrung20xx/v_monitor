# Tập trung dependency xác thực của FastAPI: đọc Bearer token, kiểm tra tài khoản
# còn hoạt động và áp dụng quyền USER/ADMIN trước khi endpoint nghiệp vụ chạy.
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


# `auto_error=False` cho phép cùng dependency phục vụ cả endpoint bắt buộc đăng nhập
# và endpoint có thể tắt xác thực trong môi trường kiểm thử được cấu hình rõ ràng.
_bearer = HTTPBearer(auto_error=False)


def _authentication_error() -> HTTPException:
    # Dùng một thông báo chung cho thiếu, sai và đã thu hồi token để không tiết lộ
    # tài khoản có tồn tại hay nguyên nhân xác thực thất bại.
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Thông tin đăng nhập không hợp lệ hoặc đã bị thu hồi",
        headers={"WWW-Authenticate": "Bearer"},
    )


async def _load_user_from_token(
    token: str,
    db: AsyncSession,
) -> UserAccount:
    # Bước 1: xác minh chữ ký/claim rồi chuyển `sub` thành UUID và `ver` thành số.
    # Mọi kiểu dữ liệu sai đều được quy về cùng lỗi xác thực.
    try:
        # `sub` liên kết token với khóa chính user; `ver` liên kết với phiên bản quyền.
        payload = decode_access_token(token)
        user_id = uuid.UUID(str(payload["sub"]))
        token_version = int(payload["ver"])
    except (TokenValidationError, KeyError, TypeError, ValueError):
        raise _authentication_error()

    # Bước 2: đọc tài khoản thật ở mỗi request. Token chỉ hợp lệ khi tài khoản còn
    # hoạt động và phiên bản quyền trong token vẫn khớp với database.
    user = await db.get(UserAccount, user_id)
    # Một điều kiện thất bại là đủ từ chối: user bị xóa, bị khóa đăng nhập hoặc token
    # được phát trước lần đổi mật khẩu/thay đổi quyền gần nhất.
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
    # Trả None khi request không mang Bearer token; nếu có token thì vẫn xác minh đầy đủ.
    # Dependency tùy chọn không có nghĩa token sai được bỏ qua; chỉ trường hợp thiếu token trả None.
    if credentials is None:
        return None
    return await _load_user_from_token(credentials.credentials, db)


async def require_current_user(
    user: Annotated[Optional[UserAccount], Depends(get_optional_current_user)],
) -> UserAccount:
    # Nâng dependency tùy chọn thành bắt buộc cho các endpoint luôn cần đăng nhập.
    if user is None:
        raise _authentication_error()
    return user


async def require_viewer_if_enabled(
    user: Annotated[Optional[UserAccount], Depends(get_optional_current_user)],
) -> Optional[UserAccount]:
    # Khi AUTH_REQUIRED=true, mọi API đọc dữ liệu cần tài khoản hợp lệ. Nhánh false
    # chỉ giữ khả năng chạy môi trường kiểm thử đã chủ động tắt xác thực.
    if settings.auth_required and user is None:
        raise _authentication_error()
    return user


def _require_admin_role(user: UserAccount) -> UserAccount:
    # Phân biệt xác thực và phân quyền: tài khoản hợp lệ nhưng không phải ADMIN nhận 403.
    if user.role != UserRole.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Chỉ tài khoản quản trị được phép thực hiện thao tác này",
        )
    return user


async def require_admin(
    user: Annotated[UserAccount, Depends(require_current_user)],
) -> UserAccount:
    # Dependency dành cho endpoint quản trị luôn yêu cầu xác thực, không xét cờ môi trường.
    return _require_admin_role(user)


async def require_admin_if_enabled(
    user: Annotated[Optional[UserAccount], Depends(get_optional_current_user)],
) -> Optional[UserAccount]:
    # Biến thể tương thích môi trường test; production với AUTH_REQUIRED=true vẫn
    # bắt buộc tài khoản ADMIN và backend là lớp quyết định quyền cuối cùng.
    # Khi auth tắt rõ ràng, endpoint được phép chạy mà không ép một user giả.
    if not settings.auth_required:
        return user
    # Khi auth bật, thiếu token là lỗi 401 trước khi xét vai trò.
    if user is None:
        raise _authentication_error()
    # User hợp lệ nhưng không phải ADMIN được phân loại thành lỗi quyền 403.
    return _require_admin_role(user)


async def authenticate_websocket_token(token: Optional[str]) -> Optional[UserAccount]:
    # Mỗi lần gọi đều đọc user_accounts để thay đổi mật khẩu, quyền hoặc trạng
    # thái tài khoản có hiệu lực ngay mà không cần bảng phiên hay blacklist.
    if not token:
        # Production yêu cầu token; môi trường chủ động tắt auth được phép trả None.
        if settings.auth_required:
            raise _authentication_error()
        return None
    # Session ngắn chỉ tồn tại trong lần xác thực/heartbeat và tự đóng sau truy vấn.
    async with AsyncSessionLocal() as db:
        return await _load_user_from_token(token, db)
