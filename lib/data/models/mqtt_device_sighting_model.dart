class MqttDeviceSightingModel {
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
