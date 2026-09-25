"""Tra catalog LTE theo batch và ước lượng vị trí từ serving/neighbor cells.

Luồng này chỉ làm việc với catalog nội bộ đã kiểm duyệt: modem -> các radio
observation -> một truy vấn anchor -> estimate. Không có HTTP/geolocation API
trong worker MQTT, nên độ trễ và khả năng chịu tải không phụ thuộc mạng ngoài.
"""
from dataclasses import dataclass
from datetime import datetime
import math
import uuid

from sqlalchemy import select, tuple_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.cell_observation import CellObservation
from app.models.cell_position_estimate import CellPositionEstimate
from app.models.cell_tower import CellTower
from app.schemas.cellular import CellIdentityKey, CellularObservationInput, CellularPayloadInput


@dataclass(frozen=True)
class _Anchor:
    """Một observation đã khớp chính xác với một tọa độ catalog.

    ``is_serving`` và ``rsrp_dbm`` là dữ liệu đo cho lần scan này, trong khi
    ``tower`` là dữ liệu địa lý dài hạn của catalog; tách hai nguồn để không
    vô tình sửa catalog theo telemetry chưa kiểm duyệt.
    """
    tower: CellTower
    is_serving: bool
    rsrp_dbm: float | None


def _haversine_m(latitude_a: float, longitude_a: float, latitude_b: float, longitude_b: float) -> float:
    """Khoảng cách mặt cầu giữa estimate và anchor, đơn vị mét.

    Hàm chỉ dùng để biểu diễn độ phân tán của nhiều trạm. Nó không biến RSRP
    thành khoảng cách hay thực hiện trilateration vì thiếu công suất phát,
    hướng sector và dữ liệu môi trường.
    """
    radius_m = 6_371_008.8
    latitude_delta = math.radians(latitude_b - latitude_a)
    longitude_delta = math.radians(longitude_b - longitude_a)
    haversine = (
        math.sin(latitude_delta / 2) ** 2
        + math.cos(math.radians(latitude_a))
        * math.cos(math.radians(latitude_b))
        * math.sin(longitude_delta / 2) ** 2
    )
    return 2 * radius_m * math.asin(math.sqrt(haversine))


def _signal_weight(anchor: _Anchor) -> float:
    # RSRP không phải khoảng cách. Chỉ dùng dải tín hiệu như trọng số tương đối,
    # đồng thời tăng nhẹ serving cell thay vì áp dụng mô hình lan truyền không có
    # công suất phát, sector và dữ liệu địa hình.
    # Clamp ngăn một RSRP bất thường chi phối hoàn toàn centroid; không có RSRP
    # vẫn giữ anchor với trọng số nền để scan cũ/firmware tối giản hoạt động.
    if anchor.rsrp_dbm is None:
        relative = 0.35
    else:
        relative = min(1.0, max(0.2, (anchor.rsrp_dbm + 140.0) / 90.0))
    return relative * (settings.cell_position_serving_weight if anchor.is_serving else 1.0)


