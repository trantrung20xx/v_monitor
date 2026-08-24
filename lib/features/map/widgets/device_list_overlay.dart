import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/device_formatters.dart';
import '../../../core/widgets/device_icon.dart';
import '../../../data/models/device_model.dart';
import '../../../domain/entities/device_query_filter.dart';
import '../../../domain/entities/device_status_resolver.dart';

/// Overlay danh sách thiết bị trên Bản đồ
/// Được tối ưu cho cả Desktop (Floating Panel) và Mobile (Draggable Bottom Sheet).
class DeviceListOverlay extends StatefulWidget {
  const DeviceListOverlay({
    super.key,
    required this.devices,
    this.addresses = const {},
    required this.onDeviceSelected,
    this.onClose,
    this.scrollController,
    this.isMobileSheet = false,
  });

  final List<DeviceModel> devices;
  final Map<String, String> addresses;
  final void Function(DeviceModel) onDeviceSelected;
  final VoidCallback? onClose;
  final ScrollController? scrollController;
  final bool isMobileSheet;

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
    final appColors = context.appColors;
    final filteredDevices = DeviceQueryFilter.filter(
      widget.devices,
      query: _searchQuery,
      statusFilter: _statusFilter,
    );

    // Thống kê nhanh theo trạng thái
    int onlineCount = 0;
    int movingCount = 0;
    int stoppedCount = 0;
    int staleCount = 0;
    int offlineCount = 0;

    for (final d in widget.devices) {
      final s = DeviceStatusResolver.resolve(
        isOnline: d.isOnline,
        lastSeenAt: d.lastSeenAt,
        latestMeasuredAt: d.latestMeasuredAt,
        currentSpeedMps: d.currentSpeedMps,
        baseStatus: d.status,
      );
      if (s.connectivity == ConnectivityStatus.offline) {
        offlineCount++;
      } else {
        onlineCount++;
        if (s.freshness == DataFreshnessStatus.stale) {
          staleCount++;
        } else if (s.movement == MovementStatus.moving) {
          movingCount++;
        } else {
          stoppedCount++;
        }
      }
    }

    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isSheet = widget.isMobileSheet;
    final panelWidth = isSheet
        ? double.infinity
        : math.min(410.0, math.max(0.0, viewportWidth - 24));

