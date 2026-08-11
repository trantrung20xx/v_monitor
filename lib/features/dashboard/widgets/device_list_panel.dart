import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/device_icon.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/device_model.dart';

/// Side panel listing devices with status.
class DeviceListPanel extends StatelessWidget {
  const DeviceListPanel({super.key, required this.devices});

  final List<DeviceModel> devices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_other, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('Chưa có thiết bị', style: theme.textTheme.bodyLarge),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: devices.length,
      separatorBuilder: (context, index) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final device = devices[index];
        return _DeviceTile(device: device);
      },
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});
  final DeviceModel device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.pushNamed('device-detail', pathParameters: {'id': device.id}),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              DeviceIcon(
                deviceType: device.deviceType,
                isOnline: device.isOnline,
                isMoving: device.isMoving,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.deviceCode,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (device.name != device.deviceCode)
                      Text(
                        device.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              StatusBadge(
                label: device.statusLabel,
                isOnline: device.isOnline,
                isMoving: device.isMoving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
