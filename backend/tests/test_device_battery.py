import os
import sys
import unittest
import uuid
from datetime import datetime, timezone
from pathlib import Path

from pydantic import ValidationError


os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.schemas.tracking import LocationSampleCreate  # noqa: E402


class DeviceBatterySchemaTest(unittest.TestCase):
    def _valid_payload(self) -> dict:
        return {
            "device_id": uuid.uuid4(),
            "measured_at": datetime.now(timezone.utc),
            "latitude": 10.7769,
            "longitude": 106.7009,
        }

    def test_accepts_battery_level_of_the_device(self):
        sample = LocationSampleCreate(
            **self._valid_payload(),
            battery_pct=0,
        )
        self.assertEqual(sample.battery_pct, 0)

    def test_rejects_battery_level_outside_percentage_range(self):
        with self.assertRaises(ValidationError):
            LocationSampleCreate(
                **self._valid_payload(),
                battery_pct=101,
            )

    def test_rejects_legacy_uav_battery_field(self):
        with self.assertRaises(ValidationError):
            LocationSampleCreate(
                **self._valid_payload(),
                uav_battery_pct=50,
            )


if __name__ == "__main__":
    unittest.main()
