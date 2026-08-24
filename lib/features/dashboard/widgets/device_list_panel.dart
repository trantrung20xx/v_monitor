import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../data/models/device_model.dart';
import '../../../domain/entities/device_query_filter.dart';
import 'device_card.dart';

class DeviceGrid extends StatelessWidget {
  const DeviceGrid({
    super.key,
    required this.devices,
    required this.searchQuery,
    required this.statusFilter,
    required this.deviceAddresses,
  });

  final List<DeviceModel> devices;
  final String searchQuery;
  final DeviceFilter statusFilter;
  final Map<String, String> deviceAddresses;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final filteredDevices = DeviceQueryFilter.filter(
      devices,
      query: searchQuery,
      statusFilter: statusFilter,
    );

    if (filteredDevices.isEmpty) {
      final isFiltered =
          searchQuery.isNotEmpty || statusFilter != DeviceFilter.all;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: appColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isFiltered
                      ? Icons.search_off_rounded
                      : Icons.devices_other_rounded,
                  size: 32,
                  color: appColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isFiltered
                    ? 'Không tìm thấy thiết bị phù hợp'
                    : 'Chưa có thiết bị nào',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: appColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isFiltered
                    ? 'Thử thay đổi bộ lọc hoặc từ khóa tìm kiếm'
                    : 'Kiểm tra kết nối backend và MQTT',
                style: TextStyle(fontSize: 13, color: appColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        // Danh sách một cột cho màn hình di động và khung nhìn hẹp.
        if (totalWidth < 600) {
          return ListView.separated(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            itemCount: filteredDevices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
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

        // Lưới đáp ứng nhiều cột, tối thiểu ba thẻ trên màn hình máy tính.
        final int columnCount;
        if (totalWidth >= 1200) {
          columnCount = 4;
        } else if (totalWidth >= 800) {
          columnCount = 3;
        } else if (totalWidth >= 520) {
          columnCount = 2;
        } else {
          columnCount = 1;
        }

        if (columnCount == 1) {
          return ListView.separated(
            padding: const EdgeInsets.only(top: 4, bottom: 20),
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

        return GridView.builder(
          padding: const EdgeInsets.only(top: 4, bottom: 20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 186,
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
}
