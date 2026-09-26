"""Hợp đồng dữ liệu LTE giữa modem, MQTT worker, catalog và REST.

Một cell chỉ có thể được tra trong catalog khi có đủ ``MCC/MNC/TAC/cell_id``.
PCI và EARFCN chỉ có ý nghĩa trong phạm vi khu vực/tần số nên được lưu để chẩn
đoán, tuyệt đối không được dùng để đoán một cell toàn cục hay tự tạo tọa độ.
"""
from datetime import datetime
from typing import Any
import uuid

from pydantic import ConfigDict, Field, field_validator, model_validator

from app.schemas.common import BaseSchema

# Khóa dùng thống nhất giữa payload modem, dictionary catalog trong RAM và unique
# constraint của cell_towers. Tách alias này giúp static type checker biết một
# identity hoàn chỉnh không còn chứa None.
CellIdentityKey = tuple[str, str, str, int, int]


class CellularObservationInput(BaseSchema):
    """Một serving hoặc neighbor LTE; neighbor được phép thiếu identity toàn cục."""

    # Modem của các hãng thường thêm trường riêng. Giữ chúng trong model đầu vào
    # để việc nâng firmware không làm cả gói LTE bị từ chối; chỉ các trường bên
    # dưới mới tham gia lookup và ước lượng.
    model_config = ConfigDict(extra="allow")

    rat: str = "LTE"
    mcc: str | None = Field(default=None, min_length=3, max_length=3)
    mnc: str | None = Field(default=None, min_length=2, max_length=3)
    tac: int | None = Field(default=None, ge=0, le=65535)
    cell_id: int | None = Field(default=None, ge=0, le=268435455)
    pci: int | None = Field(default=None, ge=0, le=503)
    earfcn: int | None = Field(default=None, ge=0)
    rsrp_dbm: float | None = Field(default=None, ge=-160, le=-30)
    rsrq_db: float | None = Field(default=None, ge=-40, le=0)
    sinr_db: float | None = Field(default=None, ge=-30, le=60)

    @model_validator(mode="before")
    @classmethod
    def _normalize_modem_aliases(cls, value: Any):
        if not isinstance(value, dict):
            return value
        normalized = dict(value)
        # Canonical key luôn được ưu tiên. Alias chỉ là lớp tương thích cho modem
        # đang dùng camelCase hoặc thuật ngữ 3GPP như ECI/CI, không được phép ghi
        # đè giá trị mà firmware đã gửi đúng tên chuẩn.
        aliases = {
            # RAT / technology
            "network_type": "rat",
            "radio": "rat",
            "technology": "rat",

            # Cell identity
            "cell_mcc": "mcc",
            "cell_mnc": "mnc",
            "cell_tac": "tac",
            "cell_id": "cell_id",
            "cellId": "cell_id",
            "cellid": "cell_id",
            "ci": "cell_id",
            "eci": "cell_id",

            # Signal metrics
            "cell_rsrp": "rsrp_dbm",
            "cell_rsrq": "rsrq_db",
            "cell_sinr": "sinr_db",
            "rsrp": "rsrp_dbm",
            "rsrq": "rsrq_db",
            "sinr": "sinr_db",

            # If modem emits full names
            "tracking_area_code": "tac",
            "trackingAreaCode": "tac",
            "physical_cell_id": "pci",
            "physicalCellId": "pci",
        }
        for old, new in aliases.items():
            if new not in normalized and old in normalized:
                normalized[new] = normalized[old]
        return normalized

    @field_validator("rat")
    @classmethod
    def _require_lte(cls, value: str) -> str:
        normalized = value.strip().upper()
        if normalized not in {"LTE", "4G"}:
            raise ValueError("Hiện chỉ hỗ trợ radio LTE/4G")
        return "LTE"

    @field_validator("mcc", "mnc")
    @classmethod
    def _require_digits(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = str(value).strip()
        if not normalized.isdigit():
            raise ValueError("MCC/MNC chỉ gồm chữ số")
        return normalized

    def has_global_identity(self) -> bool:
        # TAC hoặc PCI riêng lẻ có thể trùng giữa mạng/khu vực. Bốn trường này là
        # khóa nghiệp vụ tối thiểu khớp unique catalog ``cell_towers``.
        return self.global_identity_key() is not None

    def global_identity_key(self) -> CellIdentityKey | None:
        """Trả khóa catalog đã được thu hẹp kiểu, hoặc None khi identity thiếu.

        ``has_global_identity`` hữu ích cho điều kiện nghiệp vụ nhưng kiểu trả về
        bool không giúp Pylance thu hẹp các thuộc tính Optional của object. Hàm
        này kiểm tra từng local value rồi chỉ tạo tuple khi tất cả khác None, vì
        vậy caller có thể truyền khóa cho ``dict[CellIdentityKey, ...]`` an toàn.
        """
        mcc = self.mcc
        mnc = self.mnc
        tac = self.tac
        cell_id = self.cell_id
        if mcc is None or mnc is None or tac is None or cell_id is None:
            return None
        return (self.rat, mcc, mnc, tac, cell_id)


class CellularPayloadInput(BaseSchema):
    """Radio scan chuẩn: serving đầy đủ identity, tối đa 32 neighbor."""

    # Giữ metadata ngoài schema như tên modem hoặc trạng thái đăng ký mạng nhưng
    # không cho phép chúng thay đổi tập trường định vị đã được kiểm tra.
    model_config = ConfigDict(extra="allow")

    rat: str = "LTE"
    serving: CellularObservationInput
    neighbors: list[CellularObservationInput] = Field(default_factory=list, max_length=64)

    @model_validator(mode="before")
    @classmethod
    def _normalize_container_aliases(cls, value: Any):
        if not isinstance(value, dict):
            return value
        normalized = dict(value)
        # Chỉ đổi tên container; từng phần tử vẫn phải qua validator của
        # CellularObservationInput để alias, dải giá trị và RAT được chuẩn hóa.
        if "serving" not in normalized:
            for alias in ("serving_cell", "servingCell", "cell"):
                if alias in normalized:
                    normalized["serving"] = normalized[alias]
                    break
        if "neighbors" not in normalized:
            for alias in ("neighbor_cells", "neighbour_cells", "neighborCells", "cells"):
                if alias in normalized:
                    normalized["neighbors"] = normalized[alias]
                    break
        return normalized

    @model_validator(mode="after")
    def _validate_serving_identity(self):
        # Neighbor scan có thể chỉ có PCI/EARFCN, còn serving cell bắt buộc có
        # identity toàn cục: nếu thiếu thì ngay cả kết quả một trạm cũng không có
        # anchor đáng tin để ước lượng.
        if not self.serving.has_global_identity():
            raise ValueError("Serving cell LTE phải có MCC, MNC, TAC và cell_id/ECI")
        if self.rat.strip().upper() not in {"LTE", "4G"}:
            raise ValueError("Hiện chỉ hỗ trợ radio LTE/4G")
        return self


def _normalize_legacy_cellular_aliases(data: dict[str, Any]) -> dict[str, Any]:
    """Chuẩn hóa alias raw LTE phổ biến trước khi build candidate."""
    if not isinstance(data, dict):
        return data

    normalized = dict(data)

    # Root-level aliases chung
    aliases = {
        "cell_mcc": "mcc",
        "cell_mnc": "mnc",
        "cell_tac": "tac",
        "cell_id": "cell_id",
        "cellId": "cell_id",
        "cellid": "cell_id",
        "ci": "cell_id",
        "eci": "cell_id",
        "cell_rsrp": "rsrp_dbm",
        "cell_rsrq": "rsrq_db",
        "cell_sinr": "sinr_db",
        "rsrp": "rsrp_dbm",
        "rsrq": "rsrq_db",
        "sinr": "sinr_db",
    }
    for old, new in aliases.items():
        if old in normalized and new not in normalized:
            normalized[new] = normalized[old]

    # cellular.serving aliases
    if "cellular" in normalized and isinstance(normalized["cellular"], dict):
        cellular = dict(normalized["cellular"])
        serving = cellular.get("serving")
        if serving is None:
            for alias in ("serving_cell", "servingCell", "cell"):
                if alias in cellular:
                    serving = cellular[alias]
                    break
        if isinstance(serving, dict):
            for old, new in aliases.items():
                if old in serving and new not in serving:
                    serving[new] = serving[old]
            cellular["serving"] = serving
        normalized["cellular"] = cellular

    # Chuẩn hóa kiểu cơ bản để tránh lỗi validate từ int/string mismatch
    if "mcc" in normalized and normalized["mcc"] is not None and not isinstance(normalized["mcc"], str):
        normalized["mcc"] = str(normalized["mcc"])
    if "mnc" in normalized and normalized["mnc"] is not None and not isinstance(normalized["mnc"], str):
        normalized["mnc"] = str(normalized["mnc"]) if not isinstance(normalized["mnc"], int) else f"{normalized['mnc']:02d}"

    return normalized


def extract_cellular_payload(data: dict[str, Any]) -> CellularPayloadInput | None:
    """Lấy payload chuẩn từ envelope mới hoặc alias modem tối thiểu.

    Không đoán identity từ PCI. Nếu không có cellular envelope hay root identity,
    trả ``None`` để giữ nguyên xử lý telemetry không có vị trí của hệ thống cũ.
    """
    normalized = _normalize_legacy_cellular_aliases(data)

    candidate = normalized.get("cellular") or normalized.get("cell_info")
    if candidate is None and all(key in normalized for key in ("mcc", "mnc", "tac")) and any(
        key in normalized for key in ("cell_id", "cellId", "cellid", "ci", "eci")
    ):
        candidate = {
            "rat": normalized.get("rat") or normalized.get("network_type") or normalized.get("radio") or "LTE",
            "serving": normalized,
            "neighbors": normalized.get("neighbors") or normalized.get("neighbor_cells") or normalized.get("neighbour_cells") or [],
        }
    if candidate is None:
        return None

    # Gọi model_validate ở một điểm duy nhất để MQTT worker nhận cùng một lỗi
    # validation bất kể modem dùng envelope mới hay payload root cũ.
    return CellularPayloadInput.model_validate(candidate)

class CellPositionEstimateResponse(BaseSchema):
    """Response chỉ-đọc của estimate LTE, tách khỏi DeviceResponse GPS.

    ``status`` có thể là ESTIMATED, NO_MATCH hoặc REJECTED_ACCURACY. Hai trạng
    thái sau cố ý có latitude/longitude là null để client không hiển thị vị trí
    cũ hoặc vị trí suy đoán không đủ tin cậy như thể đó là GPS.
    """
    id: uuid.UUID
    device_id: uuid.UUID
    telemetry_message_id: uuid.UUID
    measured_at: datetime
    received_at: datetime
    method: str
    status: str
    latitude: float | None = None
    longitude: float | None = None
    accuracy_m: float | None = None
    confidence: float
    matched_cell_count: int


class CellTowerImportRow(BaseSchema):
    """Dòng catalog CSV chuẩn, dùng chung cho import để chặn dữ liệu anchor sai."""

    # CSV nhà cung cấp có thể mang cột mô tả dư. Bỏ qua chúng để định dạng import
    # ổn định, còn các cột định vị bắt buộc vẫn bị Pydantic kiểm tra chặt chẽ.
    model_config = ConfigDict(extra="ignore")

    rat: str = "LTE"
    mcc: str = Field(min_length=3, max_length=3)
    mnc: str = Field(min_length=2, max_length=3)
    tac: int = Field(ge=0, le=65535)
    cell_id: int = Field(ge=0, le=268435455)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    pci: int | None = Field(default=None, ge=0, le=503)
    earfcn: int | None = Field(default=None, ge=0)
    site_key: str | None = Field(default=None, max_length=128)
    accuracy_m: float | None = Field(default=None, ge=0)
    source_updated_at: datetime | None = None
    is_active: bool = True

    @model_validator(mode="before")
    @classmethod
    def _normalize_blank_csv_values(cls, value: Any):
        if not isinstance(value, dict):
            return value
        # csv.DictReader trả chuỗi rỗng cho ô trống; đổi thành None giúp các cột
        # tùy chọn (PCI, EARFCN, site_key...) không bị lỗi ép kiểu giả tạo.
        return {
            key: None if isinstance(item, str) and not item.strip() else item
            for key, item in value.items()
        }

    @field_validator("rat")
    @classmethod
    def _tower_lte_only(cls, value: str) -> str:
        normalized = value.strip().upper()
        if normalized not in {"LTE", "4G"}:
            raise ValueError("Catalog hiện chỉ nhận LTE/4G")
        return "LTE"

    @field_validator("mcc", "mnc")
    @classmethod
    def _tower_digits(cls, value: str) -> str:
        normalized = str(value).strip()
        if not normalized.isdigit():
            raise ValueError("MCC/MNC chỉ gồm chữ số")
        return normalized
