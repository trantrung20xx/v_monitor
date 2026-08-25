# Dịch vụ reverse geocoding có cache theo tọa độ làm tròn, gộp request đồng thời,
# giới hạn request tuần tự và retry lỗi mạng tạm thời trước khi báo không khả dụng.
import asyncio
import json
import logging
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from app.core.config import settings

logger = logging.getLogger(__name__)


class GeocodingUnavailableError(RuntimeError):
    # Phân biệt lỗi nhà cung cấp/mạng tạm thời với tọa độ đầu vào sai ở tầng API.
    pass


class GeocodingService:
    # Dịch GPS thành địa chỉ đọc được nhưng không tham gia quyết định tracking;
    # geocoding lỗi không được làm mất telemetry hoặc latest state.
    def __init__(
        self,
        *,
        retry_attempts: int | None = None,
        retry_delay_seconds: float | None = None,
    ):
        # cache lưu kết quả thành công theo tọa độ làm tròn; pending gộp các request
        # trùng đang chạy; lock giới hạn toàn tiến trình chỉ gọi provider tuần tự.
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
        # Năm chữ số thập phân đủ gộp các tọa độ rất gần nhau, giảm gọi API mà vẫn
        # giữ địa chỉ có ý nghĩa ở quy mô đường/phố.
        cache_key = f"{latitude:.5f},{longitude:.5f}"
        cached = self._cache.get(cache_key)
        # Cache hit không gọi mạng và trả cùng cấu trúc đã chuẩn hóa.
        if cached is not None:
            return cached

        pending = self._pending.get(cache_key)
        # Chỉ request đầu tiên cho một tọa độ tạo task provider mới.
        if pending is None:
            # Request đầu tiên sở hữu task; các request sau cùng tọa độ chỉ await task đó.
            pending = asyncio.create_task(
                self._resolve_uncached(cache_key, latitude, longitude)
            )
            self._pending[cache_key] = pending

        try:
            # shield ngăn một HTTP request client bị hủy kéo theo việc hủy lookup dùng
            # chung mà các request khác vẫn đang chờ.
            # Mọi caller cùng cache_key nhận kết quả hoặc exception từ cùng một task.
            return await asyncio.shield(pending)
        finally:
            # Chỉ task đang được map giữ quyền xóa, tránh xóa nhầm task mới cùng khóa.
            if pending.done() and self._pending.get(cache_key) is pending:
                self._pending.pop(cache_key, None)

    async def _resolve_uncached(
        self,
        cache_key: str,
        latitude: float,
        longitude: float,
    ) -> dict[str, str | None]:
        # Chỉ cache khi provider trả được một chuỗi địa chỉ; kết quả rỗng có thể thử
        # lại ở request sau thay vì trở thành dữ liệu rỗng cố định.
        last_error: Exception | None = None
        for attempt in range(1, self._retry_attempts + 1):
            try:
                # Lock tuần tự hóa lời gọi provider để tuân thủ giới hạn dịch vụ công cộng.
                async with self._provider_request_lock:
                    # urllib là API blocking nên chạy trong thread, không chặn event loop FastAPI.
                    provider, payload = await asyncio.to_thread(
                        self._fetch_reverse_geocode,
                        latitude,
                        longitude,
                    )
                result = self._build_result(provider, payload)
                # Chỉ cache địa chỉ có nội dung; kết quả rỗng được phép thử lại lần sau.
                if result["formatted_address"] or result["display_name"]:
                    self._cache[cache_key] = result
                return result
            except (HTTPError, URLError, TimeoutError, OSError, ValueError) as exc:
                # Đây là lỗi mạng/payload có thể phục hồi nên tiếp tục retry theo cấu hình.
                last_error = exc
                logger.warning(
                    "Reverse geocoding attempt %s/%s failed: %s",
                    attempt,
                    self._retry_attempts,
                    exc,
                )
            except Exception as exc:
                # Lỗi không dự kiến vẫn được lưu làm nguyên nhân và thử lại có giới hạn.
                last_error = exc
                logger.exception("Unexpected reverse geocoding error: %s", exc)

            # Không sleep sau lần cuối; delay bằng 0 tắt hoàn toàn thời gian chờ retry.
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
        # Photon và Nominatim có payload khác nhau; kết quả ra luôn cùng hợp đồng
        # formatted_address/display_name/provider cho Flutter.
        normalized = (
            # Photon cần chuyển FeatureCollection thành object giống Nominatim;
            # Nominatim đã có sẵn address/display_name nên dùng trực tiếp.
            self._normalize_photon_payload(payload)
            if provider == "photon"
            else payload
        )

        address = self._format_address(normalized.get("address"))
        display_name = self._clean_text(normalized.get("display_name"))
        return {
            # formatted_address ưu tiên chuỗi tự ghép đã loại trùng; display_name
            # là phương án dự phòng khi provider thiếu address details.
            "formatted_address": address or display_name,
            "display_name": display_name,
            "provider": provider,
        }

    def _fetch_reverse_geocode(
        self,
        latitude: float,
        longitude: float,
    ) -> tuple[str, dict]:
        # Hàm blocking này luôn được gọi qua asyncio.to_thread. base_url và User-Agent
        # lấy từ Settings để đổi provider/server mà không sửa source code.
        provider = settings.geocoding_provider
        base_url = settings.geocoding_base_url.rstrip("/")
        # Photon và Nominatim dùng tên tham số/định dạng response khác nhau.
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
        # Header User-Agent là yêu cầu nhận diện ứng dụng của provider công cộng.
        headers = {
            "Accept": "application/json",
            "User-Agent": settings.geocoding_user_agent,
        }
        # Nominatim đọc ngôn ngữ từ cả query và header; Photon dùng query mặc định.
        if provider == "nominatim":
            headers["Accept-Language"] = "vi,en;q=0.8"
        # URL hoàn chỉnh được tạo từ base URL đã kiểm tra và query đã encode.
        request = Request(f"{base_url}/reverse?{query}", headers=headers)
        # Timeout mạng lấy từ cấu hình để request lỗi không giữ thread vô hạn.
        with urlopen(  # noqa: S310 - base URL is controlled by backend settings.
            request,
            timeout=settings.geocoding_timeout_seconds,
        ) as response:
            raw = response.read().decode("utf-8")
        # JSON hợp lệ nhưng không phải object vẫn sai hợp đồng provider.
        parsed = json.loads(raw)
        if not isinstance(parsed, dict):
            raise ValueError("Reverse geocoding provider returned invalid JSON")
        return provider, parsed

    def _normalize_photon_payload(self, payload: dict) -> dict:
        # Photon trả FeatureCollection; chỉ lấy feature tốt nhất do request đặt limit=1.
        features = payload.get("features")
        # Không có feature nghĩa provider không tìm được địa chỉ, không phải lỗi parse.
        if not isinstance(features, list) or not features:
            return {}

        # Mỗi lớp payload đều được kiểm tra kiểu trước khi đọc sâu để tránh lỗi KeyError/TypeError.
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
        # Xếp thành phần từ cụ thể đến tổng quát, bỏ đường vô danh và loại phần lặp
        # để chuỗi địa chỉ ngắn nhưng vẫn đủ nhận biết cho người vận hành.
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
        # Chỉ ghép số nhà khi tên đường chưa bắt đầu bằng chính số đó để tránh lặp.
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
            # Bỏ phần rỗng và nhãn kỹ thuật không hữu ích với người dùng.
            if not part or part.lower() == "unnamed road":
                continue
            normalized_part = part.casefold()
            # So sánh không phân biệt hoa thường để loại phần trùng hoàn toàn.
            if any(normalized_part == existing.casefold() for existing in cleaned):
                continue
            # Nếu phần mới đã chứa phần cũ, bỏ phần cũ ngắn hơn để địa chỉ không lặp.
            cleaned = [
                existing
                for existing in cleaned
                if existing.casefold() not in normalized_part
            ]
            cleaned.append(part)

        return ", ".join(cleaned) if cleaned else None

    def _first_text(self, values: dict, keys: list[str]) -> str | None:
        # Mỗi provider/quốc gia có thể dùng khóa khác; lấy khóa đầu tiên có nội dung.
        for key in keys:
            value = self._clean_text(values.get(key))
            # Thứ tự keys thể hiện độ ưu tiên nghiệp vụ; gặp giá trị đầu tiên thì dừng.
            if value:
                return value
        return None

    def _clean_text(self, value: object) -> str | None:
        # Chuẩn hóa mọi giá trị provider thành chuỗi đã trim hoặc None.
        if value is None:
            return None
        text = str(value).strip()
        return text or None


# Singleton giữ cache và bộ giới hạn request xuyên suốt vòng đời API.
geocoding_service = GeocodingService()
