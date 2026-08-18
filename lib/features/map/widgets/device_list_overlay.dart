import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/device_formatters.dart';
import '../../../core/widgets/device_icon.dart';
import '../../../data/models/device_model.dart';
import '../../../domain/entities/device_query_filter.dart';
import '../../../domain/entities/device_status_resolver.dart';

/// Overlay danh sách thiết bị trên Bản đồ
/// Được thiết kế tối ưu, trực quan, đồng bộ style với toàn bộ hệ thống.
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

  static const Color _primaryBlue = Color(0xFF1677FF);
  static const Color _textMain = Color(0xFF0F172A);
  static const Color _textMuted = Color(0xFF64748B);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _bgSurface = Color(0xFFF8FAFC);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredDevices = DeviceQueryFilter.filter(
      widget.devices,
      query: _searchQuery,
      statusFilter: _statusFilter,
    );

    // Tính toán số lượng thống kê nhanh
    int onlineCount = 0;
    int movingCount = 0;
    int stoppedCount = 0;
    int staleCount = 0;
    int offlineCount = 0;

    for (final d in widget.devices) {
      final s = DeviceStatusResolver.resolve(
        isOnline: d.isOnline,
        lastSeenAt: d.lastSeenAt,
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
    final panelWidth = math.min(410.0, math.max(0.0, viewportWidth - 24));

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: panelWidth,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderColor),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // ─── Header: Tiêu đề + Thống kê + Nút đóng ───
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: _borderColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.devices_rounded,
                          size: 16,
                          color: _primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thiết bị trên bản đồ',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: _textMain,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _bgSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _borderColor),
                        ),
                        child: Text(
                          '${filteredDevices.length}/${widget.devices.length}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _textMain,
                          ),
                        ),
                      ),
                      if (widget.onClose != null) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: widget.onClose,
                          tooltip: 'Đóng danh sách',
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Thống kê nhanh theo nhãn
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildStatusMiniBadge('Chạy', movingCount, const Color(0xFF1677FF)),
                        const SizedBox(width: 6),
                        _buildStatusMiniBadge('Dừng', stoppedCount, const Color(0xFFD97706)),
                        const SizedBox(width: 6),
                        _buildStatusMiniBadge('Mất GPS', staleCount, const Color(0xFFDC2626)),
                        const SizedBox(width: 6),
                        _buildStatusMiniBadge('Ngoại tuyến', offlineCount, const Color(0xFF64748B)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ─── Search Box ───
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: _bgSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderColor),
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 10, right: 6),
                      child: Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: _textMuted,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: _textMain,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Tìm theo tên, mã thiết bị, loại...',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: _textMuted,
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
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
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: _textMuted,
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
            const Divider(height: 1, color: _borderColor),

            // ─── Danh sách thiết bị ───
            Expanded(
              child: filteredDevices.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _bgSurface,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.search_off_rounded,
                                size: 32,
                                color: _textMuted,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Không tìm thấy thiết bị phù hợp',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _textMain,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Thử thay đổi từ khóa hoặc bộ lọc trạng thái',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: _textMuted,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
      ),
    );
  }

  Widget _buildStatusMiniBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$label: $count',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: Row(
        children: _options.map((option) {
          final isSelected = selected == option.filter;
          final count = counts[option.filter] ?? 0;

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onChanged(option.filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF1677FF).withValues(alpha: 0.1)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF1677FF)
                        : const Color(0xFFE2E8F0),
                    width: isSelected ? 1.2 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? const Color(0xFF1677FF)
                            : const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '($count)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? const Color(0xFF1677FF)
                            : const Color(0xFF94A3B8),
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

/// Card hiển thị thông tin thiết bị tinh giản, hiện đại và tối ưu thông tin
class _DeviceMapCard extends StatelessWidget {
  const _DeviceMapCard({
    required this.device,
    this.address,
    required this.onTap,
  });

  final DeviceModel device;
  final String? address;
  final VoidCallback onTap;

  static const Color _textMain = Color(0xFF0F172A);
  static const Color _textMuted = Color(0xFF64748B);
  static const Color _borderColor = Color(0xFFE2E8F0);

  @override
  Widget build(BuildContext context) {
    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
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
      badgeColor = const Color(0xFF64748B);
      badgeText = 'Ngoại tuyến';
      badgeIcon = Icons.power_settings_new_rounded;
    } else if (isStale) {
      badgeColor = const Color(0xFFDC2626);
      badgeText = 'Mất GPS';
      badgeIcon = Icons.warning_amber_rounded;
    } else if (isMoving) {
      badgeColor = const Color(0xFF1677FF);
      final speedText = DeviceFormatters.speedKmh(
        device.currentSpeedMps,
        status: status,
      );
      badgeText = speedText;
      badgeIcon = Icons.navigation_rounded;
    } else if (isStopped) {
      badgeColor = const Color(0xFFD97706);
      badgeText = 'Đang dừng';
      badgeIcon = Icons.pause_circle_rounded;
    } else {
      badgeColor = const Color(0xFF16A34A);
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
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Hàng 1: Icon phương tiện + Tên/Mã + Badge trạng thái/Tốc độ ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(
                        DeviceIcon.iconFor(device.deviceType),
                        color: badgeColor,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _textMain,
                              height: 1.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            subIdentity,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: _textMuted,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: badgeColor.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            badgeIcon,
                            size: 11,
                            color: badgeColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            badgeText,
                            style: TextStyle(
                              color: badgeColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 7),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 6),

                // ── Hàng 2: Vị trí & Thời gian cập nhật + Nút chi tiết ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 13,
                      color: _textMuted,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        locationLine1,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _textMain,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isStale
                              ? Icons.warning_amber_rounded
                              : Icons.schedule_rounded,
                          size: 11.5,
                          color: isStale ? const Color(0xFFDC2626) : _textMuted,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          relativeTimeText,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: isStale ? FontWeight.w700 : FontWeight.w500,
                            color: isStale ? const Color(0xFFDC2626) : _textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    // Icon chuyển tới trang chi tiết
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => context.pushNamed(
                        'device-detail',
                        pathParameters: {'id': device.id},
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: _textMuted,
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
