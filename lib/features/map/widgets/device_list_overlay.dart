import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../data/models/device_model.dart';
import '../../../domain/entities/device_query_filter.dart';
import '../../../domain/entities/device_status_resolver.dart';
import '../../../core/widgets/device_icon.dart';
import 'package:intl/intl.dart';

class DeviceListOverlay extends StatefulWidget {
  const DeviceListOverlay({
    super.key,
    required this.devices,
    required this.onDeviceSelected,
    this.onClose,
    this.scrollController,
  });

  final List<DeviceModel> devices;
  final void Function(DeviceModel) onDeviceSelected;
  final VoidCallback? onClose;
  final ScrollController? scrollController;

  @override
  State<DeviceListOverlay> createState() => _DeviceListOverlayState();
}

class _DeviceListOverlayState extends State<DeviceListOverlay> {
  String _searchQuery = '';
  DeviceFilter _statusFilter = DeviceFilter.all;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredDevices = DeviceQueryFilter.filter(
      widget.devices,
      query: _searchQuery,
      statusFilter: _statusFilter,
    );
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final panelWidth = math.min(420.0, math.max(0.0, viewportWidth - 24));

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: panelWidth,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
              color: theme.colorScheme.surface,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Thiết bị trên bản đồ',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${filteredDevices.length}/${widget.devices.length} thiết bị hiển thị',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onClose != null)
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: widget.onClose,
                      tooltip: 'Đóng danh sách',
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Tìm thiết bị, mã, người phụ trách...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          tooltip: 'Xóa tìm kiếm',
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            });
                          },
                        ),
                  isDense: true,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
            _OverlayFilterBar(
              selected: _statusFilter,
              onChanged: (filter) {
                setState(() {
                  _statusFilter = filter;
                });
              },
            ),
            const Divider(height: 1),
            // List
            Expanded(
              child: Builder(
                builder: (context) {
                  if (filteredDevices.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 40,
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Không tìm thấy thiết bị phù hợp',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    controller: widget.scrollController,
                    padding: EdgeInsets.zero,
                    itemCount: filteredDevices.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final device = filteredDevices[index];
                      return _DeviceListItem(
                        device: device,
                        onTap: () => widget.onDeviceSelected(device),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayFilterBar extends StatelessWidget {
  const _OverlayFilterBar({required this.selected, required this.onChanged});

  final DeviceFilter selected;
  final ValueChanged<DeviceFilter> onChanged;

  static const _options = [
    _FilterOption(DeviceFilter.all, 'Tất cả'),
    _FilterOption(DeviceFilter.online, 'Trực tuyến'),
    _FilterOption(DeviceFilter.offline, 'Ngoại tuyến'),
    _FilterOption(DeviceFilter.moving, 'Di chuyển'),
    _FilterOption(DeviceFilter.stopped, 'Đang dừng'),
    _FilterOption(DeviceFilter.stale, 'Mất tín hiệu'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: _options.map((option) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(option.label),
              selected: selected == option.filter,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onChanged(option.filter),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FilterOption {
  const _FilterOption(this.filter, this.label);

  final DeviceFilter filter;
  final String label;
}

class _DeviceListItem extends StatelessWidget {
  const _DeviceListItem({required this.device, required this.onTap});

  final DeviceModel device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );

    var speedText = '--';
    var speedUnit = '';
    if (status.movement == MovementStatus.moving &&
        device.currentSpeedMps != null) {
      speedText = (device.currentSpeedMps! * 3.6).toStringAsFixed(1);
      speedUnit = 'km/h';
    } else if (status.movement == MovementStatus.stopped) {
      speedText = '0';
      speedUnit = 'km/h';
    }

    final displayName = device.name.isNotEmpty
        ? device.name
        : device.deviceCode;

    final lastSeenText = device.lastSeenAt != null
        ? DateFormat('HH:mm dd/MM').format(device.lastSeenAt!.toLocal())
        : 'Không xác định';

    final personName =
        (device.currentPersonName != null &&
            device.currentPersonName!.isNotEmpty)
        ? device.currentPersonName!
        : 'Chưa giao thiết bị';
    final needsAssignment =
        status.movement == MovementStatus.moving &&
        (device.currentPersonName?.trim().isNotEmpty ?? false) == false;
    final speedColor = status.movement == MovementStatus.moving
        ? const Color(0xFF2563EB)
        : theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar & Status Badge
            Stack(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    DeviceIcon.iconFor(device.deviceType),
                    color: status.color,
                    size: 22,
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: status.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            // Identity & Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  _OverlayStatusChip(status: status),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        needsAssignment
                            ? Icons.warning_amber_rounded
                            : Icons.person_rounded,
                        size: 14,
                        color: needsAssignment
                            ? const Color(0xFFEA580C)
                            : theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          personName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: needsAssignment
                                ? const Color(0xFFEA580C)
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          lastSeenText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Speed
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 52,
                  height: 26,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      speedText,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: speedColor,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                if (speedUnit.isNotEmpty)
                  Text(
                    speedUnit,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.w600,
                      height: 0.8,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayStatusChip extends StatelessWidget {
  const _OverlayStatusChip({required this.status});

  final ResolvedDeviceStatus status;

  @override
  Widget build(BuildContext context) {
    final icon = status.connectivity == ConnectivityStatus.offline
        ? Icons.wifi_off_rounded
        : status.freshness == DataFreshnessStatus.stale
        ? Icons.signal_wifi_statusbar_connected_no_internet_4_rounded
        : status.movement == MovementStatus.moving
        ? Icons.navigation_rounded
        : Icons.pause_circle_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: status.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              status.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: status.color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
