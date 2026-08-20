from datetime import datetime, timezone
from typing import Any

import jwt
from pwdlib import PasswordHash

from app.core.config import settings
from app.models.user_account import UserAccount


_password_hash = PasswordHash.recommended()
_dummy_password_hash = _password_hash.hash("v-monitor-dummy-password")


class TokenValidationError(ValueError):
    pass


def hash_password(password: str) -> str:
    return _password_hash.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _password_hash.verify(password, password_hash)
    except Exception:
        return False


def verify_dummy_password(password: str) -> None:
    # Thực hiện cùng loại phép tính khi username không tồn tại để giảm chênh lệch thời gian.
    verify_password(password, _dummy_password_hash)


def _jwt_secret() -> str:
    if len(settings.jwt_secret) < 32:
        raise RuntimeError("JWT_SECRET phải có ít nhất 32 ký tự")
    return settings.jwt_secret


def create_access_token(user: UserAccount) -> str:
    now = datetime.now(timezone.utc)
    payload: dict[str, Any] = {
        "sub": str(user.id),
        "ver": user.token_version,
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "iat": now,
        "nbf": now,
    }
    # JWT không có exp để ứng dụng nội bộ duy trì đăng nhập lâu dài. Quyền truy
    # cập vẫn bị thu hồi tập trung bằng token_version trong user_accounts.
    return jwt.encode(
        payload,
        _jwt_secret(),
        algorithm=settings.jwt_algorithm,
    )


def decode_access_token(token: str) -> dict[str, Any]:
    try:
        return jwt.decode(
            token,
            _jwt_secret(),
            algorithms=[settings.jwt_algorithm],
            audience=settings.jwt_audience,
            issuer=settings.jwt_issuer,
            options={"require": ["iat", "nbf", "sub", "ver"]},
        )
    except (jwt.PyJWTError, RuntimeError, ValueError) as exc:
        raise TokenValidationError("Khóa đăng nhập không hợp lệ hoặc đã bị thu hồi") from exc
