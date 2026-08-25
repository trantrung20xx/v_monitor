from functools import lru_cache
from pathlib import Path
from urllib.parse import urlparse

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


_BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    # Nhóm cấu hình tiến trình API. API_RELOAD chỉ dùng khi phát triển cục bộ;
    # bản chạy thật phải để false để tránh tạo tiến trình theo dõi tệp dư thừa.
    app_env: str = "development"
    api_prefix: str = "/api/v1"
    api_host: str = "0.0.0.0"
    api_port: int = Field(default=8000, ge=1, le=65535)
    api_reload: bool = False

    # Pool PostgreSQL được cấu hình tập trung để cùng mã nguồn có thể chạy trên
    # máy cá nhân, máy chủ công ty hoặc dịch vụ cơ sở dữ liệu quản lý sẵn.
    database_url: str = ""
    database_pool_size: int = Field(default=10, ge=1, le=100)
    database_max_overflow: int = Field(default=10, ge=0, le=100)
    database_pool_timeout_seconds: int = Field(default=30, ge=1, le=300)
    database_pool_recycle_seconds: int = Field(default=1800, ge=60, le=86400)
    database_connect_timeout_seconds: int = Field(default=10, ge=1, le=60)

    # Danh sách origin được phân tách bằng dấu phẩy. Dùng URL frontend cụ thể
    # khi public qua Cloudflare; dấu * chỉ phù hợp môi trường phát triển kín.
    cors_origins: str = "*"

    # MQTT client id để trống sẽ được tạo từ hostname và PID, tránh hai backend
    # dùng cùng client id rồi liên tục ngắt kết nối lẫn nhau.
    mqtt_host: str = "localhost"
    mqtt_port: int = Field(default=1883, ge=1, le=65535)
    mqtt_client_id: str | None = None
    mqtt_username: str | None = None
    mqtt_password: str | None = None
    mqtt_use_tls: bool = False
    mqtt_topic_prefix: str = "v_monitor/telemetry"
    mqtt_keepalive_seconds: int = Field(default=60, ge=10, le=3600)
    mqtt_connect_timeout_seconds: int = Field(default=10, ge=1, le=120)
    mqtt_reconnect_min_delay_seconds: int = Field(default=1, ge=1, le=300)
    mqtt_reconnect_max_delay_seconds: int = Field(default=30, ge=1, le=3600)
    mqtt_worker_count: int = Field(default=8, ge=1, le=64)
    mqtt_queue_size: int = Field(default=20000, ge=100, le=1000000)

    # Một kết nối frontend chậm không được phép chặn luồng xử lý MQTT cho mọi
    # người dùng còn lại.
    realtime_send_timeout_seconds: float = Field(default=5, gt=0, le=30)

    # Nhà cung cấp geocoding phải khai báo rõ để URL proxy hoặc host nội bộ
    # không bị đoán sai loại payload dựa trên tên miền.
    geocoding_provider: str = "photon"
    geocoding_base_url: str = "https://photon.komoot.io"
    geocoding_user_agent: str = "v_monitor/1.0 local-development"
    geocoding_timeout_seconds: int = Field(default=8, ge=1, le=30)
    geocoding_retry_attempts: int = Field(default=2, ge=1, le=3)
    geocoding_retry_delay_seconds: float = Field(default=0.5, ge=0, le=5)

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

    @field_validator("api_host", "mqtt_host")
    @classmethod
    def _require_network_host(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("Host kết nối không được để trống")
        return normalized

    @field_validator("mqtt_topic_prefix")
    @classmethod
    def _normalize_mqtt_topic_prefix(cls, value: str) -> str:
        normalized = value.strip().strip("/")
        if not normalized or any(part == "" for part in normalized.split("/")):
            raise ValueError("MQTT_TOPIC_PREFIX không hợp lệ")
        if "+" in normalized or "#" in normalized:
            raise ValueError("MQTT_TOPIC_PREFIX không được chứa ký tự đại diện")
        return normalized

    @field_validator("mqtt_client_id")
    @classmethod
    def _normalize_mqtt_client_id(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        if not normalized:
            return None
        if len(normalized.encode("utf-8")) > 128:
            raise ValueError("MQTT_CLIENT_ID không được vượt quá 128 byte")
        return normalized

    @field_validator("geocoding_provider")
    @classmethod
    def _normalize_geocoding_provider(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in {"nominatim", "photon"}:
            raise ValueError("GEOCODING_PROVIDER phải là nominatim hoặc photon")
        return normalized

    @field_validator("geocoding_base_url")
    @classmethod
    def _validate_geocoding_base_url(cls, value: str) -> str:
        normalized = value.strip().rstrip("/")
        parsed = urlparse(normalized)
        if parsed.scheme not in {"http", "https"} or not parsed.hostname:
            raise ValueError("GEOCODING_BASE_URL phải là URL HTTP hoặc HTTPS tuyệt đối")
        return normalized

    @field_validator("database_url")
    @classmethod
    def _require_database_url(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("DATABASE_URL không được để trống")
        if not value.startswith("postgresql+asyncpg://"):
            raise ValueError("DATABASE_URL phải sử dụng postgresql+asyncpg://")
        return value

    @model_validator(mode="after")
    def _validate_related_settings(self):
        if self.auth_required and len(self.jwt_secret) < 32:
            raise ValueError(
                "JWT_SECRET phải có ít nhất 32 ký tự khi AUTH_REQUIRED=true"
            )
        if self.jwt_algorithm != "HS256":
            raise ValueError("JWT_ALGORITHM hiện chỉ hỗ trợ HS256")
        if (
            self.mqtt_reconnect_max_delay_seconds
            < self.mqtt_reconnect_min_delay_seconds
        ):
            raise ValueError(
                "MQTT_RECONNECT_MAX_DELAY_SECONDS không được nhỏ hơn "
                "MQTT_RECONNECT_MIN_DELAY_SECONDS"
            )
        return self

    @property
    def cors_origin_list(self) -> list[str]:
        value = self.cors_origins.strip()
        if not value or value == "*":
            return ["*"]

        origins: list[str] = []
        for raw_origin in value.split(","):
            origin = raw_origin.strip().rstrip("/")
            if not origin:
                continue
            parsed = urlparse(origin)
            if (
                parsed.scheme not in {"http", "https"}
                or not parsed.hostname
                or parsed.path not in {"", "/"}
                or parsed.query
                or parsed.fragment
            ):
                raise ValueError(
                    "CORS_ORIGINS chỉ được chứa origin HTTP/HTTPS, không chứa path"
                )
            if origin not in origins:
                origins.append(origin)
        if not origins:
            raise ValueError("CORS_ORIGINS không có origin hợp lệ")
        return origins


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
