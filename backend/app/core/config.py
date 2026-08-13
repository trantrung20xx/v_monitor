import os
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    # Sử dụng cổng 5432 (mặc định của Postgres) thay vì 55432
    DATABASE_URL: str = "postgresql+asyncpg://postgres:atl132456@localhost:5432/v_monitor"
    MQTT_HOST: str = "broker.emqx.io"
    MQTT_PORT: int = 1883
    API_HOST: str = "0.0.0.0"
    API_PORT: int = 8000
    JWT_SECRET: str = "super-secret-key-change-in-production"
    MQTT_USERNAME: str = ""
    MQTT_PASSWORD: str = ""

    # Tự động load từ file .env nếu có
    model_config = SettingsConfigDict(
        env_file=os.path.join(os.path.dirname(__file__), "../../.env"),
        env_file_encoding="utf-8",
        extra="ignore"
    )

settings = Settings()
