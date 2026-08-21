import uuid
from datetime import datetime
from typing import Any, Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import Field, field_validator, model_validator

from app.domain.enums import UserRole
from app.schemas.common import BaseSchema


class LoginRequest(BaseSchema):
    username: str = Field(min_length=3, max_length=50)
    password: str = Field(min_length=1, max_length=128)

    @field_validator("username")
    @classmethod
    def _normalize_username(cls, value: str) -> str:
        normalized = value.strip()
        if len(normalized) < 3:
            raise ValueError("Username phải có ít nhất 3 ký tự không tính khoảng trắng")
        return normalized


class UserResponse(BaseSchema):
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
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


class UserCreate(BaseSchema):
    username: str = Field(min_length=3, max_length=50)
    password: str = Field(min_length=8, max_length=128)
    full_name: str = Field(min_length=1, max_length=255)
    email: Optional[str] = Field(default=None, max_length=320)
    role: UserRole = UserRole.USER
    is_active: bool = True

    @field_validator("username")
    @classmethod
    def _strip_username(cls, value: str) -> str:
        normalized = value.strip()
        if len(normalized) < 3:
            raise ValueError("Username phải có ít nhất 3 ký tự không tính khoảng trắng")
        return normalized

    @field_validator("full_name")
    @classmethod
    def _strip_full_name(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("Tên hiển thị không được chỉ chứa khoảng trắng")
        return normalized

    @field_validator("email")
    @classmethod
    def _strip_email(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        normalized = value.strip().lower()
        return normalized or None


class UserUpdate(BaseSchema):
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
        if not self.model_fields_set:
            raise ValueError("Phải cung cấp ít nhất một trường cần cập nhật")
        for field_name in ("full_name", "role", "is_active"):
            if field_name in self.model_fields_set and getattr(self, field_name) is None:
                raise ValueError(f"{field_name} không được để null")
        return self


class ChangePasswordRequest(BaseSchema):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


class ResetPasswordRequest(BaseSchema):
    new_password: str = Field(min_length=8, max_length=128)


class UserSettingsResponse(BaseSchema):
    theme: str
    language: str
    timezone: str
    notifications_enabled: bool
    preferences: Optional[dict[str, Any]] = None
    created_at: datetime
    updated_at: datetime


class UserSettingsUpdate(BaseSchema):
    theme: Optional[str] = Field(default=None, pattern="^(system|light|dark)$")
    language: Optional[str] = Field(default=None, min_length=2, max_length=10)
    timezone: Optional[str] = Field(default=None, min_length=1, max_length=64)
    notifications_enabled: Optional[bool] = None
    preferences: Optional[dict[str, Any]] = None

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
        if value is None:
            return None
        normalized = value.strip()
        try:
            ZoneInfo(normalized)
        except (ZoneInfoNotFoundError, ValueError) as exc:
            raise ValueError("Múi giờ không hợp lệ") from exc
        return normalized

    @model_validator(mode="after")
    def _require_change(self):
        if not self.model_fields_set:
            raise ValueError("Phải cung cấp ít nhất một cài đặt cần cập nhật")
        return self
