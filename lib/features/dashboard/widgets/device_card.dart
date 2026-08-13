import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/device_icon.dart';
import '../../../data/models/device_model.dart';
import '../../../domain/entities/device_status_resolver.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    this.address,
    required this.onTap,
  });

  final DeviceModel device;
  final String? address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );

    final theme = Theme.of(context);
    
    String speedStr = '—';
    if (device.currentSpeedMps != null && status.movement == MovementStatus.moving) {
      speedStr = '${(device.currentSpeedMps! * 3.6).toStringAsFixed(1)} km/h';
    } else if (status.movement == MovementStatus.stopped) {
      speedStr = '0 km/h';
    }

    String batteryStr = '—';
    if (device.uavBatteryPct != null) {
      batteryStr = '${device.uavBatteryPct}%';
    } else if (device.controllerBatteryPct != null) {
      batteryStr = '${device.controllerBatteryPct}%';
    }

    String lastSeenStr = '—';
    if (device.lastSeenAt != null) {
      final now = DateTime.now();
      final diff = now.difference(device.lastSeenAt!);
      if (diff.inMinutes < 1) {
        lastSeenStr = 'Vừa xong';
      } else if (diff.inMinutes < 60) {
        lastSeenStr = '${diff.inMinutes} phút trước';
      } else if (diff.inHours < 24) {
        lastSeenStr = '${diff.inHours} giờ trước';
      } else {
        lastSeenStr = DateFormat('dd/MM HH:mm').format(device.lastSeenAt!);
      }
    }

    String locationStr = '—';
    if (address != null && address!.isNotEmpty) {
      locationStr = address!;
    } else if (device.latitude != null && device.longitude != null) {
      locationStr = '${device.latitude!.toStringAsFixed(5)}, ${device.longitude!.toStringAsFixed(5)}';
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: status.color.withValues(alpha: 0.3), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // Fix RenderFlex overflow
            children: [
              // Header row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: status.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      DeviceIcon.iconFor(device.deviceType),
                      color: status.color,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name.isNotEmpty ? device.name : device.deviceCode,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: status.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              status.label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: status.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Info grid
              _InfoRow(icon: Icons.person, label: 'Người dùng', value: device.currentPersonName ?? 'Chưa phân công'),
              const SizedBox(height: 8),
              _InfoRow(icon: Icons.location_on, label: 'Vị trí', value: locationStr),
              const SizedBox(height: 8),
              
              Row(
                children: [
                  Expanded(child: _InfoRow(icon: Icons.speed, label: 'Tốc độ', value: speedStr)),
                  Expanded(child: _InfoRow(icon: Icons.battery_charging_full, label: 'Pin', value: batteryStr)),
                ],
              ),
              
              // Remove Spacer to prevent overflow in GridView
              const Divider(height: 24),
              
              // Footer
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    'Cập nhật: $lastSeenStr',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.outline),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
