class DeviceModel {
  final String id;
  final String deviceCode;
  final String name;
  final String type;
  final String status;
  final String? serialNumber;
  final String? manufacturer;
  final String? model;
  final String? firmwareVersion;
  final Map<String, dynamic>? metadataJson;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isOnline;
  final double? latitude;
  final double? longitude;
  final double? currentAltitudeM;
  final double? currentSpeedMps;
  final double? currentHeadingDeg;

  /// Phần trăm pin của chính thiết bị; null khi thiết bị chưa gửi dữ liệu pin.
  final int? batteryPct;
  final DateTime? lastSeenAt;
  final DateTime? latestMeasuredAt;

  DeviceModel({
    required this.id,
    required this.deviceCode,
    required this.name,
    required this.type,
    required this.status,
    this.serialNumber,
    this.manufacturer,
    this.model,
    this.firmwareVersion,
    this.metadataJson,
    this.createdAt,
    this.updatedAt,
    this.isOnline = false,
    this.latitude,
    this.longitude,
    this.currentAltitudeM,
    this.currentSpeedMps,
    this.currentHeadingDeg,
    this.batteryPct,
    this.lastSeenAt,
    this.latestMeasuredAt,
  });

  String get deviceType => type;

  @Deprecated(
    'Use DeviceStatusResolver.resolve(...) to account for offline and stale GPS.',
  )
  String get statusLabel {
    switch (status) {
      case 'ONLINE':
        return 'Trực tuyến';
      case 'OFFLINE':
        return 'Ngoại tuyến';
      case 'ACTIVE':
        return 'Đang hoạt động';
      default:
        return 'Không xác định';
    }
  }

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata_json'];
    return DeviceModel(
      id: json['id'] ?? '',
      deviceCode: json['device_code'] ?? '',
      name: json['name'] ?? '',
      type: json['device_type'] ?? 'OTHER',
      status: json['status'] ?? 'UNKNOWN',
      serialNumber: _stringOrNull(json['serial_number']),
      manufacturer: _stringOrNull(json['manufacturer']),
      model: _stringOrNull(json['model']),
      firmwareVersion: _stringOrNull(json['firmware_version']),
      metadataJson: metadata is Map
          ? Map<String, dynamic>.from(metadata)
          : null,
      createdAt: _dateOrNull(json['created_at']),
      updatedAt: _dateOrNull(json['updated_at']),
      isOnline: json['is_online'] ?? false,
      latitude: _doubleOrNull(json['current_latitude']),
      longitude: _doubleOrNull(json['current_longitude']),
      currentAltitudeM: _doubleOrNull(json['current_altitude_m']),
      currentSpeedMps: _doubleOrNull(json['current_speed_mps']),
      currentHeadingDeg: _doubleOrNull(json['current_heading_deg']),
      batteryPct: _intOrNull(json['battery_pct']),
      lastSeenAt: _dateOrNull(json['last_seen_at']),
      latestMeasuredAt: _dateOrNull(json['latest_measured_at']),
    );
  }

  static String? _stringOrNull(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
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

  static DateTime? _dateOrNull(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
