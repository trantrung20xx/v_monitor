// Thống kê một device_code MQTT chưa đăng ký: lần đầu/cuối thấy, số gói và topic.
// Model này không đại diện thiết bị được phép hoạt động.
class MqttDeviceSightingModel {
  // Thống kê gộp một device_code lạ trên MQTT; đây chưa phải DeviceModel đã đăng ký.
  const MqttDeviceSightingModel({
    required this.deviceCode,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.messageCount,
    required this.lastTopic,
  });

  final String deviceCode;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final int messageCount;
  final String lastTopic;

  factory MqttDeviceSightingModel.fromJson(Map<String, dynamic> json) {
    // first/last seen và messageCount lấy từ backend, UI không tự tạo trạng thái online.
    return MqttDeviceSightingModel(
      deviceCode: json['device_code']?.toString() ?? '',
      firstSeenAt:
          DateTime.tryParse(json['first_seen_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastSeenAt:
          DateTime.tryParse(json['last_seen_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
      lastTopic: json['last_topic']?.toString() ?? '',
    );
  }
}
