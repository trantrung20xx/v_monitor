class LocationModel {
  final String id;
  final String deviceId;
  final DateTime measuredAt;
  final double latitude;
  final double longitude;
  final double? speedMps;
  final double? headingDeg;

  LocationModel({
    required this.id,
    required this.deviceId,
    required this.measuredAt,
    required this.latitude,
    required this.longitude,
    this.speedMps,
    this.headingDeg,
  });

  bool get isMoving => (speedMps ?? 0) > 0.5;

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      id: json['id'] ?? '',
      deviceId: json['device_id'] ?? '',
      measuredAt: DateTime.parse(json['measured_at']),
      latitude: json['latitude'],
      longitude: json['longitude'],
      speedMps: json['speed_mps'],
      headingDeg: json['heading_deg'],
    );
  }
}
