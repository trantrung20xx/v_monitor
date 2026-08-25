import asyncio
import json
import logging
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from app.core.config import settings

logger = logging.getLogger(__name__)


class GeocodingUnavailableError(RuntimeError):
    pass


class GeocodingService:
    def __init__(
        self,
        *,
        retry_attempts: int | None = None,
        retry_delay_seconds: float | None = None,
    ):
        self._cache: dict[str, dict[str, str | None]] = {}
        self._pending: dict[str, asyncio.Task[dict[str, str | None]]] = {}
        self._provider_request_lock = asyncio.Lock()
        self._retry_attempts = retry_attempts or settings.geocoding_retry_attempts
        self._retry_delay_seconds = (
            settings.geocoding_retry_delay_seconds
            if retry_delay_seconds is None
            else retry_delay_seconds
        )

    async def reverse(self, latitude: float, longitude: float) -> dict[str, str | None]:
        cache_key = f"{latitude:.5f},{longitude:.5f}"
        cached = self._cache.get(cache_key)
        if cached is not None:
            return cached

        pending = self._pending.get(cache_key)
        if pending is None:
            pending = asyncio.create_task(
                self._resolve_uncached(cache_key, latitude, longitude)
            )
            self._pending[cache_key] = pending

        try:
            return await asyncio.shield(pending)
        finally:
            if pending.done() and self._pending.get(cache_key) is pending:
                self._pending.pop(cache_key, None)

    async def _resolve_uncached(
        self,
        cache_key: str,
        latitude: float,
        longitude: float,
    ) -> dict[str, str | None]:
        last_error: Exception | None = None
        for attempt in range(1, self._retry_attempts + 1):
            try:
                async with self._provider_request_lock:
                    provider, payload = await asyncio.to_thread(
                        self._fetch_reverse_geocode,
                        latitude,
                        longitude,
                    )
                result = self._build_result(provider, payload)
                if result["formatted_address"] or result["display_name"]:
                    self._cache[cache_key] = result
                return result
            except (HTTPError, URLError, TimeoutError, OSError, ValueError) as exc:
                last_error = exc
                logger.warning(
                    "Reverse geocoding attempt %s/%s failed: %s",
                    attempt,
                    self._retry_attempts,
                    exc,
                )
            except Exception as exc:
                last_error = exc
                logger.exception("Unexpected reverse geocoding error: %s", exc)

            if attempt < self._retry_attempts and self._retry_delay_seconds > 0:
                await asyncio.sleep(self._retry_delay_seconds)

        raise GeocodingUnavailableError(
            "Reverse geocoding provider is temporarily unavailable"
        ) from last_error

    def _build_result(
        self,
        provider: str,
        payload: dict,
    ) -> dict[str, str | None]:
        normalized = (
            self._normalize_photon_payload(payload)
            if provider == "photon"
            else payload
        )

        address = self._format_address(normalized.get("address"))
        display_name = self._clean_text(normalized.get("display_name"))
        return {
            "formatted_address": address or display_name,
            "display_name": display_name,
            "provider": provider,
        }

    def _fetch_reverse_geocode(
        self,
        latitude: float,
        longitude: float,
    ) -> tuple[str, dict]:
        provider = settings.geocoding_provider
        base_url = settings.geocoding_base_url.rstrip("/")
        if provider == "photon":
            query = urlencode(
                {
                    "lat": f"{latitude:.7f}",
                    "lon": f"{longitude:.7f}",
                    "limit": 1,
                }
            )
        else:
            query = urlencode(
                {
                    "format": "jsonv2",
                    "lat": f"{latitude:.7f}",
                    "lon": f"{longitude:.7f}",
                    "addressdetails": 1,
                    "accept-language": "vi,en",
                    "zoom": 18,
                }
            )
        headers = {
            "Accept": "application/json",
            "User-Agent": settings.geocoding_user_agent,
        }
        if provider == "nominatim":
            headers["Accept-Language"] = "vi,en;q=0.8"
        request = Request(f"{base_url}/reverse?{query}", headers=headers)
        with urlopen(  # noqa: S310 - base URL is controlled by backend settings.
            request,
            timeout=settings.geocoding_timeout_seconds,
        ) as response:
            raw = response.read().decode("utf-8")
        parsed = json.loads(raw)
        if not isinstance(parsed, dict):
            raise ValueError("Reverse geocoding provider returned invalid JSON")
        return provider, parsed

    def _normalize_photon_payload(self, payload: dict) -> dict:
        features = payload.get("features")
        if not isinstance(features, list) or not features:
            return {}

        first_feature = features[0]
        if not isinstance(first_feature, dict):
            return {}
        properties = first_feature.get("properties")
        if not isinstance(properties, dict):
            return {}

        address = {
            "amenity": properties.get("name"),
            "house_number": properties.get("housenumber"),
            "road": properties.get("street"),
            "neighbourhood": properties.get("locality"),
            "city_district": properties.get("district"),
            "county": properties.get("county"),
            "city": properties.get("city"),
            "state": properties.get("state"),
            "country": properties.get("country"),
        }
        display_name = self._format_address(address)
        return {"address": address, "display_name": display_name}

    def _format_address(self, address: object) -> str | None:
        if not isinstance(address, dict):
            return None

        poi = self._first_text(
            address,
            [
                "amenity",
                "building",
                "office",
                "shop",
                "tourism",
                "leisure",
                "historic",
                "place",
            ],
        )
        road = self._first_text(
            address,
            [
                "road",
                "street",
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
            poi,
            road,
            self._first_text(
                address,
                [
                    "neighbourhood",
                    "quarter",
                    "suburb",
                    "ward",
                ],
            ),
            self._first_text(
                address,
                [
                    "city_district",
                    "district",
                    "borough",
                ],
            ),
            self._first_text(
                address,
                ["village", "town", "municipality", "city", "county"],
            ),
            self._first_text(
                address,
                ["state_district", "province", "state", "region"],
            ),
            self._clean_text(address.get("country")),
        ]

        cleaned: list[str] = []
        for part in parts:
            if not part or part.lower() == "unnamed road":
                continue
            normalized_part = part.casefold()
            if any(normalized_part == existing.casefold() for existing in cleaned):
                continue
            cleaned = [
                existing
                for existing in cleaned
                if existing.casefold() not in normalized_part
            ]
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
