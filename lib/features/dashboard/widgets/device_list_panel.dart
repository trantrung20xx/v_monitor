import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/device_model.dart';
import 'device_card.dart';

class DeviceGrid extends StatelessWidget {
  const DeviceGrid({
    super.key,
    required this.devices,
    required this.searchQuery,
    required this.deviceAddresses,
  });

  final List<DeviceModel> devices;
  final String searchQuery;
  final Map<String, String> deviceAddresses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Apply search filter
    final filteredDevices = devices.where((device) {
      if (searchQuery.isEmpty) return true;
      final q = searchQuery.toLowerCase();
      return device.name.toLowerCase().contains(q) ||
          device.deviceCode.toLowerCase().contains(q) ||
          (device.currentPersonName?.toLowerCase().contains(q) ?? false);
    }).toList();

    if (filteredDevices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searchQuery.isEmpty ? Icons.devices_other_rounded : Icons.search_off_rounded,
              size: 56,
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              searchQuery.isEmpty
                  ? 'Chưa có thiết bị nào'
                  : 'Không tìm thấy thiết bị phù hợp',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (searchQuery.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Kiểm tra kết nối backend và MQTT',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrow screen: single column list
        if (constraints.maxWidth < 480) {
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: filteredDevices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final device = filteredDevices[index];
              return DeviceCard(
                device: device,
                address: deviceAddresses[device.id],
                onTap: () => context.pushNamed(
                  'device-detail',
                  pathParameters: {'id': device.id},
                ),
              );
            },
          );
        }

        // Wide screen: responsive grid
        const maxCrossExtent = 380.0;
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxCrossExtent,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: _cardAspectRatio(constraints.maxWidth, maxCrossExtent),
          ),
          itemCount: filteredDevices.length,
          itemBuilder: (context, index) {
            final device = filteredDevices[index];
            return DeviceCard(
              device: device,
              address: deviceAddresses[device.id],
              onTap: () => context.pushNamed(
                'device-detail',
                pathParameters: {'id': device.id},
              ),
            );
          },
        );
      },
    );
  }

  /// Compute a reasonable aspect ratio based on available width.
  double _cardAspectRatio(double totalWidth, double maxExtent) {
    final cols = (totalWidth / maxExtent).ceil().clamp(1, 4);
    final cardW = (totalWidth - 32 - (cols - 1) * 12) / cols;
    // Card height ~200px is ideal; adjust ratio accordingly
    return cardW / 200;
  }
}
