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

class UsageStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"
    UNKNOWN = "UNKNOWN"

class ProcessingStatus(str, enum.Enum):
    PENDING = "PENDING"
    PROCESSED = "PROCESSED"
    FAILED = "FAILED"
    SKIPPED = "SKIPPED"