    return Container(
      width: panelWidth,
      decoration: BoxDecoration(
        color: appColors.surface,
        borderRadius: isSheet
            ? const BorderRadius.vertical(top: Radius.circular(18))
            : BorderRadius.circular(14),
        border: isSheet ? null : Border.all(color: appColors.border),
        boxShadow: [
          BoxShadow(
            color: appColors.shadow.withValues(alpha: isSheet ? 0.08 : 0.12),
            blurRadius: isSheet ? 16 : 20,
            offset: isSheet ? const Offset(0, -3) : const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          // ─── Drag Handle (chỉ trên Mobile Sheet) ───
          if (isSheet) ...[
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: appColors.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],

          // ─── Header: Tiêu đề + Đếm số lượng + Nút đóng ───
          Container(
            padding: EdgeInsets.fromLTRB(12, isSheet ? 4 : 10, 8, 8),
            decoration: BoxDecoration(
              color: appColors.surface,
              border: Border(bottom: BorderSide(color: appColors.border)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: appColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.devices_rounded,
                    size: 15,
                    color: appColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Thiết bị trên bản đồ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: appColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: appColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: appColors.border),
                  ),
                  child: Text(
                    '${filteredDevices.length}/${widget.devices.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: appColors.textPrimary,
                    ),
                  ),
                ),
                if (widget.onClose != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: widget.onClose,
                    tooltip: 'Đóng danh sách',
                  ),
                ],
              ],
            ),
          ),

          // ─── Search Box tinh gọn ───
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: appColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: appColors.border),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 6),
                    child: Icon(
                      Icons.search_rounded,
                      size: 15,
                      color: appColors.textSecondary,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(
                        fontSize: 12,
                        color: appColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Tìm theo tên, mã, loại...',
                        hintStyle: TextStyle(
                          fontSize: 11.5,
                          color: appColors.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 7),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          _searchQuery = '';
                          _searchController.clear();
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: appColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ─── Filter Tabs Bar ───
          _OverlayFilterBar(
            selected: _statusFilter,
            counts: {
              DeviceFilter.all: widget.devices.length,
              DeviceFilter.online: onlineCount,
              DeviceFilter.offline: offlineCount,
              DeviceFilter.moving: movingCount,
              DeviceFilter.stopped: stoppedCount,
              DeviceFilter.stale: staleCount,
            },
            onChanged: (filter) {
              setState(() {
                _statusFilter = filter;
              });
            },
          ),
          Divider(height: 1, color: appColors.border),

          // ─── Danh sách thiết bị (Cuộn mượt mà) ───
          Expanded(
            child: filteredDevices.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: appColors.surfaceSubtle,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.search_off_rounded,
                              size: 28,
                              color: appColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Không tìm thấy thiết bị phù hợp',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: appColors.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Thử đổi từ khóa hoặc bộ lọc',
                            style: TextStyle(
                              fontSize: 11,
                              color: appColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    itemCount: filteredDevices.length,
                    itemBuilder: (context, index) {
                      final device = filteredDevices[index];
                      return _DeviceMapCard(
                        device: device,
                        address: widget.addresses[device.id],
                        onTap: () => widget.onDeviceSelected(device),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _OverlayFilterBar extends StatelessWidget {
  const _OverlayFilterBar({
    required this.selected,
    required this.counts,
    required this.onChanged,
  });

  final DeviceFilter selected;
  final Map<DeviceFilter, int> counts;
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
    final appColors = context.appColors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 6),
      child: Row(
        children: _options.map((option) {
          final isSelected = selected == option.filter;
          final count = counts[option.filter] ?? 0;

          return Padding(
            padding: const EdgeInsets.only(right: 5),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onChanged(option.filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? appColors.primary.withValues(alpha: 0.1)
                      : appColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? appColors.primary : appColors.border,
                    width: isSelected ? 1.2 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected
                            ? appColors.primary
                            : appColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '($count)',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? appColors.primary
                            : appColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
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

/// Card hiển thị thông tin thiết bị siêu tinh gọn, tối ưu không gian cho màn hình nhỏ
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
    final appColors = context.appColors;
    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      latestMeasuredAt: device.latestMeasuredAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );

    final isOnline = status.connectivity == ConnectivityStatus.online;
    final isMoving = status.movement == MovementStatus.moving;
    final isStopped = status.movement == MovementStatus.stopped;
    final isStale = status.freshness == DataFreshnessStatus.stale;

    // 1. Tên & mã thiết bị
    final displayName = device.name.trim().isNotEmpty
        ? device.name.trim()
        : device.deviceCode.trim();
    final typeLabel = DeviceFormatters.deviceTypeLabel(device.deviceType);
    final subIdentity = '${device.deviceCode} · $typeLabel';

    // 2. Badge trạng thái hoạt động & tốc độ
    final Color badgeColor;
    final String badgeText;
    final IconData badgeIcon;

    if (!isOnline) {
      badgeColor = appColors.offline;
      badgeText = 'Ngoại tuyến';
      badgeIcon = Icons.power_settings_new_rounded;
    } else if (isStale) {
      badgeColor = appColors.danger;
      badgeText = 'Mất GPS';
      badgeIcon = Icons.warning_amber_rounded;
    } else if (isMoving) {
      badgeColor = appColors.primary;
      final speedText = DeviceFormatters.speedForStatus(
        device.currentSpeedMps,
        status: status,
      );
      badgeText = speedText;
      badgeIcon = Icons.navigation_rounded;
    } else if (isStopped) {
      badgeColor = appColors.warning;
      badgeText = 'Đang dừng';
      badgeIcon = Icons.pause_circle_rounded;
    } else {
      badgeColor = appColors.success;
      badgeText = 'Trực tuyến';
      badgeIcon = Icons.check_circle_outline_rounded;
    }

    // 3. Thời gian cập nhật
    final relativeTimeText = DeviceFormatters.relativeTime(device.lastSeenAt);

    // 4. Địa chỉ
    final (locationLine1, _) = DeviceFormatters.addressLines(
      address,
      latitude: device.latitude,
      longitude: device.longitude,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: appColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appColors.border),
        boxShadow: [
          BoxShadow(
            color: appColors.shadow.withValues(alpha: 0.02),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: AppPalette.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Hàng 1: Icon phương tiện + Tên/Mã + Badge trạng thái/Tốc độ ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        DeviceIcon.iconFor(device.deviceType),
                        color: badgeColor,
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: appColors.textPrimary,
                              height: 1.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            subIdentity,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: appColors.textSecondary,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: badgeColor.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 10, color: badgeColor),
                          const SizedBox(width: 3),
                          Text(
                            badgeText,
                            style: TextStyle(
                              color: badgeColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 5),
                Divider(height: 1, color: appColors.surfaceMuted),
                const SizedBox(height: 4),

                // ── Hàng 2: Vị trí & Thời gian cập nhật + Nút chi tiết ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 11.5,
                      color: appColors.textSecondary,
                    ),
                    const SizedBox(width: 2.5),
                    Expanded(
                      child: Text(
                        locationLine1,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: appColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isStale
                              ? Icons.warning_amber_rounded
                              : Icons.schedule_rounded,
                          size: 10.5,
                          color: isStale
                              ? appColors.danger
                              : appColors.textSecondary,
                        ),
                        const SizedBox(width: 2.5),
                        Text(
                          relativeTimeText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isStale
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isStale
                                ? appColors.danger
                                : appColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 2),
                    // Icon chuyển tới trang chi tiết
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => context.pushNamed(
                        'device-detail',
                        pathParameters: {'id': device.id},
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(1.5),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 15,
                          color: appColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
