import 'package:flutter/material.dart';

/// Returns an icon representing the device type.
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
    final theme = Theme.of(context);
    final color = isOnline
        ? (isMoving ? theme.colorScheme.primary : Colors.green)
        : Colors.grey;

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

  /// Get icon data without building a widget.
  static IconData iconFor(String type) => _iconForType(type);
}
