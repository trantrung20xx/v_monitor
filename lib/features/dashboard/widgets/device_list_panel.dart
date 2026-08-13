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
            Icon(Icons.search_off, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              searchQuery.isEmpty ? 'Chưa có thiết bị nào' : 'Không tìm thấy thiết bị phù hợp',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        mainAxisExtent: 280, // Fixed height for cards
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
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
  }
}

