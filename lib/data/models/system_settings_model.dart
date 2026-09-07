// Ba ngưỡng vận hành dùng chung: ngoại tuyến, di chuyển và khoảng đứt quãng.
// copyWith hỗ trợ cập nhật bất biến khi WebSocket hoặc API trả cấu hình mới.
class SystemSettingsModel {
  // Ba ngưỡng vận hành dùng chung do backend lưu; default chỉ dùng trước lần tải đầu.
  const SystemSettingsModel({
    this.offlineTimeoutSeconds = 300,
    this.movementThresholdMps = 0.5,
    this.defaultGapThresholdSeconds = 300,
    this.dashboardUpdateIntervalMs = 500,
  });

  final int offlineTimeoutSeconds;
  final double movementThresholdMps;
  final int defaultGapThresholdSeconds;
  final int dashboardUpdateIntervalMs;

  factory SystemSettingsModel.fromJson(Map<String, dynamic> json) {
    // Tên khóa khớp schema FastAPI và giữ đơn vị giây/mét trên giây của domain.
    return SystemSettingsModel(
      offlineTimeoutSeconds: _intValue(json['offline_timeout_seconds']) ?? 300,
      movementThresholdMps: _doubleValue(json['movement_threshold_mps']) ?? 0.5,
      defaultGapThresholdSeconds:
          _intValue(json['default_gap_threshold_seconds']) ?? 300,
      dashboardUpdateIntervalMs:
          (_intValue(json['dashboard_update_interval_ms']) ?? 500).clamp(
            250,
            1000,
          ),
    );
  }

  Map<String, dynamic> toJson() => {
    // Payload PATCH chỉ chứa ba trường quản trị được phép thay đổi.
    'offline_timeout_seconds': offlineTimeoutSeconds,
    'movement_threshold_mps': movementThresholdMps,
    'default_gap_threshold_seconds': defaultGapThresholdSeconds,
    'dashboard_update_interval_ms': dashboardUpdateIntervalMs,
  };

  SystemSettingsModel copyWith({
    // Tạo snapshot mới cho state bất biến; không sửa object hiện tại tại chỗ.
    int? offlineTimeoutSeconds,
    double? movementThresholdMps,
    int? defaultGapThresholdSeconds,
    int? dashboardUpdateIntervalMs,
  }) {
    return SystemSettingsModel(
      offlineTimeoutSeconds:
          offlineTimeoutSeconds ?? this.offlineTimeoutSeconds,
      movementThresholdMps: movementThresholdMps ?? this.movementThresholdMps,
      defaultGapThresholdSeconds:
          defaultGapThresholdSeconds ?? this.defaultGapThresholdSeconds,
      dashboardUpdateIntervalMs:
          dashboardUpdateIntervalMs ?? this.dashboardUpdateIntervalMs,
    );
  }

  static int? _intValue(dynamic value) => switch (value) {
    int number => number,
    num number => number.toInt(),
    String text => int.tryParse(text),
    _ => null,
  };

  static double? _doubleValue(dynamic value) => switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text),
    _ => null,
  };
}
