import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../data/models/device_model.dart';
import '../../../domain/entities/device_query_filter.dart';
import '../../../domain/entities/device_status_resolver.dart';
import '../../../core/utils/device_formatters.dart';
import '../../../core/widgets/device_icon.dart';

class DeviceListOverlay extends StatefulWidget {
  const DeviceListOverlay({
    super.key,
    required this.devices,
    this.addresses = const {},
    required this.onDeviceSelected,
    this.onClose,
    this.scrollController,
  });

  final List<DeviceModel> devices;
  final Map<String, String> addresses;
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
                  hintText: 'Tìm theo tên, mã thiết bị, loại...',
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

                  return ListView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: filteredDevices.length,
                    itemBuilder: (context, index) {
                      final device = filteredDevices[index];
                      return _DeviceMapCard(
                        device: device,
                        address: widget.addresses[device.id],
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

/// Card thiết bị hiển thị trong panel Bản đồ
/// Cung cấp phân cấp thị giác rõ ràng cho người vận hành nhận biết nhanh trong 2-3s:
/// 1. Định danh (Tên, Mã, Loại phương tiện)
/// 2. Trạng thái kết nối (Trực tuyến / Ngoại tuyến)
/// 3. Trạng thái di chuyển + GPS freshness (Đang di chuyển / Đang dừng / Không xác định · GPS mới / cũ)
/// 4. Metrics nổi bật (Tốc độ km/h, Hướng di chuyển)
/// 5. Vị trí hiện tại hoặc Vị trí gần nhất kèm thời gian cập nhật
class _DeviceMapCard extends StatelessWidget {
  const _DeviceMapCard({
    required this.device,
    this.address,
    required this.onTap,
  });

  final DeviceModel device;
  final String? address;
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

    final isOnline = status.connectivity == ConnectivityStatus.online;
    final isMoving = status.movement == MovementStatus.moving;
    final isStale = status.freshness == DataFreshnessStatus.stale;

    // 1. Định danh
    final displayName = device.name.trim().isNotEmpty
        ? device.name.trim()
        : device.deviceCode.trim();
    final typeLabel = DeviceFormatters.deviceTypeLabel(device.deviceType);
    final subIdentity = '${device.deviceCode} · $typeLabel';

    // 2. Connectivity
    final connectivityColor = isOnline
        ? const Color(0xFF16A34A)
        : Colors.grey.shade500;
    final connectivityLabel = isOnline ? 'Trực tuyến' : 'Ngoại tuyến';

    // 3. Movement state & GPS freshness
    final String movementBadgeText;
    final IconData movementBadgeIcon;
    final Color movementBadgeColor;

    if (!isOnline) {
      movementBadgeText = 'Trạng thái di chuyển không xác định';
      movementBadgeIcon = Icons.help_outline_rounded;
      movementBadgeColor = Colors.grey.shade600;
    } else if (isStale) {
      movementBadgeText = isMoving ? 'Đang di chuyển · GPS cũ' : 'Đang dừng · GPS cũ';
      movementBadgeIcon = Icons.warning_amber_rounded;
      movementBadgeColor = const Color(0xFFD97706);
    } else if (isMoving) {
      movementBadgeText = 'Đang di chuyển · GPS mới';
      movementBadgeIcon = Icons.near_me_rounded;
      movementBadgeColor = const Color(0xFF2563EB);
    } else {
      movementBadgeText = 'Đang dừng · GPS mới';
      movementBadgeIcon = Icons.pause_circle_rounded;
      movementBadgeColor = const Color(0xFF16A34A);
    }

    // 4. Speed & Heading
    final speedText = DeviceFormatters.speedKmh(
      device.currentSpeedMps,
      status: status,
    );
    final speedColor = isMoving
        ? const Color(0xFF2563EB)
        : theme.colorScheme.onSurface;

    final headingText = DeviceFormatters.headingText(
      device.currentHeadingDeg,
      status: status,
    );

    // 5. Thời gian cập nhật
    final relativeTimeText = DeviceFormatters.relativeTime(device.lastSeenAt);

    // 6. Vị trí
    final (locationLine1, locationLine2) = DeviceFormatters.addressLines(
      address,
      latitude: device.latitude,
      longitude: device.longitude,
    );
    final isLocationStaleOrOffline = !isOnline || isStale;
    final locationHeader = isLocationStaleOrOffline ? 'Vị trí gần nhất' : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ─── Header: Icon + Name + SubIdentity + Connectivity ───
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: status.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      DeviceIcon.iconFor(device.deviceType),
                      color: status.color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subIdentity,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                            height: 1.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Connectivity badge (top right)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: connectivityColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: connectivityColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: connectivityColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          connectivityLabel,
                          style: TextStyle(
                            color: connectivityColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // ─── Movement & GPS Freshness line ───
              Row(
                children: [
                  Icon(
                    movementBadgeIcon,
                    size: 13,
                    color: movementBadgeColor,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      movementBadgeText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: movementBadgeColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ─── Metrics Block: Speed & Heading ───
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Speed
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            speedText,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: speedColor,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tốc độ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 26,
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Heading
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headingText,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isOnline && device.currentHeadingDeg != null
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.outline,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Hướng',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ─── Location & Last Update ───
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.location_on_outlined,
                      size: 15,
                      color: isLocationStaleOrOffline
                          ? theme.colorScheme.outline
                          : const Color(0xFF1677FF),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (locationHeader != null) ...[
                          Text(
                            locationHeader,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 10.5,
                            ),
                          ),
                          const SizedBox(height: 1),
                        ],
                        Text(
                          locationLine1,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                            fontSize: 11.5,
                            height: 1.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (locationLine2.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            locationLine2,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              height: 1.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Last seen / update time
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isStale
                            ? Icons.warning_amber_rounded
                            : Icons.schedule_rounded,
                        size: 13,
                        color: isStale
                            ? const Color(0xFFDC2626)
                            : theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        relativeTimeText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isStale
                              ? const Color(0xFFDC2626)
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: isStale
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 11,
                        ),
                      ),
                    ],
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
