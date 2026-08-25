# Hợp đồng request/response cho đăng nhập, tài khoản và tùy chọn cá nhân.
# Validator chuẩn hóa chuỗi, email, múi giờ và ngăn PATCH rỗng trước khi vào service.
import uuid
from datetime import datetime
from typing import Any, Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import Field, field_validator, model_validator

from app.domain.enums import UserRole
from app.schemas.common import BaseSchema


class LoginRequest(BaseSchema):
    # username nhận dạng tài khoản; password chỉ tồn tại trong request và không được phản hồi.
    username: str = Field(min_length=3, max_length=50)
    password: str = Field(min_length=1, max_length=128)

    @field_validator("username")
    @classmethod
    def _normalize_username(cls, value: str) -> str:
        # Khoảng trắng ngoài không thuộc định danh và được loại trước khi truy vấn.
        normalized = value.strip()
        # Kiểm tra lại sau trim vì Field kiểm tra độ dài trên chuỗi đầu vào ban đầu.
        if len(normalized) < 3:
            raise ValueError("Username phải có ít nhất 3 ký tự không tính khoảng trắng")
        return normalized


class UserResponse(BaseSchema):
    # Dữ liệu an toàn để trả frontend, cố ý không có password_hash và trạng thái khóa nội bộ.
    id: uuid.UUID
    username: str
    full_name: str
    email: Optional[str] = None
    role: UserRole
    is_active: bool
    last_login_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime


class TokenResponse(BaseSchema):
    # access_token là JWT dùng cho HTTP/WS; token_type mô tả chuẩn Bearer.
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


class UserCreate(BaseSchema):
    # Dữ liệu ADMIN cung cấp khi tạo tài khoản; role/is_active xác định quyền ban đầu.
    username: str = Field(min_length=3, max_length=50)
    password: str = Field(min_length=8, max_length=128)
    full_name: str = Field(min_length=1, max_length=255)
    email: Optional[str] = Field(default=None, max_length=320)
    role: UserRole = UserRole.USER
    is_active: bool = True

    @field_validator("username")
    @classmethod
    def _strip_username(cls, value: str) -> str:
        # Lưu username đã chuẩn hóa để so sánh không bị ảnh hưởng bởi khoảng trắng.
        normalized = value.strip()
        if len(normalized) < 3:
            raise ValueError("Username phải có ít nhất 3 ký tự không tính khoảng trắng")
        return normalized

    @field_validator("full_name")
    @classmethod
    def _strip_full_name(cls, value: str) -> str:
        # Tên hiển thị cho phép khoảng trắng bên trong nhưng không cho phép toàn khoảng trắng.
        normalized = value.strip()
        if not normalized:
            raise ValueError("Tên hiển thị không được chỉ chứa khoảng trắng")
        return normalized

    @field_validator("email")
    @classmethod
    def _strip_email(cls, value: Optional[str]) -> Optional[str]:
        # None giữ nghĩa không khai báo email.
        if value is None:
            return None
        # Email được lưu chữ thường để kiểm tra unique không phân biệt hoa thường.
        normalized = value.strip().lower()
        # Chuỗi rỗng sau trim được quy về None thay vì lưu giá trị rỗng.
        return normalized or None


