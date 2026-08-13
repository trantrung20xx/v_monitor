class UsageSessionModel {
  final String id;
  final String deviceId;
  final String personId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double? distanceM;
  final double? avgSpeedMps;
  final double? maxSpeedMps;
  final int? movingDurationS;
  final int? stoppedDurationS;
  final String status;
  final String? endReason;
  final String? personName;
  final String? personCode;

  UsageSessionModel({
    required this.id,
    required this.deviceId,
    required this.personId,
    required this.startedAt,
    this.endedAt,
    this.distanceM,
    this.avgSpeedMps,
    this.maxSpeedMps,
    this.movingDurationS,
    this.stoppedDurationS,
    required this.status,
    this.endReason,
    this.personName,
    this.personCode,
  });

  factory UsageSessionModel.fromJson(Map<String, dynamic> json) {
    return UsageSessionModel(
      id: json['id'] ?? '',
      deviceId: json['device_id'] ?? '',
      personId: json['person_id'] ?? '',
      startedAt: DateTime.parse(json['started_at']).toLocal(),
      endedAt: json['ended_at'] != null ? DateTime.parse(json['ended_at']).toLocal() : null,
      distanceM: json['distance_m'] != null ? (json['distance_m'] as num).toDouble() : null,
      avgSpeedMps: json['avg_speed_mps'] != null ? (json['avg_speed_mps'] as num).toDouble() : null,
      maxSpeedMps: json['max_speed_mps'] != null ? (json['max_speed_mps'] as num).toDouble() : null,
      movingDurationS: json['moving_duration_s'],
      stoppedDurationS: json['stopped_duration_s'],
      status: json['status'] ?? 'ACTIVE',
      endReason: json['end_reason'],
      personName: json['person_name'],
      personCode: json['person_code'],
    );
  }
}
