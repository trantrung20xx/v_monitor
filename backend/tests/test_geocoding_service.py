import asyncio
import os
import sys
import time
import unittest
from pathlib import Path
from urllib.error import URLError


os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services.geocoding_service import (  # noqa: E402
    GeocodingService,
    GeocodingUnavailableError,
)


class GeocodingServiceTest(unittest.TestCase):
    def test_reverse_formats_and_caches_address(self):
        service = GeocodingService()
        calls = []

        def fake_fetch(latitude, longitude):
            calls.append((latitude, longitude))
            return (
                "nominatim",
                {
                    "display_name": "1 Trang Tien, Hoan Kiem, Ha Noi, Viet Nam",
                    "address": {
                        "house_number": "1",
                        "road": "Trang Tien",
                        "suburb": "Hoan Kiem",
                        "city": "Ha Noi",
                        "country": "Viet Nam",
                    },
                },
            )

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

    def test_reverse_retries_a_transient_failure(self):
        service = GeocodingService(retry_attempts=2, retry_delay_seconds=0)
        calls = []

        def fake_fetch(latitude, longitude):
            calls.append((latitude, longitude))
            if len(calls) == 1:
                raise URLError("temporary DNS failure")
            return (
                "nominatim",
                {
                    "display_name": "Ha Noi, Viet Nam",
                    "address": {"city": "Ha Noi", "country": "Viet Nam"},
                },
            )

        service._fetch_reverse_geocode = fake_fetch

        result = asyncio.run(service.reverse(21.0285, 105.8126))

        self.assertEqual(result["formatted_address"], "Ha Noi, Viet Nam")
        self.assertEqual(len(calls), 2)

    def test_reverse_coalesces_concurrent_requests_for_the_same_coordinate(self):
        service = GeocodingService(retry_attempts=1, retry_delay_seconds=0)
        calls = []

        def fake_fetch(latitude, longitude):
            calls.append((latitude, longitude))
            time.sleep(0.02)
            return (
                "nominatim",
                {
                    "display_name": "Ha Noi, Viet Nam",
                    "address": {"city": "Ha Noi", "country": "Viet Nam"},
                },
            )

        service._fetch_reverse_geocode = fake_fetch

        async def run_test():
            return await asyncio.gather(
                service.reverse(21.0285, 105.8126),
                service.reverse(21.028504, 105.812604),
            )

        first, second = asyncio.run(run_test())

        self.assertEqual(first, second)
        self.assertEqual(len(calls), 1)

    def test_reverse_does_not_cache_a_network_failure(self):
        service = GeocodingService(retry_attempts=1, retry_delay_seconds=0)
        calls = []

        def fake_fetch(latitude, longitude):
            calls.append((latitude, longitude))
            if len(calls) == 1:
                raise URLError("temporary DNS failure")
            return (
                "nominatim",
                {
                    "display_name": "Ha Noi, Viet Nam",
                    "address": {"city": "Ha Noi", "country": "Viet Nam"},
                },
            )

        service._fetch_reverse_geocode = fake_fetch

        async def run_test():
            with self.assertRaises(GeocodingUnavailableError):
                await service.reverse(21.0285, 105.8126)
            return await service.reverse(21.0285, 105.8126)

        result = asyncio.run(run_test())

        self.assertEqual(result["formatted_address"], "Ha Noi, Viet Nam")
        self.assertEqual(len(calls), 2)

    def test_formats_photon_reverse_geocoding_payload(self):
        service = GeocodingService()

        result = service._build_result(
            "photon",
            {
                "features": [
                    {
                        "properties": {
                            "name": "Nhà hàng Như Quỳnh",
                            "housenumber": "31",
                            "street": "Đường Nguyễn Chí Thanh",
                            "locality": "Ngọc Khánh",
                            "district": "Giảng Võ",
                            "city": "Hà Nội",
                            "country": "Việt Nam",
                        }
                    }
                ]
            },
        )

        self.assertEqual(
            result["formatted_address"],
            (
                "Nhà hàng Như Quỳnh, 31 Đường Nguyễn Chí Thanh, "
                "Ngọc Khánh, Giảng Võ, Hà Nội, Việt Nam"
            ),
        )
        self.assertEqual(result["provider"], "photon")

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
