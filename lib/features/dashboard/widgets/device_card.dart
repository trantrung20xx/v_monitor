// Thẻ thiết bị cho dashboard: hiển thị định danh, trạng thái đã resolve, vị trí,
// pin và hành động mở chi tiết; bố cục tự đổi theo chiều rộng để tránh overflow.
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/device_formatters.dart';
import '../../../core/widgets/app_menu.dart';
import '../../../core/widgets/device_icon.dart';
import '../../../data/models/device_model.dart';
import '../../../domain/entities/device_status_resolver.dart';

// Thẻ tóm tắt một DeviceModel: định danh, trạng thái đã resolve, vị trí, tốc độ,
// pin và địa chỉ đã geocode từ DashboardState; nhấn thẻ mở trang chi tiết.
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
    // Resolver kết hợp latest state thật với ngưỡng runtime. Địa chỉ được truyền từ
    // cache DashboardCubit; thiếu địa chỉ không làm mất tọa độ hoặc dữ liệu thiết bị.
    final appColors = context.appColors;
    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      latestMeasuredAt: device.latestMeasuredAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );

    // Speed format
    final speedStr = DeviceFormatters.speedForStatus(
      device.currentSpeedMps,
      status: status,
    );

    final relativeTimeStr = DeviceFormatters.relativeTime(device.lastSeenAt);
    final headingText = DeviceFormatters.headingText(
      device.currentHeadingDeg,
      status: status,
    );
    final fullLocation = DeviceFormatters.location(device, address);
    final batteryText = DeviceFormatters.batteryPct(device.batteryPct);

    final String displayName = device.name.trim().isNotEmpty
        ? device.name.trim()
        : device.deviceCode.trim();
    final String? subCode =
        device.name.trim().isNotEmpty &&
            device.name.trim() != device.deviceCode.trim()
        ? device.deviceCode.trim()
        : (device.name.trim().isEmpty ? null : device.deviceCode.trim());

    // Màu biểu tượng và nền lấy theo trạng thái đã resolve.
    final (typeColor, typeBgColor) = _deviceTypeColors(
      device.deviceType,
      appColors,
    );

    // Connection metric details
    final (connIcon, connColor, connLabel) = _connectionStatusDetails(
      status,
      appColors,
    );

    final isStale = status.freshness == DataFreshnessStatus.stale;

    return Container(
      decoration: BoxDecoration(
        color: appColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: appColors.borderSoft, width: 1),
        boxShadow: [
          BoxShadow(
            color: appColors.shadow.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: AppPalette.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── HEADER: Icon + Name/Code + Speed + Menu ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Khối biểu tượng nhận diện loại thiết bị.
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: typeBgColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        DeviceIcon.iconFor(device.deviceType),
                        color: typeColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Khối tên hiển thị và mã thiết bị.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: appColors.textPrimary,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subCode != null && subCode.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              subCode,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w400,
                                color: appColors.textSecondary,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Speed block
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              size: 12,
                              color: appColors.primary,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'Tốc độ',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: appColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            speedStr,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: appColors.textPrimary,
                            ),
                          ),
                        ),
                        if (device.batteryPct != null) ...[
                          const SizedBox(height: 2),
                          // Pin hiển thị tại thẻ danh sách là pin của chính thiết bị,
                          // không phụ thuộc thiết bị là ô tô hay tay điều khiển UAV.
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.battery_std_rounded,
                                size: 11,
                                color: appColors.success,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                batteryText,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: appColors.successStrong,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(width: 2),
                    // Overflow menu
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: PopupMenuButton<String>(
                        tooltip: 'Thao tác thiết bị',
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 16,
                          color: appColors.textSecondary,
                        ),
                        padding: EdgeInsets.zero,
                        splashRadius: 14,
                        constraints: const BoxConstraints(
                          minWidth: 188,
                          maxWidth: 224,
                        ),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'detail',
                            height: 42,
                            padding: EdgeInsets.zero,
                            child: AppMenuItem(
                              icon: Icons.info_outline_rounded,
                              label: 'Chi tiết thiết bị',
                            ),
                          ),
                        ],
                        onSelected: (value) {
                          if (value == 'detail') {
                            onTap();
                          }
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),
                Divider(height: 1, color: appColors.divider),
                const SizedBox(height: 6),

                // ── METRICS ROW: Kết nối | Cập nhật | Hướng ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Kết nối (flex 11)
                    Expanded(
                      flex: 11,
                      child: _MetricItem(
                        icon: connIcon,
                        iconColor: connColor,
                        label: 'Kết nối',
                        value: connLabel,
                        valueColor: connColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 2. Cập nhật (flex 10)
                    Expanded(
                      flex: 10,
                      child: _MetricItem(
                        icon: isStale
                            ? Icons.warning_amber_rounded
                            : Icons.schedule_rounded,
                        iconColor: isStale
                            ? appColors.danger
                            : appColors.textSecondary,
                        label: 'Cập nhật',
                        value: relativeTimeStr,
                        valueColor: isStale
                            ? appColors.danger
                            : appColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 3. Hướng (flex 9)
                    Expanded(
                      flex: 9,
                      child: _MetricItem(
                        icon: Icons.explore_outlined,
                        iconColor: appColors.primary,
                        label: 'Hướng',
                        value: headingText,
                        valueColor: appColors.textPrimary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),
                Divider(height: 1, color: appColors.divider),
                const SizedBox(height: 6),

                // ── LOCATION BLOCK: Vị trí & địa chỉ ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 13,
                      color: appColors.danger,
                    ),
                    SizedBox(width: 3),
                    Text(
                      'Vị trí',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: appColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  fullLocation,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: appColors.textPrimary,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static (Color, Color) _deviceTypeColors(String type, AppThemeColors colors) {
    switch (type.toUpperCase()) {
      case 'UAV_CONTROLLER':
        return (colors.primary, colors.primary.withValues(alpha: 0.1));
      case 'VEHICLE':
        return (colors.primary, colors.primary.withValues(alpha: 0.1));
      default:
        return (
          colors.textSecondary,
          colors.textSecondary.withValues(alpha: 0.1),
        );
    }
  }

  static (IconData, Color, String) _connectionStatusDetails(
    ResolvedDeviceStatus status,
    AppThemeColors colors,
  ) {
    if (status.connectivity == ConnectivityStatus.offline) {
      return (Icons.wifi_off_rounded, colors.offline, 'Ngoại tuyến');
    }
    if (status.freshness == DataFreshnessStatus.stale) {
      return (
        Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
        colors.danger,
        'Mất tín hiệu GPS',
      );
    }
    return (Icons.wifi_rounded, colors.success, 'Trực tuyến');
  }
}

// Một chỉ số nhỏ trong thẻ thiết bị; label/value được giới hạn dòng để giữ chiều cao ổn định.
class _MetricItem extends StatelessWidget {
  const _MetricItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12.5, color: iconColor),
            const SizedBox(width: 3.5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: context.appColors.textSecondary,
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor,
              height: 1.15,
            ),
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}
