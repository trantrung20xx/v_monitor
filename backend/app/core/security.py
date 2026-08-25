# Các hàm bảo mật thuần: băm/kiểm tra mật khẩu và phát/giải mã JWT.
# File không truy cập database; trạng thái tài khoản được kiểm tra ở dependency và service.
from datetime import datetime, timezone
from typing import Any

import jwt
from pwdlib import PasswordHash

from app.core.config import settings
from app.models.user_account import UserAccount


# `recommended()` chọn thuật toán và tham số băm an toàn theo phiên bản pwdlib đang
# cài. Mật khẩu chỉ được so sánh qua hash; chuỗi gốc không được lưu vào database.
_password_hash = PasswordHash.recommended()
# Hash giả được tạo một lần khi tiến trình khởi động. Nhánh username không tồn tại
# vẫn chạy phép xác minh tương đương để khó suy đoán tài khoản qua thời gian phản hồi.
_dummy_password_hash = _password_hash.hash("v-monitor-dummy-password")


class TokenValidationError(ValueError):
    # Lỗi nội bộ thống nhất cho mọi trường hợp JWT sai chữ ký, sai claim hoặc sai cấu hình.
    # Dependency chuyển lỗi này thành HTTP 401 mà không lộ nguyên nhân kỹ thuật cụ thể.
    pass


def hash_password(password: str) -> str:
    # Tạo chuỗi hash có kèm salt và tham số thuật toán để lưu vào password_hash.
    return _password_hash.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    # Bao toàn bộ lỗi parse/hash thành False để dữ liệu hash hỏng không làm endpoint
    # đăng nhập trả lỗi 500 hoặc tiết lộ cấu trúc lưu mật khẩu.
    # Nhánh thành công chỉ trả boolean của thư viện, không tự so sánh chuỗi hash.
    try:
        return _password_hash.verify(password, password_hash)
    except Exception:
        # Hash sai định dạng và lỗi thuật toán đều được xem như mật khẩu không khớp.
        return False


def verify_dummy_password(password: str) -> None:
    # Thực hiện cùng loại phép tính khi username không tồn tại để giảm chênh lệch thời gian.
    verify_password(password, _dummy_password_hash)


def _jwt_secret() -> str:
    # Kiểm tra lại tại điểm ký/giải mã để bảo vệ cả trường hợp Settings bị thay thế
    # trong test hoặc được khởi tạo theo cách khác ngoài validator thông thường.
    # Không tự sinh secret vì mỗi lần khởi động sinh khóa mới sẽ vô hiệu hóa toàn bộ
    # token và che giấu lỗi cấu hình production.
    if len(settings.jwt_secret) < 32:
        raise RuntimeError("JWT_SECRET phải có ít nhất 32 ký tự")
    return settings.jwt_secret


def create_access_token(user: UserAccount) -> str:
    # Thời điểm ký dùng UTC; PyJWT chuyển datetime thành NumericDate chuẩn JWT.
    now = datetime.now(timezone.utc)
    payload: dict[str, Any] = {
        # `sub` định danh tài khoản; `ver` là phiên bản quyền dùng để thu hồi token.
        "sub": str(user.id),
        "ver": user.token_version,
        # `iss` và `aud` ngăn token hợp lệ của hệ thống khác được dùng nhầm tại đây.
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        # `iat` ghi lúc phát hành; `nbf` không cho dùng token trước thời điểm phát hành.
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
    # Chỉ chấp nhận đúng thuật toán đã cấu hình, đúng issuer/audience và đủ bốn
    # claim bắt buộc. Trạng thái active/token_version được kiểm tra tiếp tại database.
    # PyJWT thực hiện đồng thời kiểm tra chữ ký, thời điểm `nbf`, issuer và audience.
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
        # Không truyền thông điệp gốc ra API vì nội dung có thể tiết lộ claim hoặc
        # nguyên nhân chữ ký thất bại; exception gốc vẫn được nối để debug nội bộ.
        raise TokenValidationError("Khóa đăng nhập không hợp lệ hoặc đã bị thu hồi") from exc
