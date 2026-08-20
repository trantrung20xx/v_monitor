import enum

class DeviceType(str, enum.Enum):
    UAV_CONTROLLER = "UAV_CONTROLLER"
    VEHICLE = "VEHICLE"
    OTHER = "OTHER"

class DeviceStatus(str, enum.Enum):
    UNKNOWN = "UNKNOWN"
    OFFLINE = "OFFLINE"
    ONLINE = "ONLINE"
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"
    MAINTENANCE = "MAINTENANCE"
    RETIRED = "RETIRED"

class ProcessingStatus(str, enum.Enum):
    PENDING = "PENDING"
    PROCESSED = "PROCESSED"
    FAILED = "FAILED"
    SKIPPED = "SKIPPED"


class UserRole(str, enum.Enum):
    ADMIN = "ADMIN"
    USER = "USER"
