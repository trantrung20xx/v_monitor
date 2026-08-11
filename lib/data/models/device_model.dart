class DeviceModel {
  final String id;
  final String deviceCode;
  final String name;
  final String type;
  final String status;
  final int? controllerBatteryPct;
  final int? uavBatteryPct;
  final bool isOnline;
  final double? latitude;
  final double? longitude;
  final double? currentSpeedMps;
  final double? currentHeadingDeg;
  final DateTime? lastSeenAt;

  DeviceModel({
    required this.id,
    required this.deviceCode,
    required this.name,
    required this.type,
    required this.status,
    this.controllerBatteryPct,
    this.uavBatteryPct,
    this.isOnline = false,
    this.latitude,
    this.longitude,
    this.currentSpeedMps,
    this.currentHeadingDeg,
    this.lastSeenAt,
  });

  String get deviceType => type;
  bool get isMoving => (currentSpeedMps ?? 0) > 0.5;
  String get statusLabel {
    switch (status) {
      case 'ONLINE': return 'Trực tuyến';
      case 'OFFLINE': return 'Ngoại tuyến';
      case 'ACTIVE': return 'Đang hoạt động';
      default: return 'Không xác định';
    }
  }
  String? get currentPersonName => null; // To be implemented later from assignments

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] ?? '',
      deviceCode: json['device_code'] ?? '',
      name: json['name'] ?? '',
      type: json['device_type'] ?? 'OTHER',
      status: json['status'] ?? 'UNKNOWN',
      isOnline: json['is_online'] ?? false,
      controllerBatteryPct: json['controller_battery_pct'],
      uavBatteryPct: json['uav_battery_pct'],
      latitude: json['current_latitude'],
      longitude: json['current_longitude'],
      currentSpeedMps: json['current_speed_mps'],
      currentHeadingDeg: json['current_heading_deg'],
      lastSeenAt: json['last_seen_at'] != null ? DateTime.tryParse(json['last_seen_at']) : null,
    );
  }
}