class UserUpdate(BaseSchema):
    # PATCH quản trị: mọi trường đều tùy chọn nhưng validator từ chối request rỗng.
    full_name: Optional[str] = Field(default=None, min_length=1, max_length=255)
    email: Optional[str] = Field(default=None, max_length=320)
    role: Optional[UserRole] = None
    is_active: Optional[bool] = None

    @field_validator("full_name")
    @classmethod
    def _strip_full_name(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        normalized = value.strip()
        if not normalized:
            raise ValueError("Tên hiển thị không được chỉ chứa khoảng trắng")
        return normalized

    @field_validator("email")
    @classmethod
    def _strip_optional_email(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        normalized = value.strip().lower()
        return normalized or None

    @model_validator(mode="after")
    def _require_change(self):
        # model_fields_set phân biệt payload `{}` với các trường có giá trị mặc định None.
        if not self.model_fields_set:
            raise ValueError("Phải cung cấp ít nhất một trường cần cập nhật")
        # Ba trường nghiệp vụ bắt buộc có giá trị khi được gửi; email vẫn cho phép null
        # để chủ động xóa email khỏi hồ sơ.
        for field_name in ("full_name", "role", "is_active"):
            # Chỉ kiểm tra trường xuất hiện trong JSON, không ép các trường bị bỏ qua.
            if field_name in self.model_fields_set and getattr(self, field_name) is None:
                raise ValueError(f"{field_name} không được để null")
        return self


class ChangePasswordRequest(BaseSchema):
    # Người dùng phải chứng minh mật khẩu hiện tại trước khi đặt mật khẩu mới.
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


class ResetPasswordRequest(BaseSchema):
    # ADMIN đặt mật khẩu mới mà không cần biết mật khẩu cũ của người dùng.
    new_password: str = Field(min_length=8, max_length=128)


class UserSettingsResponse(BaseSchema):
    # Tùy chọn trình bày đã lưu; preferences chứa các khóa mở rộng phía Flutter hiểu được.
    theme: str
    language: str
    timezone: str
    notifications_enabled: bool
    preferences: Optional[dict[str, Any]] = None
    created_at: datetime
    updated_at: datetime


class UserSettingsUpdate(BaseSchema):
    # PATCH cá nhân; chỉ gửi trường cần đổi và hợp nhất preferences thay vì ghi đè toàn bộ.
    theme: Optional[str] = Field(default=None, pattern="^(system|light|dark)$")
    language: Optional[str] = Field(default=None, min_length=2, max_length=10)
    timezone: Optional[str] = Field(default=None, min_length=1, max_length=64)
    notifications_enabled: Optional[bool] = None
    preferences: Optional[dict[str, Any]] = None

    @field_validator("preferences")
    @classmethod
    def _validate_preferences(
        cls,
        value: Optional[dict[str, Any]],
    ) -> dict[str, Any]:
        # Gửi preferences=null dễ xóa nhầm toàn bộ lựa chọn nên bị từ chối.
        if value is None:
            raise ValueError("preferences không được để null")
        map_type = value.get("map_type")
        # Chỉ kiểm tra khóa đã biết; khóa mở rộng khác được giữ để tương thích tương lai.
        if map_type is not None and map_type not in {"street", "satellite"}:
            raise ValueError("map_type phải là street hoặc satellite")
        speed_unit = value.get("speed_unit")
        # Đơn vị tốc độ chỉ ảnh hưởng cách trình bày, dữ liệu backend vẫn lưu m/s.
        if speed_unit is not None and speed_unit not in {"kmh", "mps"}:
            raise ValueError("speed_unit phải là kmh hoặc mps")
        return value

    @field_validator("language")
    @classmethod
    def _normalize_language(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        normalized = value.strip().lower()
        if len(normalized) < 2:
            raise ValueError("Mã ngôn ngữ phải có ít nhất 2 ký tự")
        return normalized

    @field_validator("timezone")
    @classmethod
    def _validate_timezone(cls, value: Optional[str]) -> Optional[str]:
        # None nghĩa trường timezone không nằm trong thay đổi hiện tại.
        if value is None:
            return None
        normalized = value.strip()
        try:
            # ZoneInfo xác minh tên IANA như `Asia/Ho_Chi_Minh`, không nhận offset tùy ý.
            ZoneInfo(normalized)
        except (ZoneInfoNotFoundError, ValueError) as exc:
            # Giữ exception gốc cho log nhưng trả thông báo nghiệp vụ ngắn qua Pydantic.
            raise ValueError("Múi giờ không hợp lệ") from exc
        return normalized

    @model_validator(mode="after")
    def _require_change(self):
        # PATCH rỗng bị từ chối để không tạo audit/commit không có thay đổi.
        if not self.model_fields_set:
            raise ValueError("Phải cung cấp ít nhất một cài đặt cần cập nhật")
        return self
