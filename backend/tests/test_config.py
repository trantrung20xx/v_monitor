import os
import sys
import unittest
import asyncio
from pathlib import Path
from unittest import mock


os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test",
)
os.environ.setdefault("JWT_SECRET", "x" * 48)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import Settings  # noqa: E402


class SettingsTest(unittest.TestCase):
    def test_authentication_is_required_by_default(self):
        settings = Settings(
            _env_file=None,
            database_url="postgresql+asyncpg://user:pass@localhost:5432/app",
        )

        self.assertTrue(settings.auth_required)

    def test_loads_database_and_mqtt_settings(self):
        settings = Settings(
            _env_file=None,
            database_url="postgresql+asyncpg://user:pass@db.local:5432/app",
            mqtt_host="mqtt.local",
            mqtt_port=8883,
            mqtt_use_tls=True,
            mqtt_username="sensor",
            mqtt_password="secret",
        )

        self.assertEqual(
            settings.database_url,
            "postgresql+asyncpg://user:pass@db.local:5432/app",
        )
        self.assertEqual(settings.mqtt_host, "mqtt.local")
        self.assertEqual(settings.mqtt_port, 8883)
        self.assertTrue(settings.mqtt_use_tls)
        self.assertEqual(settings.mqtt_username, "sensor")
        self.assertEqual(settings.mqtt_password, "secret")

    def test_loads_geocoding_settings(self):
        settings = Settings(
            _env_file=None,
            database_url="postgresql+asyncpg://user:pass@db.local:5432/app",
            geocoding_base_url="https://geo.example.test",
            geocoding_user_agent="v_monitor/test",
            geocoding_timeout_seconds=3,
        )

        self.assertEqual(settings.geocoding_base_url, "https://geo.example.test")
        self.assertEqual(settings.geocoding_user_agent, "v_monitor/test")
        self.assertEqual(settings.geocoding_timeout_seconds, 3)

    def test_normalizes_api_prefix_and_cors_origins(self):
        settings = Settings(
            _env_file=None,
            database_url="postgresql+asyncpg://user:pass@localhost:5432/app",
            api_prefix="api/v1/",
            cors_origins="http://localhost:3000, https://example.com",
        )

        self.assertEqual(settings.api_prefix, "/api/v1")
        self.assertEqual(
            settings.cors_origin_list,
            ["http://localhost:3000", "https://example.com"],
        )

    def test_database_url_is_required(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(Exception):
                Settings(_env_file=None)

    def test_database_engine_uses_settings_database_url(self):
        from app.core.config import settings
        from app.core.database import engine

        self.assertEqual(
            engine.url.render_as_string(hide_password=False),
            settings.database_url,
        )

    def test_mqtt_service_uses_settings_connection_values(self):
        from app.services.mqtt_service import MQTTService

        mqtt_settings = Settings(
            _env_file=None,
            database_url="postgresql+asyncpg://user:pass@localhost:5432/app",
            mqtt_host="mqtt.example.test",
            mqtt_port=8883,
            mqtt_username="device",
            mqtt_password="pass",
            mqtt_use_tls=True,
        )

        fake_client = _FakeMqttClient()
        service = MQTTService()
        service.client = fake_client

        async def start_service():
            with mock.patch("app.services.mqtt_service.settings", mqtt_settings):
                await service.start()

        asyncio.run(start_service())

        self.assertEqual(fake_client.username, "device")
        self.assertEqual(fake_client.password, "pass")
        self.assertTrue(fake_client.tls_enabled)
        self.assertEqual(fake_client.host, "mqtt.example.test")
        self.assertEqual(fake_client.port, 8883)
        self.assertTrue(fake_client.loop_started)


class _FakeMqttClient:
    def __init__(self):
        self.username = None
        self.password = None
        self.tls_enabled = False
        self.host = None
        self.port = None
        self.loop_started = False

    def username_pw_set(self, username, password):
        self.username = username
        self.password = password

    def tls_set(self):
        self.tls_enabled = True

    def connect_async(self, host, port):
        self.host = host
        self.port = port

    def loop_start(self):
        self.loop_started = True


if __name__ == "__main__":
    unittest.main()
