import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/device_icon.dart';
import '../../../domain/entities/device_status_resolver.dart';

/// Icon bản đồ giữ kích thước màn hình, độc lập với zoom và cỡ chữ.
abstract final class DeviceMapIcon {
  static const artworkSize = 40.0;
  static const touchSize = 48.0;
  static const carAsset = DeviceIcon.carAsset;
  static const uavAsset = DeviceIcon.uavAsset;

  static Color statusColor(ResolvedDeviceStatus status, AppThemeColors colors) {
    if (status.activity == ActivityStatus.inactive ||
        status.connectivity == ConnectivityStatus.offline) {
      return colors.offline;
    }
    if (status.freshness == DataFreshnessStatus.stale) return colors.danger;
    if (status.movement == MovementStatus.moving) return colors.primary;
    if (status.movement == MovementStatus.stopped) return colors.warning;
    return colors.success;
  }
}
