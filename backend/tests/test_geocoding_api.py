# Xác nhận API geocoding trả provider thật và ánh xạ lỗi dịch vụ ngoài thành HTTP 503.
import asyncio
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

from fastapi import HTTPException


os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.api.v1.geocoding import reverse_geocode  # noqa: E402
from app.services.geocoding_service import (  # noqa: E402
    GeocodingUnavailableError,
    geocoding_service,
)


class GeocodingApiTest(unittest.TestCase):
    def test_returns_the_actual_provider(self):
        response_data = {
            "formatted_address": "31 Đường Nguyễn Chí Thanh, Hà Nội",
            "display_name": "31 Đường Nguyễn Chí Thanh, Hà Nội, Việt Nam",
            "provider": "photon",
        }

        with patch.object(
            geocoding_service,
            "reverse",
            AsyncMock(return_value=response_data),
        ):
            response = asyncio.run(
                reverse_geocode(21.0285, 105.8126, _current_user={})
            )

        self.assertEqual(response.provider, "photon")
        self.assertEqual(response.formatted_address, response_data["formatted_address"])

    def test_returns_503_when_the_provider_is_unavailable(self):
        with patch.object(
            geocoding_service,
            "reverse",
            AsyncMock(side_effect=GeocodingUnavailableError("DNS failure")),
        ):
            with self.assertRaises(HTTPException) as raised:
                asyncio.run(reverse_geocode(21.0285, 105.8126, _current_user={}))

        self.assertEqual(raised.exception.status_code, 503)


if __name__ == "__main__":
    unittest.main()
