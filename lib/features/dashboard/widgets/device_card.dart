import 'package:flutter/material.dart';

import '../../../core/utils/device_formatters.dart';
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

    // Speed format
    final speedStr = DeviceFormatters.speedKmh(
      device.currentSpeedMps,
      status: status,
    );

    final relativeTimeStr = DeviceFormatters.relativeTime(device.lastSeenAt);
    final headingText = DeviceFormatters.headingText(
      device.currentHeadingDeg,
      status: status,
    );
    final fullLocation = DeviceFormatters.location(device, address);

    final String displayName = device.name.trim().isNotEmpty
        ? device.name.trim()
        : device.deviceCode.trim();
    final String? subCode =
        device.name.trim().isNotEmpty &&
            device.name.trim() != device.deviceCode.trim()
        ? device.deviceCode.trim()
        : (device.name.trim().isEmpty ? null : device.deviceCode.trim());

    // Device icon color & bg
    final (typeColor, typeBgColor) = _deviceTypeColors(device.deviceType);

    // Connection metric details
    final (connIcon, connColor, connLabel) = _connectionStatusDetails(status);

    final isStale = status.freshness == DataFreshnessStatus.stale;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E9ED), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
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
                    // Device Icon Container
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
                    // Device Name and Code
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF18212A),
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subCode != null && subCode.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              subCode,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF66727D),
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
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              size: 12,
                              color: Color(0xFF2563EB),
                            ),
                            SizedBox(width: 2),
                            Text(
                              'Tốc độ',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF66727D),
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
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF18212A),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 2),
                    // Overflow menu
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          size: 16,
                          color: Color(0xFF66727D),
                        ),
                        padding: EdgeInsets.zero,
                        splashRadius: 14,
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'detail',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 16,
                                  color: Color(0xFF66727D),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Chi tiết thiết bị',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ],
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
                const Divider(height: 1, color: Color(0xFFE8ECEF)),
                const SizedBox(height: 6),

                // ── METRICS ROW: Kết nối | Cập nhật | Hướng ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Kết nối (flex 10)
                    Expanded(
                      flex: 10,
                      child: _MetricItem(
                        icon: connIcon,
                        iconColor: connColor,
                        label: 'Kết nối',
                        value: connLabel,
                        valueColor: connColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 2. Cập nhật (flex 11)
                    Expanded(
                      flex: 11,
                      child: _MetricItem(
                        icon: isStale
                            ? Icons.warning_amber_rounded
                            : Icons.schedule_rounded,
                        iconColor: isStale
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF66727D),
                        label: 'Cập nhật',
                        value: relativeTimeStr,
                        valueColor: isStale
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF18212A),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 3. Hướng (flex 9)
                    Expanded(
                      flex: 9,
                      child: _MetricItem(
                        icon: Icons.explore_outlined,
                        iconColor: const Color(0xFF3976D9),
                        label: 'Hướng',
                        value: headingText,
                        valueColor: const Color(0xFF18212A),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),
                const Divider(height: 1, color: Color(0xFFE8ECEF)),
                const SizedBox(height: 6),

                // ── LOCATION BLOCK: Vị trí & địa chỉ ──
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 13,
                      color: Color(0xFFD95656),
                    ),
                    SizedBox(width: 3),
                    Text(
                      'Vị trí',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF66727D),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  fullLocation,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF18212A),
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

  static (Color, Color) _deviceTypeColors(String type) {
    switch (type.toUpperCase()) {
      case 'UAV_CONTROLLER':
        return (
          const Color(0xFF1677FF),
          const Color(0xFF1677FF).withValues(alpha: 0.1),
        );
      case 'VEHICLE':
        return (
          const Color(0xFF1677FF),
          const Color(0xFF1677FF).withValues(alpha: 0.1),
        );
      default:
        return (
          const Color(0xFF66727D),
          const Color(0xFF66727D).withValues(alpha: 0.1),
        );
    }
  }

  static (IconData, Color, String) _connectionStatusDetails(
    ResolvedDeviceStatus status,
  ) {
    if (status.connectivity == ConnectivityStatus.offline) {
      return (Icons.wifi_off_rounded, const Color(0xFF8B949E), 'Ngoại tuyến');
    }
    if (status.freshness == DataFreshnessStatus.stale) {
      return (
        Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
        const Color(0xFFDC2626),
        'Mất tín hiệu GPS',
      );
    }
    return (Icons.wifi_rounded, const Color(0xFF16A34A), 'Trực tuyến');
  }
}

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
            Icon(icon, size: 13, color: iconColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF66727D),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: valueColor,
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
