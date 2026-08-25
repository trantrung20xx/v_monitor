# Xác nhận Settings chuẩn hóa đúng API, PostgreSQL, MQTT, CORS và giá trị bảo mật bắt buộc.
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

    def test_loads_api_process_settings(self):
        settings = Settings(
            _env_file=None,
            database_url="postgresql+asyncpg://user:pass@localhost:5432/app",
            api_host="127.0.0.1",
            api_port=9100,
            api_reload=True,
        )

        self.assertEqual(settings.api_host, "127.0.0.1")
        self.assertEqual(settings.api_port, 9100)
        self.assertTrue(settings.api_reload)

    def test_loads_database_and_mqtt_settings(self):
        settings = Settings(
            _env_file=None,
            database_url="postgresql+asyncpg://user:pass@db.local:5432/app",
            mqtt_host="mqtt.local",
            mqtt_port=8883,
            mqtt_client_id="backend-primary",
            mqtt_use_tls=True,
            mqtt_username="sensor",
            mqtt_password="secret",
            mqtt_topic_prefix="company/v-monitor/telemetry",
            mqtt_keepalive_seconds=45,
            mqtt_connect_timeout_seconds=7,
            mqtt_reconnect_min_delay_seconds=2,
            mqtt_reconnect_max_delay_seconds=20,
        )

        self.assertEqual(
            settings.database_url,
            "postgresql+asyncpg://user:pass@db.local:5432/app",
        )
        self.assertEqual(settings.mqtt_host, "mqtt.local")
        self.assertEqual(settings.mqtt_port, 8883)
        self.assertEqual(settings.mqtt_client_id, "backend-primary")
        self.assertTrue(settings.mqtt_use_tls)
        self.assertEqual(settings.mqtt_username, "sensor")
        self.assertEqual(settings.mqtt_password, "secret")
        self.assertEqual(
            settings.mqtt_topic_prefix,
            "company/v-monitor/telemetry",
        )
        self.assertEqual(settings.mqtt_keepalive_seconds, 45)
        self.assertEqual(settings.mqtt_connect_timeout_seconds, 7)
        self.assertEqual(settings.mqtt_reconnect_min_delay_seconds, 2)
        self.assertEqual(settings.mqtt_reconnect_max_delay_seconds, 20)

    def test_loads_database_pool_settings(self):
        settings = Settings(
            _env_file=None,
            database_url="postgresql+asyncpg://user:pass@db.local:5432/app",
            database_pool_size=12,
            database_max_overflow=4,
            database_pool_timeout_seconds=15,
            database_pool_recycle_seconds=900,
            database_connect_timeout_seconds=6,
        )

        self.assertEqual(settings.database_pool_size, 12)
        self.assertEqual(settings.database_max_overflow, 4)
        self.assertEqual(settings.database_pool_timeout_seconds, 15)
        self.assertEqual(settings.database_pool_recycle_seconds, 900)
        self.assertEqual(settings.database_connect_timeout_seconds, 6)

    def test_normalizes_and_validates_mqtt_topic_prefix(self):
        settings = Settings(
            _env_file=None,
            database_url="postgresql+asyncpg://user:pass@localhost:5432/app",
            mqtt_topic_prefix="/v_monitor/telemetry/",
        )
        self.assertEqual(settings.mqtt_topic_prefix, "v_monitor/telemetry")

        with self.assertRaises(Exception):
            Settings(
                _env_file=None,
                database_url="postgresql+asyncpg://user:pass@localhost:5432/app",
                mqtt_topic_prefix="v_monitor/+",
            )

    def test_loads_geocoding_settings(self):
        settings = Settings(
            _env_file=None,
            database_url="postgresql+asyncpg://user:pass@db.local:5432/app",
            geocoding_provider="PHOTON",
            geocoding_base_url="https://geo.example.test",
            geocoding_user_agent="v_monitor/test",
            geocoding_timeout_seconds=3,
            geocoding_retry_attempts=3,
            geocoding_retry_delay_seconds=0.25,
        )

        self.assertEqual(settings.geocoding_provider, "photon")
        self.assertEqual(settings.geocoding_base_url, "https://geo.example.test")
        self.assertEqual(settings.geocoding_user_agent, "v_monitor/test")
        self.assertEqual(settings.geocoding_timeout_seconds, 3)
        self.assertEqual(settings.geocoding_retry_attempts, 3)
        self.assertEqual(settings.geocoding_retry_delay_seconds, 0.25)

        with self.assertRaises(Exception):
            Settings(
                _env_file=None,
                database_url="postgresql+asyncpg://user:pass@db.local:5432/app",
                geocoding_provider="unsupported",
            )

    def test_normalizes_api_prefix_and_cors_origins(self):
        settings = Settings(
            _env_file=None,
            database_url="postgresql+asyncpg://user:pass@localhost:5432/app",
            api_prefix="api/v1/",
            cors_origins=(
                "http://localhost:3000/, https://example.com, "
                "https://example.com"
            ),
        )

        self.assertEqual(settings.api_prefix, "/api/v1")
        self.assertEqual(
            settings.cors_origin_list,
            ["http://localhost:3000", "https://example.com"],
        )

        invalid = Settings(
            _env_file=None,
            database_url="postgresql+asyncpg://user:pass@localhost:5432/app",
            cors_origins="https://example.com/not-an-origin",
        )
        with self.assertRaises(ValueError):
            _ = invalid.cors_origin_list

    def test_database_url_is_required(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(Exception):
                Settings(_env_file=None)

        with self.assertRaises(Exception):
            Settings(
                _env_file=None,
                database_url="postgresql://user:pass@localhost:5432/app",
            )

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
            mqtt_client_id="backend-test",
            mqtt_username="device",
            mqtt_password="pass",
            mqtt_use_tls=True,
            mqtt_keepalive_seconds=45,
            mqtt_connect_timeout_seconds=7,
            mqtt_reconnect_min_delay_seconds=2,
            mqtt_reconnect_max_delay_seconds=20,
        )

        fake_client = _FakeMqttClient()

        async def start_service():
            with mock.patch("app.services.mqtt_service.settings", mqtt_settings):
                service = MQTTService()
                service.client = fake_client
                await service.start()
                await service.stop()
                return service

        service = asyncio.run(start_service())

        self.assertEqual(service._client_id, "backend-test")
        self.assertEqual(fake_client.username, "device")
        self.assertEqual(fake_client.password, "pass")
        self.assertTrue(fake_client.tls_enabled)
        self.assertEqual(fake_client.host, "mqtt.example.test")
        self.assertEqual(fake_client.port, 8883)
        self.assertEqual(fake_client.keepalive, 45)
        self.assertEqual(fake_client.connect_timeout, 7)
        self.assertEqual(fake_client.reconnect_min_delay, 2)
        self.assertEqual(fake_client.reconnect_max_delay, 20)
        self.assertTrue(fake_client.loop_started)
        self.assertTrue(fake_client.disconnected)
        self.assertTrue(fake_client.loop_stopped)


class _FakeMqttClient:
    def __init__(self):
        self.username = None
        self.password = None
        self.tls_enabled = False
        self.host = None
        self.port = None
        self.keepalive = None
        self.connect_timeout = None
        self.reconnect_min_delay = None
        self.reconnect_max_delay = None
        self.loop_started = False
        self.loop_stopped = False
        self.disconnected = False

    def username_pw_set(self, username, password):
        self.username = username
        self.password = password

    def tls_set(self):
        self.tls_enabled = True

    def reconnect_delay_set(self, min_delay, max_delay):
        self.reconnect_min_delay = min_delay
        self.reconnect_max_delay = max_delay

    def connect_async(self, host, port, keepalive):
        self.host = host
        self.port = port
        self.keepalive = keepalive

    def loop_start(self):
        self.loop_started = True
        return 0

    def disconnect(self):
        self.disconnected = True

    def loop_stop(self):
        self.loop_stopped = True


if __name__ == "__main__":
    unittest.main()
