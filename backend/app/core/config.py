from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    DATABASE_URL: str = "postgresql+asyncpg://v_monitor:change_me_for_local_dev@localhost:55432/v_monitor_dev"
    MQTT_HOST: str = "localhost"
    MQTT_PORT: int = 1883
    API_HOST: str = "0.0.0.0"
    API_PORT: int = 8000
    JWT_SECRET: str = "change-me"
    MQTT_USERNAME: str = ""
    MQTT_PASSWORD: str = ""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

settings = Settings()
