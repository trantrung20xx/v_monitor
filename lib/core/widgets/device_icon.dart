// Biểu tượng thiết bị dùng chung, ánh xạ loại thiết bị sang icon và bề mặt theme.
import 'package:flutter/material.dart';

import '../theme/app_theme_colors.dart';

/// Trả biểu tượng tương ứng với loại thiết bị do backend cung cấp.
// Ô tô và UAV dùng ảnh PNG chung với bản đồ; loại khác giữ biểu tượng thiết bị.
class DeviceIcon extends StatelessWidget {
  const DeviceIcon({
    super.key,
    required this.deviceType,
    this.isOnline = false,
    this.isMoving = false,
    this.size = 24,
    this.color,
  });

  final String deviceType;
  final bool isOnline;
  final bool isMoving;
  final double size;
  final Color? color;

  static const carAsset = 'assets/map_icons/car_top_render.png';
  static const uavAsset = 'assets/map_icons/uav_top_render.png';

  static String? assetFor(String type) => switch (type.trim().toUpperCase()) {
    'VEHICLE' => carAsset,
    'UAV_CONTROLLER' => uavAsset,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final resolvedColor =
        color ??
        (isOnline
            ? (isMoving ? colors.primary : colors.success)
            : colors.offline);

    final asset = assetFor(deviceType);
    if (asset != null) {
      return Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          cacheWidth: (size * 3).ceil(),
          color: resolvedColor,
          colorBlendMode: BlendMode.modulate,
          excludeFromSemantics: true,
        ),
      );
    }

    return Icon(_iconForType(deviceType), color: resolvedColor, size: size);
  }

  static IconData _iconForType(String type) {
    switch (type.trim().toUpperCase()) {
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
