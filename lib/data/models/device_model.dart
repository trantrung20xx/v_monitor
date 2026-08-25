// Mô hình thiết bị hợp nhất hồ sơ quản lý với latest state từ backend.
// Giá trị nullable có nghĩa backend chưa nhận phép đo tương ứng, không phải số 0.
class DeviceModel {
  // Một object kết hợp hồ sơ `devices` với `device_latest_state` do backend trả phẳng.
  // Trường null biểu diễn chưa có telemetry tương ứng, không được tự đổi thành 0.
  // id là UUID database; deviceCode là mã dùng trên topic MQTT; name là tên hiển thị.
  final String id;
  final String deviceCode;
  final String name;
  // type phân loại phần cứng; status là trạng thái quản lý gốc; isEnabled là quyền nhận gói.
  final String type;
  final String status;
  final bool isEnabled;
  // Thông tin phần cứng tùy chọn phục vụ kiểm kê, không tham gia tính online/offline.
  final String? serialNumber;
  final String? manufacturer;
  final String? model;
  final String? firmwareVersion;
  // metadataJson chứa thuộc tính mở rộng; createdAt/updatedAt là thời gian hồ sơ thay đổi.
  final Map<String, dynamic>? metadataJson;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  // isOnline và current* lấy từ DeviceLatestState, không lấy từ status quản lý.
  final bool isOnline;
  final double? latitude;
  final double? longitude;
  final double? currentAltitudeM;
  final double? currentSpeedMps;
  final double? currentHeadingDeg;

  /// Phần trăm pin của chính thiết bị; null khi thiết bị chưa gửi dữ liệu pin.
  final int? batteryPct;
  // lastSeenAt là lần backend nhận gói; latestMeasuredAt là thời gian GPS được đo.
  final DateTime? lastSeenAt;
  final DateTime? latestMeasuredAt;

  DeviceModel({
    required this.id,
    required this.deviceCode,
    required this.name,
    required this.type,
    required this.status,
    this.isEnabled = true,
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
    // Nhãn này chỉ phản ánh status hồ sơ; trạng thái realtime dùng DeviceStatusResolver.
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

  // Chuyển JSON linh hoạt vì số từ HTTP có thể là int, double hoặc chuỗi.
  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    // Parse cả tên trường backend hiện tại và alias tương thích cũ; DateTime luôn
    // được giữ kèm timezone để resolver có thể chuyển local chính xác.
    final metadata = json['metadata_json'];
    return DeviceModel(
      id: json['id'] ?? '',
      deviceCode: json['device_code'] ?? '',
      name: json['name'] ?? '',
      type: json['device_type'] ?? 'OTHER',
      status: json['status'] ?? 'UNKNOWN',
      isEnabled: json['is_enabled'] ?? true,
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
