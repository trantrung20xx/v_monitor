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

class AssignmentType(str, enum.Enum):
    RESPONSIBLE = "RESPONSIBLE"
    OPERATOR = "OPERATOR"

class UsageStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"
    UNKNOWN = "UNKNOWN"

class BatteryType(str, enum.Enum):
    CONTROLLER = "CONTROLLER"
    UAV = "UAV"
    VEHICLE = "VEHICLE"

class ProcessingStatus(str, enum.Enum):
    PENDING = "PENDING"
    PROCESSED = "PROCESSED"
    FAILED = "FAILED"
    SKIPPED = "SKIPPED"
