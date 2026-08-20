from functools import lru_cache
from pathlib import Path

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


_BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    app_env: str = "development"

    api_prefix: str = "/api/v1"
    api_host: str = "0.0.0.0"
    api_port: int = 8000

    database_url: str = ""

    cors_origins: str = "*"

    mqtt_host: str = "localhost"
    mqtt_port: int = 1883
    mqtt_username: str | None = None
    mqtt_password: str | None = None
    mqtt_use_tls: bool = False
    mqtt_worker_count: int = Field(default=8, ge=1, le=64)
    mqtt_queue_size: int = Field(default=20000, ge=100, le=1000000)

    geocoding_base_url: str = "https://nominatim.openstreetmap.org"
    geocoding_user_agent: str = "v_monitor/1.0 local-development"
    geocoding_timeout_seconds: int = 8

    # Cấu hình truy vấn lịch sử theo dõi.
    default_timezone: str = "UTC"                         # Múi giờ hiển thị
    tracking_gap_threshold_seconds: int = 300             # Ngưỡng xác định khoảng đứt quãng
    tracking_outlier_speed_kmh: float = 500.0             # Ngưỡng phát hiện điểm GPS nhảy bất thường
    tracking_max_history_samples: int = 100000            # Số mẫu tối đa cho một truy vấn

    # Toàn bộ API giám sát và WebSocket yêu cầu tài khoản nội bộ hợp lệ. Chỉ môi
    # trường kiểm thử đặc biệt mới được phép tắt cờ này một cách tường minh.
    auth_required: bool = True
    jwt_secret: str = ""
    jwt_algorithm: str = "HS256"
    jwt_issuer: str = "v_monitor"
    jwt_audience: str = "v_monitor_internal"
    login_max_failed_attempts: int = Field(default=5, ge=3, le=20)
    login_lock_minutes: int = Field(default=15, ge=1, le=1440)

    device_offline_timeout_seconds: int = Field(default=300, ge=30, le=86400)
    device_offline_scan_interval_seconds: int = Field(default=30, ge=5, le=3600)
    device_list_max_limit: int = Field(default=5000, ge=100, le=50000)

    model_config = SettingsConfigDict(
        env_file=_BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    @field_validator("api_prefix")
    @classmethod
    def _normalize_api_prefix(cls, value: str) -> str:
        value = value.strip()
        if not value:
            return ""
        if not value.startswith("/"):
            value = f"/{value}"
        return value.rstrip("/")

    @field_validator("database_url")
    @classmethod
    def _require_database_url(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("DATABASE_URL is required")
        return value

    @model_validator(mode="after")
    def _validate_auth_settings(self):
        if self.auth_required and len(self.jwt_secret) < 32:
            raise ValueError(
                "JWT_SECRET phải có ít nhất 32 ký tự khi AUTH_REQUIRED=true"
            )
        if self.jwt_algorithm != "HS256":
            raise ValueError("JWT_ALGORITHM hiện chỉ hỗ trợ HS256")
        return self

    @property
    def cors_origin_list(self) -> list[str]:
        value = self.cors_origins.strip()
        if not value or value == "*":
            return ["*"]
        return [origin.strip() for origin in value.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
