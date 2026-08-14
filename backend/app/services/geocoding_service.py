import asyncio
import json
import logging
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from app.core.config import settings

logger = logging.getLogger(__name__)


class GeocodingService:
    def __init__(self):
        self._cache: dict[str, dict[str, str | None]] = {}

    async def reverse(self, latitude: float, longitude: float) -> dict[str, str | None]:
        cache_key = f"{latitude:.4f},{longitude:.4f}"
        cached = self._cache.get(cache_key)
        if cached is not None:
            return cached

        try:
            payload = await asyncio.to_thread(
                self._fetch_reverse_geocode,
                latitude,
                longitude,
            )
        except (HTTPError, URLError, TimeoutError, OSError) as exc:
            logger.warning("Reverse geocoding failed: %s", exc)
            payload = {}
        except Exception as exc:
            logger.exception("Unexpected reverse geocoding error: %s", exc)
            payload = {}

        address = self._format_address(payload.get("address"))
        display_name = self._clean_text(payload.get("display_name"))
        result = {
            "formatted_address": address or display_name,
            "display_name": display_name,
        }
        self._cache[cache_key] = result
        return result

    def _fetch_reverse_geocode(
        self,
        latitude: float,
        longitude: float,
    ) -> dict:
        base_url = settings.geocoding_base_url.rstrip("/")
        query = urlencode(
            {
                "format": "jsonv2",
                "lat": f"{latitude:.7f}",
                "lon": f"{longitude:.7f}",
                "addressdetails": 1,
                "accept-language": "vi,en",
            }
        )
        request = Request(
            f"{base_url}/reverse?{query}",
            headers={
                "Accept": "application/json",
                "User-Agent": settings.geocoding_user_agent,
            },
        )
        with urlopen(  # noqa: S310 - base URL is controlled by backend settings.
            request,
            timeout=settings.geocoding_timeout_seconds,
        ) as response:
            raw = response.read().decode("utf-8")
        parsed = json.loads(raw)
        return parsed if isinstance(parsed, dict) else {}

    def _format_address(self, address: object) -> str | None:
        if not isinstance(address, dict):
            return None

        road = self._first_text(
            address,
            [
                "road",
                "pedestrian",
                "footway",
                "path",
                "residential",
                "neighbourhood",
            ],
        )
        house_number = self._clean_text(address.get("house_number"))
        if road and house_number and not road.startswith(house_number):
            road = f"{house_number} {road}"

        parts = [
            road,
            self._first_text(address, ["suburb", "city_district", "quarter"]),
            self._first_text(address, ["village", "town", "city"]),
            self._clean_text(address.get("county")),
            self._clean_text(address.get("state")),
            self._clean_text(address.get("country")),
        ]

        cleaned: list[str] = []
        for part in parts:
            if not part or part.lower() == "unnamed road":
                continue
            if any(part == existing or part in existing for existing in cleaned):
                continue
            cleaned = [existing for existing in cleaned if existing not in part]
            cleaned.append(part)

        return ", ".join(cleaned) if cleaned else None

    def _first_text(self, values: dict, keys: list[str]) -> str | None:
        for key in keys:
            value = self._clean_text(values.get(key))
            if value:
                return value
        return None

    def _clean_text(self, value: object) -> str | None:
        if value is None:
            return None
        text = str(value).strip()
        return text or None


geocoding_service = GeocodingService()
