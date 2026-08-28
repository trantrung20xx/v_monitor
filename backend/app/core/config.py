# Nguồn cấu hình runtime duy nhất của backend. Giá trị lấy từ biến môi trường
# hoặc backend/.env, được kiểm tra ngay khi khởi động để lỗi cấu hình xuất hiện sớm.
from functools import lru_cache
from pathlib import Path
from urllib.parse import urlparse

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


_BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    # Nhóm cấu hình tiến trình API. API_RELOAD chỉ dùng khi phát triển cục bộ;
    # bản chạy thật phải để false để tránh tạo tiến trình theo dõi tệp dư thừa.
    # app_env: nhãn môi trường; api_prefix: tiền tố mọi REST route.
    # api_host/api_port: giao diện mạng và cổng Uvicorn lắng nghe; api_reload: tự nạp lại code.
    app_env: str = "development"
    api_prefix: str = "/api/v1"
    api_host: str = "0.0.0.0"
    api_port: int = Field(default=8000, ge=1, le=65535)
    api_reload: bool = False

    # Pool PostgreSQL được cấu hình tập trung để cùng mã nguồn có thể chạy trên
    # máy cá nhân, máy chủ công ty hoặc dịch vụ cơ sở dữ liệu quản lý sẵn.
    # database_url: chuỗi kết nối asyncpg có thông tin host/database/tài khoản.
    # pool_size: số kết nối thường trực; max_overflow: số kết nối tăng tạm khi cao tải.
    # pool_timeout: thời gian chờ lấy kết nối; pool_recycle: tuổi tối đa của socket trong pool.
    # connect_timeout: giới hạn thời gian mở một kết nối PostgreSQL mới.
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
    # host/port/username/password/TLS: thông tin kết nối broker.
    # topic_prefix: gốc topic telemetry; keepalive: chu kỳ broker kiểm tra phiên.
    # connect_timeout: thời gian chờ bắt tay; reconnect min/max: biên backoff kết nối lại.
    # worker_count: số consumer xử lý song song; queue_size: sức chứa hàng đợi trong RAM.
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
    # provider quyết định cấu trúc response; base_url là endpoint dịch vụ.
    # user_agent nhận diện ứng dụng; timeout/retry/delay điều khiển khả năng chịu lỗi mạng.
    geocoding_provider: str = "photon"
    geocoding_base_url: str = "https://photon.komoot.io"
    geocoding_user_agent: str = "v_monitor/1.0 local-development"
    geocoding_timeout_seconds: int = Field(default=8, ge=1, le=30)
    geocoding_retry_attempts: int = Field(default=2, ge=1, le=3)
    geocoding_retry_delay_seconds: float = Field(default=0.5, ge=0, le=5)

    # Cấu hình truy vấn lịch sử theo dõi.
    # default_timezone: múi giờ chuẩn khi client không truyền múi giờ riêng.
    # gap_threshold: khoảng im lặng đủ lớn để tách đoạn; outlier_speed: ngưỡng loại GPS nhảy.
    # max_history_samples: chặn một truy vấn lịch sử lấy quá nhiều mẫu vào bộ nhớ.
    default_timezone: str = "UTC"
    tracking_gap_threshold_seconds: int = 300
    tracking_outlier_speed_kmh: float = 500.0
    tracking_max_history_samples: int = 100000

    # Toàn bộ API giám sát và WebSocket yêu cầu tài khoản nội bộ hợp lệ. Chỉ môi
    # trường kiểm thử đặc biệt mới được phép tắt cờ này một cách tường minh.
    # jwt_secret ký token; algorithm/issuer/audience ngăn token sai nguồn hoặc sai mục đích.
    # failed_attempts và lock_minutes giới hạn dò mật khẩu liên tục.
    auth_required: bool = True
    jwt_secret: str = ""
    jwt_algorithm: str = "HS256"
    jwt_issuer: str = "v_monitor"
    jwt_audience: str = "v_monitor_internal"
    login_max_failed_attempts: int = Field(default=5, ge=3, le=20)
    login_lock_minutes: int = Field(default=15, ge=1, le=1440)

    # offline_timeout: thời gian không thấy gói trước khi đánh dấu ngoại tuyến.
    # scan_interval: chu kỳ quét trạng thái; list_max_limit: trần thiết bị trả cho giao diện.
    device_offline_timeout_seconds: int = Field(default=300, ge=30, le=86400)
    device_offline_scan_interval_seconds: int = Field(default=30, ge=5, le=3600)
    device_list_max_limit: int = Field(default=5000, ge=100, le=50000)

    # Pydantic đọc đúng backend/.env theo UTF-8, không phân biệt hoa thường và
    # bỏ qua biến dư để có thể dùng chung môi trường với dịch vụ khác.
    model_config = SettingsConfigDict(
        env_file=_BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    @field_validator("api_prefix")
    @classmethod
    def _normalize_api_prefix(cls, value: str) -> str:
        # Chuẩn hóa về dạng /api/v1, không có dấu / cuối để ghép route ổn định.
        value = value.strip()
        # Chuỗi rỗng là cấu hình hợp lệ khi API cần được phục vụ ngay tại root.
        if not value:
            return ""
        # Tự bổ sung dấu gạch đầu giúp `api/v1` và `/api/v1` cho cùng kết quả.
        if not value.startswith("/"):
            value = f"/{value}"
        # Bỏ dấu gạch cuối để không tạo đường dẫn có hai dấu `/` khi ghép route.
        return value.rstrip("/")

    @field_validator("api_host", "mqtt_host")
    @classmethod
    def _require_network_host(cls, value: str) -> str:
        # Loại khoảng trắng và từ chối host rỗng trước khi thư viện mạng xử lý.
        normalized = value.strip()
        # Phát hiện cấu hình thiếu lúc khởi động thay vì chờ lần kết nối đầu tiên.
        if not normalized:
            raise ValueError("Host kết nối không được để trống")
        return normalized

    @field_validator("mqtt_topic_prefix")
    @classmethod
    def _normalize_mqtt_topic_prefix(cls, value: str) -> str:
        # Prefix phải là đường dẫn topic cụ thể; wildcard chỉ dành cho phía subscribe nội bộ.
        normalized = value.strip().strip("/")
        # Mỗi cấp topic phải có tên; hai dấu `/` liên tiếp tạo một cấp rỗng.
        if not normalized or any(part == "" for part in normalized.split("/")):
            raise ValueError("MQTT_TOPIC_PREFIX không hợp lệ")
        # `+` và `#` là wildcard MQTT nên không được nằm trong prefix publish chuẩn.
        if "+" in normalized or "#" in normalized:
            raise ValueError("MQTT_TOPIC_PREFIX không được chứa ký tự đại diện")
        return normalized

    @field_validator("mqtt_client_id")
    @classmethod
    def _normalize_mqtt_client_id(cls, value: str | None) -> str | None:
        # Chuỗi rỗng đồng nghĩa tự sinh; giới hạn byte bảo đảm broker chấp nhận ổn định.
        # None thể hiện biến môi trường không được khai báo và giữ cơ chế tự sinh.
        if value is None:
            return None
        normalized = value.strip()
        # Giá trị chỉ gồm khoảng trắng được xử lý như không cấu hình client id.
        if not normalized:
            return None
        # Đếm byte UTF-8 vì broker giới hạn dữ liệu truyền, không phải ký tự hiển thị.
        if len(normalized.encode("utf-8")) > 128:
            raise ValueError("MQTT_CLIENT_ID không được vượt quá 128 byte")
        return normalized

    @field_validator("geocoding_provider")
    @classmethod
    def _normalize_geocoding_provider(cls, value: str) -> str:
        # Chỉ nhận provider mà bộ chuyển đổi payload phía service đã hỗ trợ.
        normalized = value.strip().lower()
        # Giới hạn tập giá trị để service luôn chọn đúng cấu trúc request/response.
        if normalized not in {"nominatim", "photon"}:
            raise ValueError("GEOCODING_PROVIDER phải là nominatim hoặc photon")
        return normalized

    @field_validator("geocoding_base_url")
    @classmethod
    def _validate_geocoding_base_url(cls, value: str) -> str:
        # URL tuyệt đối giúp proxy và urllib không diễn giải nhầm thành đường dẫn cục bộ.
        normalized = value.strip().rstrip("/")
        parsed = urlparse(normalized)
        # Chỉ nhận giao thức mạng được hỗ trợ và bắt buộc có hostname thật.
        if parsed.scheme not in {"http", "https"} or not parsed.hostname:
            raise ValueError("GEOCODING_BASE_URL phải là URL HTTP hoặc HTTPS tuyệt đối")
        return normalized

    @field_validator("database_url")
    @classmethod
    def _require_database_url(cls, value: str) -> str:
        # Backend dùng engine async nên bắt buộc driver asyncpg, không nhận URL sync.
        value = value.strip()
        # Không dùng database mặc định ngầm để tránh kết nối nhầm môi trường.
        if not value:
            raise ValueError("DATABASE_URL không được để trống")
        # Prefix xác nhận đồng thời PostgreSQL và driver bất đồng bộ của SQLAlchemy.
        if not value.startswith("postgresql+asyncpg://"):
            raise ValueError("DATABASE_URL phải sử dụng postgresql+asyncpg://")
        return value

    @model_validator(mode="after")
    def _validate_related_settings(self):
        # Kiểm tra các quy tắc liên trường không thể biểu diễn bằng giới hạn của một Field.
        # Chỉ bắt độ dài secret khi auth bật; test cô lập có thể chủ động tắt auth.
        if self.auth_required and len(self.jwt_secret) < 32:
            raise ValueError(
                "JWT_SECRET phải có ít nhất 32 ký tự khi AUTH_REQUIRED=true"
            )
        # Luồng ký và giải mã hiện sử dụng khóa đối xứng HS256 thống nhất.
        if self.jwt_algorithm != "HS256":
            raise ValueError("JWT_ALGORITHM hiện chỉ hỗ trợ HS256")
        # Backoff tối đa phải không nhỏ hơn mức khởi đầu để Paho tăng thời gian hợp lệ.
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
        # Chuyển chuỗi .env thành danh sách origin chuẩn cho CORSMiddleware và loại trùng.
        value = self.cors_origins.strip()
        # Wildcard được giữ thành một phần tử theo đúng hợp đồng của middleware.
        if not value or value == "*":
            return ["*"]

        origins: list[str] = []
        for raw_origin in value.split(","):
            # Chuẩn hóa dấu `/` cuối để cùng origin không tồn tại dưới hai dạng.
            origin = raw_origin.strip().rstrip("/")
            # Dấu phẩy thừa không tạo một origin rỗng trong kết quả.
            if not origin:
                continue
            parsed = urlparse(origin)
            # Origin chỉ gồm scheme, host và port; path/query/fragment đều bị từ chối.
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
            # Giữ thứ tự khai báo đồng thời loại các origin trùng nhau.
            if origin not in origins:
                origins.append(origin)
        # Chuỗi chỉ gồm dấu phẩy/khoảng trắng là lỗi cấu hình, không phải wildcard.
        if not origins:
            raise ValueError("CORS_ORIGINS không có origin hợp lệ")
        return origins


@lru_cache
def get_settings() -> Settings:
    # Chỉ tạo một Settings cho mỗi tiến trình để mọi module dùng cùng một cấu hình đồng bộ.
    return Settings()


# Singleton cấu hình được import bởi API, database và các dịch vụ nền.
settings = get_settings()
