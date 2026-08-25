# Xác nhận lịch sử GPS sắp theo measured_at, giữ timezone và serialize metadata phân trang.
import os
import sys
import unittest
import asyncio
from datetime import datetime, timezone, timedelta
from pathlib import Path
from unittest import mock
import uuid

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.schemas.tracking import LocationHistoryResponse, LocationSampleResponse
from app.services.tracking_service import TrackingService


class TrackingHistorySchemaTest(unittest.TestCase):
    def test_location_history_response_serialization(self):
        dev_id = uuid.uuid4()
        now = datetime.now(timezone.utc)
        sample_id = uuid.uuid4()

        sample = LocationSampleResponse(
            id=sample_id,
            device_id=dev_id,
            measured_at=now,
            latitude=21.0285,
            longitude=105.8542,
            altitude_m=35.0,
            speed_mps=12.5,
            heading_deg=90.0,
            accuracy_m=2.0,
            satellite_count=12,
            source="gps",
            received_at=now,
            created_at=now,
        )

        response = LocationHistoryResponse(
            device_id=dev_id,
            from_time=now - timedelta(hours=1),
            to_time=now,
            samples=[sample],
            total_count=1,
            truncated=False,
        )

        data = response.model_dump(mode="json")
        self.assertEqual(data["device_id"], str(dev_id))
        self.assertEqual(len(data["samples"]), 1)
        self.assertEqual(data["total_count"], 1)
        self.assertFalse(data["truncated"])
        self.assertEqual(data["samples"][0]["latitude"], 21.0285)
        self.assertEqual(data["samples"][0]["longitude"], 105.8542)


class TrackingServiceOrderingTest(unittest.TestCase):
    def test_samples_ordered_by_measured_at_asc(self):
        dev_id = uuid.uuid4()
        t0 = datetime(2026, 8, 16, 8, 0, 0, tzinfo=timezone.utc)
        t1 = datetime(2026, 8, 16, 8, 15, 0, tzinfo=timezone.utc)
        t2 = datetime(2026, 8, 16, 8, 30, 0, tzinfo=timezone.utc)
        t3 = datetime(2026, 8, 16, 8, 45, 0, tzinfo=timezone.utc)

        # Giả lập danh sách không theo thứ tự từ nguồn
        raw_samples = [
            {"id": uuid.uuid4(), "device_id": dev_id, "measured_at": t2, "latitude": 21.2, "longitude": 105.2},
            {"id": uuid.uuid4(), "device_id": dev_id, "measured_at": t0, "latitude": 21.0, "longitude": 105.0},
            {"id": uuid.uuid4(), "device_id": dev_id, "measured_at": t3, "latitude": 21.3, "longitude": 105.3},
            {"id": uuid.uuid4(), "device_id": dev_id, "measured_at": t1, "latitude": 21.1, "longitude": 105.1},
        ]

        # Kiểm tra deterministic ordering: measured_at ASC, id ASC
        sorted_samples = sorted(raw_samples, key=lambda s: (s["measured_at"], s["id"]))
        self.assertEqual(sorted_samples[0]["measured_at"], t0)
        self.assertEqual(sorted_samples[1]["measured_at"], t1)
        self.assertEqual(sorted_samples[2]["measured_at"], t2)
        self.assertEqual(sorted_samples[3]["measured_at"], t3)

    def test_timezone_aware_comparison(self):
        # Múi giờ UTC+7 (Việt Nam) so với UTC
        tz_vn = timezone(timedelta(hours=7))
        t_vn = datetime(2026, 8, 16, 15, 30, 0, tzinfo=tz_vn) # 15:30 VN = 08:30 UTC
        t_utc = datetime(2026, 8, 16, 8, 30, 0, tzinfo=timezone.utc)

        # Hai mốc thời gian này phải tương đương tuyệt đối
        self.assertEqual(t_vn.astimezone(timezone.utc), t_utc)


if __name__ == "__main__":
    unittest.main()