class CellularPositionService:
    """Xử lý một LTE scan mà không commit transaction của caller.

    Caller quyết định tính nguyên tử cùng telemetry: LTE-only sẽ commit cùng
    presence/estimate, còn LTE đi kèm GPS được đặt trong savepoint để lỗi phần
    mở rộng không làm thay đổi hợp đồng GPS cũ.
    """

    @staticmethod
    async def process_scan(
        db: AsyncSession,
        *,
        device_id: uuid.UUID,
        telemetry_message_id: uuid.UUID,
        measured_at: datetime,
        received_at: datetime,
        cellular: CellularPayloadInput,
    ) -> CellPositionEstimate:
        # observation_index giữ đúng thứ tự modem gửi: index 0 luôn serving;
        # unique(telemetry_message_id, observation_index) chặn ghi lặp nếu code
        # được gọi lại trong cùng transaction.
        inputs: list[tuple[bool, CellularObservationInput]] = [(True, cellular.serving)]
        inputs.extend((False, item) for item in cellular.neighbors)

        # Gom các identity đầy đủ trước khi truy vấn để số round-trip DB không
        # tăng theo số neighbor. Neighbor thiếu identity vẫn được lưu phía dưới
        # nhưng không thể trở thành anchor.
        towers = await CellularPositionService._load_matching_towers(db, [item for _, item in inputs])

        anchors: list[_Anchor] = []
        observations: list[CellObservation] = []
        for index, (is_serving, item) in enumerate(inputs):
            # Đúng identity đầy đủ mới dùng làm dictionary key. Không fallback từ
            # PCI/EARFCN để tránh ghép nhầm trạm ở một vùng khác.
            identity_key = item.global_identity_key()
            tower = towers.get(identity_key) if identity_key is not None else None
            observations.append(
                CellObservation(
                    telemetry_message_id=telemetry_message_id,
                    device_id=device_id,
                    measured_at=measured_at,
                    observation_index=index,
                    is_serving=is_serving,
                    rat=item.rat,
                    mcc=item.mcc,
                    mnc=item.mnc,
                    tac=item.tac,
                    cell_id=item.cell_id,
                    pci=item.pci,
                    earfcn=item.earfcn,
                    rsrp_dbm=item.rsrp_dbm,
                    rsrq_db=item.rsrq_db,
                    sinr_db=item.sinr_db,
                    matched_cell_tower_id=tower.id if tower else None,
                    raw_json=item.model_dump(mode="json", exclude_none=True),
                )
            )
            # Observation không khớp vẫn được lưu raw_json để vận hành biết cần
            # bổ sung catalog nào; chỉ observation đã có tower mới là anchor.
            if tower is not None:
                anchors.append(_Anchor(tower=tower, is_serving=is_serving, rsrp_dbm=item.rsrp_dbm))
        db.add_all(observations)

        # Một site có thể phát nhiều sector/cell. Dùng một anchor/site tránh
        # nhiều sector cùng trạm làm kết quả trông có vẻ "nhiều trạm" hơn thực tế.
        unique_anchors = CellularPositionService._distinct_sites(anchors)
        estimate_data = CellularPositionService._estimate(unique_anchors)
        estimate = CellPositionEstimate(
            device_id=device_id,
            telemetry_message_id=telemetry_message_id,
            measured_at=measured_at,
            received_at=received_at,
            **estimate_data,
        )
        db.add(estimate)
        # Flush lấy UUID estimate để DeviceLatestState có thể tham chiếu ngay,
        # nhưng không commit; rollback của caller vẫn loại bỏ toàn bộ scan.
        await db.flush()
        return estimate

    @staticmethod
    async def _load_matching_towers(
        db: AsyncSession,
        inputs: list[CellularObservationInput],
    ) -> dict[CellIdentityKey, CellTower]:
        """Nạp tất cả anchor active của một scan bằng đúng một SELECT.

        Chỉ số ``ix_cell_towers_active_identity`` có cùng thứ tự cột với lookup
        này. Từ điển trả về giúp mỗi observation lấy anchor O(1) trong RAM.
        """
        keys: set[CellIdentityKey] = set()
        for item in inputs:
            identity_key = item.global_identity_key()
            if identity_key is not None:
                keys.add(identity_key)
        if not keys:
            return {}
        # tuple_ tạo so sánh theo nguyên bộ khóa thay vì năm query/neighbor;
        # điều này quan trọng khi worker cùng lúc xử lý nhiều modem scan.
        result = await db.execute(
            select(CellTower).where(
                CellTower.is_active.is_(True),
                tuple_(CellTower.rat, CellTower.mcc, CellTower.mnc, CellTower.tac, CellTower.cell_id).in_(keys),
            )
        )
        return {
            (tower.rat, tower.mcc, tower.mnc, tower.tac, tower.cell_id): tower
            for tower in result.scalars()
        }

    @staticmethod
    def _distinct_sites(anchors: list[_Anchor]) -> list[_Anchor]:
        # Chỉ giữ radio observation mạnh nhất của mỗi site. Catalog thiếu site_key
        # vẫn dùng từng row như một site độc lập để không làm mất khả năng hoạt động.
        grouped: dict[str, _Anchor] = {}
        for anchor in anchors:
            # Thiếu site_key vẫn cho phép dùng catalog cũ, nhưng mỗi cell được
            # xem là một site độc lập. Catalog tốt nên luôn điền site_key cho
            # những sector đặt tại cùng vị trí vật lý.
            site_key = anchor.tower.site_key or f"cell:{anchor.tower.id}"
            old = grouped.get(site_key)
            if old is None or _signal_weight(anchor) > _signal_weight(old):
                grouped[site_key] = anchor
        return list(grouped.values())

    @staticmethod
    def _estimate(anchors: list[_Anchor]) -> dict:
        """Tạo estimate có thể công bố hoặc một trạng thái từ chối minh bạch.

        Centroid có trọng số phù hợp khi chỉ có tọa độ cell và cường độ tương đối.
        ``accuracy_m`` bao gồm độ phân tán anchor và accuracy do catalog công bố;
        vì vậy nó là bán kính bất định, không phải lời khẳng định chính xác GPS.
        """
        if not anchors:
            # Không có match không phải lỗi worker: đây là tín hiệu vận hành để
            # import/cập nhật catalog. Null tọa độ bảo vệ client khỏi marker giả.
            return {
                "method": "LTE_MULTICELL_WEIGHTED_CENTROID_V1",
                "status": "NO_MATCH",
                "latitude": None,
                "longitude": None,
                "location": None,
                "accuracy_m": None,
                "confidence": 0.0,
                "matched_cell_count": 0,
                "diagnostics_json": {"reason": "no_catalog_match"},
            }

        # Cùng trọng số được dùng nhất quán cho lat/lon, chất lượng catalog và
        # độ phân tán; total_weight luôn dương do _signal_weight có clamp nền.
        weights = [_signal_weight(anchor) for anchor in anchors]
        total_weight = sum(weights)
        latitude = sum(anchor.tower.latitude * weight for anchor, weight in zip(anchors, weights)) / total_weight
        longitude = sum(anchor.tower.longitude * weight for anchor, weight in zip(anchors, weights)) / total_weight
        catalog_accuracy = sum((anchor.tower.accuracy_m or 0.0) * weight for anchor, weight in zip(anchors, weights)) / total_weight

        if len(anchors) == 1:
            # Một trạm chỉ cho biết vùng phục vụ, không biết thiết bị ở đâu trong
            # vùng đó. Do vậy luôn áp dụng ngưỡng single-site bảo thủ.
            accuracy_m = max(settings.cell_position_single_site_accuracy_m, catalog_accuracy)
        else:
            # RMS khoảng cách từ centroid tới các site mô tả phạm vi bất đồng của
            # scan. Cộng thêm sai số catalog để không đánh giá quá lạc quan.
            weighted_rms = math.sqrt(
                sum(
                    weight * _haversine_m(latitude, longitude, anchor.tower.latitude, anchor.tower.longitude) ** 2
                    for anchor, weight in zip(anchors, weights)
                ) / total_weight
            )
            accuracy_m = max(settings.cell_position_min_accuracy_m, weighted_rms + catalog_accuracy)

        diagnostics = {
            "distinct_site_count": len(anchors),
            "matched_cell_count": len(anchors),
            "catalog_accuracy_m": round(catalog_accuracy, 3),
        }
        if accuracy_m > settings.cell_position_max_accuracy_m:
            # Lưu estimate bị từ chối để audit, nhưng bỏ tọa độ để route REST và
            # client không thể vô tình sử dụng kết quả ngoài giới hạn đã cấu hình.
            diagnostics["reason"] = "predicted_accuracy_exceeds_limit"
            diagnostics["predicted_accuracy_m"] = round(accuracy_m, 3)
            return {
                "method": "LTE_MULTICELL_WEIGHTED_CENTROID_V1",
                "status": "REJECTED_ACCURACY",
                "latitude": None,
                "longitude": None,
                "location": None,
                "accuracy_m": accuracy_m,
                "confidence": 0.0,
                "matched_cell_count": len(anchors),
                "diagnostics_json": diagnostics,
            }

        # Confidence chỉ là tín hiệu xếp hạng UX (0..0.95), không dùng thay cho
        # accuracy_m. Cap 0.95 giữ nguyên sự thật rằng cell positioning không
        # thể chứng minh tọa độ tuyệt đối như GPS đã xác nhận.
        confidence = min(0.95, 0.25 + 0.15 * len(anchors) + 0.25 * (1 - accuracy_m / settings.cell_position_max_accuracy_m))
        return {
            "method": "LTE_MULTICELL_WEIGHTED_CENTROID_V1",
            "status": "ESTIMATED",
            "latitude": latitude,
            "longitude": longitude,
            "location": f"SRID=4326;POINT({longitude} {latitude})",
            "accuracy_m": accuracy_m,
            "confidence": max(0.0, confidence),
            "matched_cell_count": len(anchors),
            "diagnostics_json": diagnostics,
        }


cellular_position_service = CellularPositionService()
