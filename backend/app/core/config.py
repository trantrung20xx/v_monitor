from functools import lru_cache
from pathlib import Path

from pydantic import field_validator
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

    geocoding_base_url: str = "https://nominatim.openstreetmap.org"
    geocoding_user_agent: str = "v_monitor/1.0 local-development"
    geocoding_timeout_seconds: int = 8

    # Tracking history settings
    default_timezone: str = "UTC"                         # Display timezone (e.g. Asia/Ho_Chi_Minh)
    tracking_gap_threshold_seconds: int = 300             # Gap > this = tracking gap (configurable)
    tracking_outlier_speed_kmh: float = 500.0             # Implied speed > this = outlier
    tracking_max_history_samples: int = 100000            # Max samples per history request

    jwt_secret: str = "dev-only-change-me"

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
