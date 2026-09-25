"""Unit tests cho radio scan LTE; không yêu cầu broker hoặc database thật."""
import os
import sys
import unittest
import uuid
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test")
os.environ.setdefault("JWT_SECRET", "x" * 48)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.models.cell_tower import CellTower  # noqa: E402
from app.models.device_latest_state import DeviceLatestState  # noqa: E402
from app.schemas.cellular import CellTowerImportRow, extract_cellular_payload  # noqa: E402
from app.services.cellular_position_service import (  # noqa: E402
    CellularPositionService,
    _Anchor,
)
from app.services.tracking_service import TrackingService  # noqa: E402


_ESTIMATOR_SETTINGS = SimpleNamespace(
    cell_position_serving_weight=1.5,
    cell_position_min_accuracy_m=100.0,
    cell_position_single_site_accuracy_m=3000.0,
    cell_position_max_accuracy_m=10000.0,
)


def _tower(*, latitude, longitude, site_key, accuracy=150.0):
    return CellTower(
        id=uuid.uuid4(),
        rat="LTE",
        mcc="452",
        mnc="04",
        tac=12345,
        cell_id=1000 + int(abs(latitude) * 1000) + int(abs(longitude) * 10),
        latitude=latitude,
        longitude=longitude,
        location=f"SRID=4326;POINT({longitude} {latitude})",
        site_key=site_key,
        accuracy_m=accuracy,
        is_active=True,
    )


class _ScalarResult:
    def __init__(self, value):
        self.value = value

    def scalar_one_or_none(self):
        return self.value


class _PresenceSession:
    def __init__(self, state):
        self.state = state
        self.added = []
        self.committed = False

    async def execute(self, _query):
        return _ScalarResult(self.state)

    def add(self, item):
        self.added.append(item)

    async def flush(self):
        return None

    async def commit(self):
        self.committed = True


class CellularSchemaTest(unittest.TestCase):
    def test_accepts_full_serving_and_partial_neighbor_without_guessing_identity(self):
        payload = extract_cellular_payload(
            {
                "cellular": {
                    "rat": "4G",
                    "serving_cell": {
                        "mcc": "452", "mnc": "04", "tac": 12345,
                        "eci": 12345678, "rsrp": -91,
                    },
                    "neighbor_cells": [{"pci": 101, "earfcn": 1800, "rsrp": -104}],
                }
            }
        )
        self.assertIsNotNone(payload)
        assert payload is not None
        self.assertEqual(payload.serving.rat, "LTE")
        self.assertEqual(payload.serving.cell_id, 12345678)
        self.assertEqual(payload.serving.global_identity_key(), ("LTE", "452", "04", 12345, 12345678))
        self.assertFalse(payload.neighbors[0].has_global_identity())
        self.assertIsNone(payload.neighbors[0].global_identity_key())

    def test_catalog_csv_blank_optionals_and_invalid_coordinates_are_checked(self):
        row = CellTowerImportRow.model_validate(
            {
                "mcc": "452", "mnc": "04", "tac": "123", "cell_id": "456",
                "latitude": "21.0285", "longitude": "105.8542", "pci": "",
            }
        )
        self.assertIsNone(row.pci)
        with self.assertRaises(ValueError):
            CellTowerImportRow.model_validate(
                {"mcc": "452", "mnc": "04", "tac": 1, "cell_id": 2, "latitude": 91, "longitude": 0}
            )


