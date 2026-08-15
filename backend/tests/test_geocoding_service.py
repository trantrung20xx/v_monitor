import asyncio
import os
import sys
import unittest
from pathlib import Path


os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services.geocoding_service import GeocodingService  # noqa: E402


class GeocodingServiceTest(unittest.TestCase):
    def test_reverse_formats_and_caches_address(self):
        service = GeocodingService()
        calls = []

        def fake_fetch(latitude, longitude):
            calls.append((latitude, longitude))
            return {
                "display_name": "1 Trang Tien, Hoan Kiem, Ha Noi, Viet Nam",
                "address": {
                    "house_number": "1",
                    "road": "Trang Tien",
                    "suburb": "Hoan Kiem",
                    "city": "Ha Noi",
                    "country": "Viet Nam",
                },
            }

        service._fetch_reverse_geocode = fake_fetch

        async def run_test():
            first = await service.reverse(21.147, 105.8048)
            second = await service.reverse(21.147004, 105.804804)
            return first, second

        first, second = asyncio.run(run_test())

        self.assertEqual(
            first["formatted_address"],
            "1 Trang Tien, Hoan Kiem, Ha Noi, Viet Nam",
        )
        self.assertEqual(second, first)
        self.assertEqual(len(calls), 1)

    def test_format_address_supports_international_components(self):
        service = GeocodingService()

        formatted = service._format_address(
            {
                "building": "Central Station",
                "road": "Main Street",
                "neighbourhood": "Midtown",
                "borough": "Manhattan",
                "city": "New York",
                "state": "New York",
                "country": "United States",
            }
        )

        self.assertEqual(
            formatted,
            "Central Station, Main Street, Midtown, Manhattan, New York, United States",
        )


if __name__ == "__main__":
    unittest.main()
