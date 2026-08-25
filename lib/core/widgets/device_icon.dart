// Biểu tượng thiết bị dùng chung, ánh xạ loại thiết bị sang icon và bề mặt theme.
import 'package:flutter/material.dart';

import '../theme/app_theme_colors.dart';

/// Trả biểu tượng tương ứng với loại thiết bị do backend cung cấp.
// Biểu tượng loại thiết bị dùng chung; deviceType từ API được ánh xạ sang Material icon.
class DeviceIcon extends StatelessWidget {
  const DeviceIcon({
    super.key,
    required this.deviceType,
    this.isOnline = false,
    this.isMoving = false,
    this.size = 24,
  });

  final String deviceType;
  final bool isOnline;
  final bool isMoving;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = isOnline
        ? (isMoving ? colors.primary : colors.success)
        : colors.offline;

    return Icon(_iconForType(deviceType), color: color, size: size);
  }

  static IconData _iconForType(String type) {
    switch (type.toUpperCase()) {
      case 'UAV_CONTROLLER':
        return Icons.gamepad_rounded;
      case 'VEHICLE':
        return Icons.directions_car_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  /// Trả IconData để marker hoặc widget khác tái sử dụng mà không cần dựng DeviceIcon.
  static IconData iconFor(String type) => _iconForType(type);
}