class CellularEstimatorTest(unittest.TestCase):
    def test_multi_site_estimate_uses_distinct_sites_and_reports_accuracy(self):
        first = _tower(latitude=21.0280, longitude=105.8500, site_key="site-a")
        same_site = _tower(latitude=21.0280, longitude=105.8500, site_key="site-a")
        second = _tower(latitude=21.0300, longitude=105.8560, site_key="site-b")
        anchors = CellularPositionService._distinct_sites(
            [
                _Anchor(first, True, -90),
                _Anchor(same_site, False, -105),
                _Anchor(second, False, -96),
            ]
        )
        with patch("app.services.cellular_position_service.settings", _ESTIMATOR_SETTINGS):
            estimate = CellularPositionService._estimate(anchors)
        self.assertEqual(len(anchors), 2)
        self.assertEqual(estimate["status"], "ESTIMATED")
        self.assertEqual(estimate["matched_cell_count"], 2)
        self.assertGreater(estimate["accuracy_m"], 100)
        self.assertLess(estimate["latitude"], 21.031)
        self.assertGreater(estimate["latitude"], 21.027)

    def test_no_catalog_match_never_invents_coordinates(self):
        with patch("app.services.cellular_position_service.settings", _ESTIMATOR_SETTINGS):
            estimate = CellularPositionService._estimate([])
        self.assertEqual(estimate["status"], "NO_MATCH")
        self.assertIsNone(estimate["latitude"])
        self.assertIsNone(estimate["longitude"])

    def test_excessive_uncertainty_is_rejected(self):
        first = _tower(latitude=10.0, longitude=106.0, site_key="a")
        second = _tower(latitude=20.0, longitude=106.0, site_key="b")
        strict_settings = SimpleNamespace(**{**_ESTIMATOR_SETTINGS.__dict__, "cell_position_max_accuracy_m": 500.0})
        with patch("app.services.cellular_position_service.settings", strict_settings):
            estimate = CellularPositionService._estimate([_Anchor(first, True, -90), _Anchor(second, False, -95)])
        self.assertEqual(estimate["status"], "REJECTED_ACCURACY")
        self.assertIsNone(estimate["latitude"])


class CellularPresenceTest(unittest.IsolatedAsyncioTestCase):
    async def test_cellular_presence_keeps_gps_fields_and_motion_untouched(self):
        device_id = uuid.uuid4()
        estimate_id = uuid.uuid4()
        state = DeviceLatestState(
            device_id=device_id,
            is_online=True,
            current_latitude=21.0,
            current_longitude=105.0,
            current_speed_mps=4.2,
            latest_measured_at=datetime(2026, 9, 25, tzinfo=timezone.utc),
        )
        session = _PresenceSession(state)
        with patch("app.services.tracking_service.realtime_service.notify_device") as notify:
            events = await TrackingService.record_cellular_presence(
                session,
                device_id,
                latest_cell_estimate_id=estimate_id,
                latest_cell_measured_at=datetime(2026, 9, 25, tzinfo=timezone.utc),
            )
        self.assertEqual(events, [])
        self.assertTrue(session.committed)
        self.assertEqual(state.latest_cell_estimate_id, estimate_id)
        self.assertEqual(state.latest_cell_measured_at, datetime(2026, 9, 25, tzinfo=timezone.utc))
        self.assertEqual(state.current_latitude, 21.0)
        self.assertEqual(state.current_longitude, 105.0)
        self.assertEqual(state.current_speed_mps, 4.2)
        notify.assert_called_once_with(device_id)

    async def test_older_cell_scan_does_not_replace_newer_estimate_pointer(self):
        device_id = uuid.uuid4()
        newest_estimate_id = uuid.uuid4()
        state = DeviceLatestState(
            device_id=device_id,
            is_online=True,
            latest_cell_estimate_id=newest_estimate_id,
            latest_cell_measured_at=datetime(2026, 9, 26, tzinfo=timezone.utc),
        )
        session = _PresenceSession(state)
        with patch("app.services.tracking_service.realtime_service.notify_device"):
            await TrackingService.record_cellular_presence(
                session,
                device_id,
                latest_cell_estimate_id=uuid.uuid4(),
                latest_cell_measured_at=datetime(2026, 9, 25, tzinfo=timezone.utc),
            )
        self.assertEqual(state.latest_cell_estimate_id, newest_estimate_id)
        self.assertEqual(state.latest_cell_measured_at, datetime(2026, 9, 26, tzinfo=timezone.utc))


if __name__ == "__main__":
    unittest.main()
