class LocationModel {
  final String id;
  final String deviceId;
  final DateTime measuredAt;
  final double latitude;
  final double longitude;
  final double? altitudeM;
  final double? speedMps;
  final double? headingDeg;
  final double? accuracyM;
  final int? satelliteCount;
  final String? source;
  final DateTime? receivedAt;
  final DateTime? createdAt;

  LocationModel({
    required this.id,
    required this.deviceId,
    required this.measuredAt,
    required this.latitude,
    required this.longitude,
    this.altitudeM,
    this.speedMps,
    this.headingDeg,
    this.accuracyM,
    this.satelliteCount,
    this.source,
    this.receivedAt,
    this.createdAt,
  });

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      id: json['id'] ?? '',
      deviceId: json['device_id'] ?? '',
      measuredAt: DateTime.parse(json['measured_at']),
      latitude: _doubleOrZero(json['latitude']),
      longitude: _doubleOrZero(json['longitude']),
      altitudeM: _doubleOrNull(json['altitude_m']),
      speedMps: _doubleOrNull(json['speed_mps']),
      headingDeg: _doubleOrNull(json['heading_deg']),
      accuracyM: _doubleOrNull(json['accuracy_m']),
      satelliteCount: _intOrNull(json['satellite_count']),
      source: _stringOrNull(json['source']),
      receivedAt: _dateOrNull(json['received_at']),
      createdAt: _dateOrNull(json['created_at']),
    );
  }

  static double _doubleOrZero(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _doubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _intOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static String? _stringOrNull(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static DateTime? _dateOrNull(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
