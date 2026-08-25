// Mô hình sự kiện nhận từ API/WebSocket: định danh thiết bị, loại, thời điểm,
// vị trí và mô tả. fromJson chỉ chuyển kiểu, không suy diễn trạng thái mới.
class DeviceEventModel {
  // Sự kiện thật do backend lưu/phát realtime, khác các mốc trình bày suy ra trong timeline.
  final String id;
  final String deviceId;
  final String eventType;
  final DateTime occurredAt;
  final String? source;
  final String? description;

  DeviceEventModel({
    required this.id,
    required this.deviceId,
    required this.eventType,
    required this.occurredAt,
    this.source,
    this.description,
  });

  String get eventLabel {
    // Ánh xạ mã kỹ thuật sang nhãn; description từ backend vẫn được giữ riêng.
    switch (eventType.toUpperCase()) {
      case 'ONLINE':
        return 'Thiết bị trực tuyến';
      case 'OFFLINE':
        return 'Thiết bị ngoại tuyến';
      case 'MOVEMENT_STARTED':
      case 'MOVING':
        return 'Bắt đầu di chuyển';
      case 'MOVEMENT_STOPPED':
      case 'IDLE':
        return 'Dừng di chuyển';
      case 'GPS_LOST':
        return 'Mất tín hiệu GPS';
      case 'GPS_RESTORED':
        return 'Tín hiệu GPS khôi phục';
      case 'GEOFENCE_EXIT':
        return 'Ra khỏi vùng an toàn';
      case 'STATUS_CHANGE':
        return 'Thay đổi trạng thái';
      case 'ERROR':
        return 'Lỗi thiết bị';
      default:
        return 'Sự kiện ($eventType)';
    }
  }

  /// Phân loại nhóm sự kiện để lọc trên giao diện
  String get category {
    // Gom nhiều eventType vào nhóm filter của tab Sự kiện mà không sửa mã gốc.
    switch (eventType.toUpperCase()) {
      case 'ONLINE':
      case 'OFFLINE':
        return 'connectivity';
      case 'MOVEMENT_STARTED':
      case 'MOVEMENT_STOPPED':
      case 'MOVING':
      case 'IDLE':
        return 'movement';
      case 'GPS_LOST':
      case 'GPS_RESTORED':
      case 'GEOFENCE_EXIT':
      case 'ERROR':
        return 'alert';
      default:
        return 'other';
    }
  }

  factory DeviceEventModel.fromJson(Map<String, dynamic> json) {
    // occurred_at là mốc nghiệp vụ bắt buộc; source/description có thể vắng ở dữ liệu cũ.
    return DeviceEventModel(
      id: json['id']?.toString() ?? '',
      deviceId: json['device_id']?.toString() ?? '',
      eventType: json['event_type']?.toString() ?? 'UNKNOWN',
      occurredAt: json['occurred_at'] != null
          ? DateTime.tryParse(json['occurred_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      source: json['source']?.toString(),
      description: json['description']?.toString(),
    );
  }
}
