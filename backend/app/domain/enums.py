# Các enum là từ vựng nghiệp vụ dùng chung giữa database, schema và service.
# Giá trị chuỗi là hợp đồng lưu trữ/API nên không đổi nếu chưa có migration tương ứng.
import enum

class DeviceType(str, enum.Enum):
    # Phân loại phần cứng phục vụ biểu tượng/lọc, không quyết định quyền nhận dữ liệu.
    UAV_CONTROLLER = "UAV_CONTROLLER"
    VEHICLE = "VEHICLE"
    OTHER = "OTHER"

class DeviceStatus(str, enum.Enum):
    # Trạng thái hồ sơ do quản trị; online realtime nằm riêng trong latest_state.
    UNKNOWN = "UNKNOWN"
    OFFLINE = "OFFLINE"
    ONLINE = "ONLINE"
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    MAINTENANCE = "MAINTENANCE"
    RETIRED = "RETIRED"

class ProcessingStatus(str, enum.Enum):
    # Vòng đời một telemetry từ lúc lưu PENDING đến kết quả cuối.
    PENDING = "PENDING"
    PROCESSED = "PROCESSED"
    FAILED = "FAILED"
    SKIPPED = "SKIPPED"


class UserRole(str, enum.Enum):
    # ADMIN có quyền quản trị; USER chỉ dùng chức năng giám sát được cấp.
    ADMIN = "ADMIN"
    USER = "USER"
