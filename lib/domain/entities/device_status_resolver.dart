// Nguồn sự thật duy nhất để suy luận kết nối, độ mới GPS, chuyển động và hoạt động.
// Resolver chỉ dùng dữ liệu thật cùng ngưỡng runtime; UI không tự đoán trạng thái.
import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';

// Bốn trục độc lập để UI không trộn quyền hoạt động, kết nối, độ mới GPS và
// chuyển động thành một boolean hoặc nhãn mơ hồ.
enum ConnectivityStatus { online, offline }

enum DataFreshnessStatus { fresh, stale, unknown }

enum MovementStatus { moving, stopped, unknown }

enum ActivityStatus { active, inactive, unknown }

// Kết quả bất biến dùng chung cho dashboard, bản đồ, chi tiết và quản lý thiết bị.
class ResolvedDeviceStatus {
  const ResolvedDeviceStatus({
    required this.connectivity,
    required this.freshness,
    required this.movement,
    required this.activity,
    required this.label,
    required this.color,
  });

  final ConnectivityStatus connectivity;
  final DataFreshnessStatus freshness;
  final MovementStatus movement;
  final ActivityStatus activity;
  final String label;
  final Color color;
}

// Bộ ngưỡng có thể inject trong test hoặc cập nhật từ SystemSettingsModel lúc chạy.
class DeviceStateThresholds {
  const DeviceStateThresholds({
    this.onlineTimeout = const Duration(minutes: 5),
    this.gpsStaleTimeout = const Duration(minutes: 2),
    this.movementSpeedThresholdMps = 0.5,
  });

  final Duration onlineTimeout;
  final Duration gpsStaleTimeout;
  final double movementSpeedThresholdMps;
}

class DeviceStatusResolver {
  // Fallback dùng trước khi tải server; runtimeThresholds được SettingsCubit cập
  // nhật và reset khi đăng xuất để không rò cấu hình giữa hai tài khoản.
  static const DeviceStateThresholds _fallbackThresholds =
      DeviceStateThresholds();
  static DeviceStateThresholds _runtimeThresholds = _fallbackThresholds;

  static DeviceStateThresholds get defaultThresholds => _runtimeThresholds;

  static double get movingThresholdMps =>
      defaultThresholds.movementSpeedThresholdMps;

  static void configureRuntime({
    required Duration onlineTimeout,
    required double movementSpeedThresholdMps,
  }) {
    // Chỉ hai ngưỡng có nguồn từ backend được thay; gpsStaleTimeout giữ chính sách client.
    _runtimeThresholds = DeviceStateThresholds(
      onlineTimeout: onlineTimeout,
      gpsStaleTimeout: _runtimeThresholds.gpsStaleTimeout,
      movementSpeedThresholdMps: movementSpeedThresholdMps,
    );
  }

  static void resetRuntime() {
    _runtimeThresholds = _fallbackThresholds;
  }

  static ResolvedDeviceStatus resolve({
    required bool isOnline,
    required DateTime? lastSeenAt,
    DateTime? latestMeasuredAt,
    required double? currentSpeedMps,
    required String baseStatus,
    DeviceStateThresholds? thresholds,
  }) {
    // Bước 1 tính tuổi kết nối theo lastSeenAt và tuổi GPS theo measuredAt.
    final activeThresholds = thresholds ?? defaultThresholds;
    final now = DateTime.now();
    final connectionAge = lastSeenAt == null
        ? null
        : now.difference(lastSeenAt.toLocal());
    // Khi backend cũ chưa trả trường mới, dùng lastSeenAt để giữ tương thích.
    final gpsTimestamp = latestMeasuredAt ?? lastSeenAt;
    final gpsAge = gpsTimestamp == null
        ? null
        : now.difference(gpsTimestamp.toLocal());

    // Không timestamp tạo unknown; dữ liệu quá ngưỡng tạo stale.
    final freshness = gpsAge == null
        ? DataFreshnessStatus.unknown
        : gpsAge > activeThresholds.gpsStaleTimeout
        ? DataFreshnessStatus.stale
        : DataFreshnessStatus.fresh;

    // isOnline từ backend phải đồng thời có lastSeen đủ mới; cách kiểm tra kép
    // ngăn UI giữ online khi tác vụ presence chưa kịp quét.
    final hasRecentConnection =
        connectionAge != null &&
        connectionAge <= activeThresholds.onlineTimeout;
    final connectivity = isOnline && hasRecentConnection
        ? ConnectivityStatus.online
        : ConnectivityStatus.offline;

    // Chỉ kết luận moving/stopped khi online, GPS còn mới và có tốc độ thật.
    var movement = MovementStatus.unknown;
    if (connectivity == ConnectivityStatus.online &&
        freshness == DataFreshnessStatus.fresh &&
        currentSpeedMps != null) {
      movement = currentSpeedMps > activeThresholds.movementSpeedThresholdMps
          ? MovementStatus.moving
          : MovementStatus.stopped;
    }

    // Activity lấy từ status hồ sơ, không suy ra từ telemetry.
    var activity = ActivityStatus.unknown;
    if (baseStatus == 'ACTIVE') {
      activity = ActivityStatus.active;
    } else if (baseStatus == 'INACTIVE') {
      activity = ActivityStatus.inactive;
    }

    var label = 'Không xác định';
    Color color = AppPalette.materialGrey;

    // Ưu tiên nhãn theo mức dễ hành động: offline → GPS stale → moving/stopped
    // → online. INACTIVE nghiệp vụ ghi đè ở bước cuối.
    if (connectivity == ConnectivityStatus.offline) {
      label = 'Ngoại tuyến';
      color = AppPalette.materialGrey;
    } else if (freshness == DataFreshnessStatus.stale) {
      label = 'Mất tín hiệu GPS';
      color = AppPalette.materialRedAccent;
    } else if (movement == MovementStatus.moving) {
      label = 'Đang di chuyển';
      color = AppPalette.materialBlue;
    } else if (movement == MovementStatus.stopped) {
      label = 'Đang dừng';
      color = AppPalette.materialOrange;
    } else if (connectivity == ConnectivityStatus.online) {
      label = 'Trực tuyến';
      color = AppPalette.materialGreen;
    }

    if (activity == ActivityStatus.inactive) {
      label = 'Không hoạt động';
      color = AppPalette.materialGrey600;
    }

    return ResolvedDeviceStatus(
      connectivity: connectivity,
      freshness: freshness,
      movement: movement,
      activity: activity,
      label: label,
      color: color,
    );
  }
}
