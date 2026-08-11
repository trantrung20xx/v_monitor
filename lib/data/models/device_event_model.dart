class DeviceEventModel {
  final String id;
  final String deviceId;
  final String eventType;
  final DateTime occurredAt;
  final String? source;

  DeviceEventModel({
    required this.id,
    required this.deviceId,
    required this.eventType,
    required this.occurredAt,
    this.source,
  });

  String get eventLabel {
    switch (eventType) {
      case 'STATUS_CHANGE': return 'Thay đổi trạng thái';
      case 'BATTERY_LOW': return 'Pin yếu';
      case 'GEOFENCE_EXIT': return 'Ra khỏi vùng an toàn';
      case 'ERROR': return 'Lỗi thiết bị';
      default: return 'Sự kiện ($eventType)';
    }
  }

  factory DeviceEventModel.fromJson(Map<String, dynamic> json) {
    return DeviceEventModel(
      id: json['id'] ?? '',
      deviceId: json['device_id'] ?? '',
      eventType: json['event_type'] ?? 'UNKNOWN',
      occurredAt: DateTime.parse(json['occurred_at']),
      source: json['source'],
    );
  }
}
