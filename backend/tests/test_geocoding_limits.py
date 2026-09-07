import asyncio
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://test:test@localhost:5432/test")
os.environ.setdefault("JWT_SECRET", "x" * 48)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.services.geocoding_service import GeocodingService, GeocodingUnavailableError
from app.api.auth_dependencies import require_viewer_with_short_session


class GeocodingLimitsTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.service = GeocodingService(retry_attempts=1)

    async def asyncTearDown(self):
        await self.service.close()

    async def test_queue_is_bounded_and_deadline_includes_waiting(self):
        async def blocked(*args):
            await asyncio.Event().wait()
        self.service._fetch_reverse_geocode = blocked
        with patch("app.services.geocoding_service.settings.geocoding_max_pending", 2), patch(
            "app.services.geocoding_service.settings.geocoding_request_timeout_seconds", 0.05
        ):
            first = asyncio.create_task(self.service.reverse(1, 1))
            second = asyncio.create_task(self.service.reverse(2, 2))
            await asyncio.sleep(0)
            with self.assertRaises(GeocodingUnavailableError):
                await self.service.reverse(3, 3)
            results = await asyncio.gather(first, second, return_exceptions=True)
            self.assertTrue(all(isinstance(item, GeocodingUnavailableError) for item in results))
        await asyncio.sleep(0)
        self.assertEqual(self.service._pending, {})

    async def test_lru_cache_and_ttl(self):
        self.service._fetch_reverse_geocode = AsyncMock(return_value=("nominatim", {"display_name": "Address"}))
        with patch("app.services.geocoding_service.settings.geocoding_cache_size", 2):
            await self.service.reverse(1, 1)
            await self.service.reverse(2, 2)
            await self.service.reverse(1, 1)
            await self.service.reverse(3, 3)
            self.assertEqual(len(self.service._cache), 2)
            self.assertNotIn("2.00000,2.00000", self.service._cache)
            self.service._cache["1.00000,1.00000"] = (0, {"display_name": "Expired"})
            await self.service.reverse(1, 1)
        self.assertEqual(self.service._fetch_reverse_geocode.await_count, 4)

    async def test_cancelled_caller_does_not_leak_pending_task(self):
        release = asyncio.Event()
        async def fetch(*args):
            await release.wait()
            return "nominatim", {"display_name": "Address"}
        self.service._fetch_reverse_geocode = fetch
        caller = asyncio.create_task(self.service.reverse(1, 1))
        await asyncio.sleep(0)
        caller.cancel()
        await asyncio.gather(caller, return_exceptions=True)
        release.set()
        await asyncio.gather(*list(self.service._pending.values()))
        await asyncio.sleep(0)
        self.assertEqual(self.service._pending, {})

    async def test_auth_session_closes_before_geocoding_starts(self):
        context = AsyncMock()
        credentials = type("Credentials", (), {"credentials": "test-token"})()
        with patch("app.api.auth_dependencies.AsyncSessionLocal", return_value=context), patch(
            "app.api.auth_dependencies._load_user_from_token", new=AsyncMock(return_value="viewer")
        ):
            result = await require_viewer_with_short_session(credentials)
        self.assertEqual(result, "viewer")
        context.__aexit__.assert_awaited_once()
