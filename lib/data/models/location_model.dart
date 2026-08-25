// Một phép đo GPS bất biến. measuredAt là lúc thiết bị đo, receivedAt là lúc
// backend nhận; hai mốc này không được tráo vì dùng đánh giá độ trễ và thứ tự hành trình.
class LocationModel {
  // Một mẫu lịch sử GPS bất biến từ API; measuredAt là lúc đo, receivedAt là lúc server nhận.
  // id/deviceId liên kết bản ghi; measuredAt quyết định thứ tự thật của hành trình.
  final String id;
  final String deviceId;
  final DateTime measuredAt;
  // latitude/longitude bắt buộc; altitudeM là cao độ mét nếu thiết bị hỗ trợ.
  final double latitude;
  final double longitude;
  final double? altitudeM;
  // speedMps và headingDeg mô tả chuyển động; accuracyM/satelliteCount đánh giá GPS.
  final double? speedMps;
  final double? headingDeg;
  final double? accuracyM;
  final int? satelliteCount;
  // source cho biết MQTT/REST; receivedAt/createdAt là thời điểm phía backend.
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
    // Ép số qua `num` để chấp nhận JSON integer/double mà không mất giá trị thập phân.
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
