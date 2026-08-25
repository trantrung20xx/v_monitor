# Xác nhận topic MQTT, client id và health snapshot phản ánh đúng kết nối/subscribe.
import os
import sys
import unittest
from pathlib import Path
from unittest import mock


os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test",
)
os.environ.setdefault("JWT_SECRET", "x" * 48)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import Settings  # noqa: E402
from app.services.mqtt_service import (  # noqa: E402
    MQTTService,
    _device_code_from_topic,
    _mqtt_client_id,
)


class MqttTopicTest(unittest.TestCase):
    def setUp(self):
        self.settings = Settings(
            _env_file=None,
            database_url="postgresql+asyncpg://user:pass@localhost:5432/app",
            mqtt_topic_prefix="company/telemetry",
        )

    def test_extracts_device_code_only_from_exact_topic_shape(self):
        with mock.patch("app.services.mqtt_service.settings", self.settings):
            self.assertEqual(
                _device_code_from_topic("company/telemetry/UAV-100"),
                "UAV-100",
            )
            self.assertIsNone(
                _device_code_from_topic("company/telemetry/UAV-100/location")
            )
            self.assertIsNone(_device_code_from_topic("other/telemetry/UAV-100"))

    def test_health_reports_successful_subscription(self):
        service = MQTTService()
        client = _FakeSubscribeClient()
        with mock.patch("app.services.mqtt_service.settings", self.settings):
            service.on_connect(client, None, None, 0)
            snapshot = service.health_snapshot()

        self.assertTrue(snapshot["connected"])
        self.assertTrue(snapshot["subscribed"])
        self.assertEqual(client.topic, "company/telemetry/#")
        self.assertEqual(client.qos, 1)

    def test_generates_a_unique_client_id_when_not_configured(self):
        with (
            mock.patch("app.services.mqtt_service.settings", self.settings),
            mock.patch("app.services.mqtt_service.socket.gethostname", return_value="node 01"),
            mock.patch("app.services.mqtt_service.os.getpid", return_value=42),
        ):
            client_id = _mqtt_client_id()

        self.assertEqual(client_id, "v_monitor_backend_node-01_42")


class _FakeSubscribeClient:
    topic = None
    qos = None

    def subscribe(self, topic, qos):
        self.topic = topic
        self.qos = qos
        return (0, 1)


if __name__ == "__main__":
    unittest.main()
