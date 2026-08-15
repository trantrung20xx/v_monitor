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

    final theme = Theme.of(context);
    final isMoving = status.movement == MovementStatus.moving;

    // Speed
    final speedStr = DeviceFormatters.speedKmh(
      device.currentSpeedMps,
      status: status,
    );
    final speedUnit = isMoving || status.movement == MovementStatus.stopped
        ? 'km/h'
        : '';

    final relativeTimeStr = DeviceFormatters.relativeTime(device.lastSeenAt);
    final headingText = DeviceFormatters.headingText(
      device.currentHeadingDeg,
      status: status,
    );

    final (addressLine1, addressLine2) = DeviceFormatters.addressLines(
      address,
      latitude: device.latitude,
      longitude: device.longitude,
    );

    final String displayName = device.name.trim().isNotEmpty
        ? device.name.trim()
        : device.deviceCode.trim();
    final String? subCode =
        device.name.trim().isNotEmpty && device.name.trim() != device.deviceCode.trim()
        ? device.deviceCode.trim()
        : null;

    final speedColor = isMoving
        ? const Color(0xFF2563EB)
        : theme.colorScheme.onSurface;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Row 1: Icon + Name/Code + Status + Speed ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar + status dot
                  Stack(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: status.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          DeviceIcon.iconFor(device.deviceType),
                          color: status.color,
                          size: 24,
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
                  const SizedBox(width: 12),
                  // Name block
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subCode != null)
                          Text(
                            subCode,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        const SizedBox(height: 4),
                        // Status badge inline
                        _StatusChip(status: status),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Speed block (right-aligned)
                  _SpeedReadout(
                    value: speedStr.replaceAll(' km/h', ''),
                    unit: speedUnit,
                    color: speedColor,
                  ),
                ],
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // ── Row 2: Heading + Last Seen ──
              Row(
                children: [
                  Expanded(
                    child: _MetaItem(
                      icon: Icons.explore_outlined,
                      text: 'Hướng: $headingText',
                      faded: headingText == '--',
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MetaItem(
                    icon: status.freshness == DataFreshnessStatus.stale
                        ? Icons.warning_amber_rounded
                        : Icons.schedule_rounded,
                    text: relativeTimeStr,
                    faded: device.lastSeenAt == null,
                    color: status.freshness == DataFreshnessStatus.stale
                        ? const Color(0xFFDC2626)
                        : null,
                  ),
                ],
              ),

              // ── Row 3: Telemetry (Battery / Altitude if available) ──
              if (device.uavBatteryPct != null ||
                  device.controllerBatteryPct != null ||
                  device.currentAltitudeM != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (device.uavBatteryPct != null) ...[
                      _MetaItem(
                        icon: Icons.battery_charging_full_rounded,
                        text: 'Pin UAV: ${device.uavBatteryPct}%',
                        color: (device.uavBatteryPct! < 20)
                            ? const Color(0xFFDC2626)
                            : null,
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (device.currentAltitudeM != null) ...[
                      _MetaItem(
                        icon: Icons.flight_takeoff_rounded,
                        text: 'Độ cao: ${device.currentAltitudeM!.toStringAsFixed(1)}m',
                      ),
                    ],
                  ],
                ),
              ],

              // ── Row 4: Address ──
              const SizedBox(height: 6),
              _MetaItem(
                icon: Icons.location_on_outlined,
                text: addressLine1,
                maxLines: 1,
              ),
              if (addressLine2.isNotEmpty) ...[
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(left: 17),
                  child: Text(
                    addressLine2,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final ResolvedDeviceStatus status;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    if (status.connectivity == ConnectivityStatus.offline) {
      icon = Icons.wifi_off_rounded;
    } else if (status.freshness == DataFreshnessStatus.stale) {
      icon = Icons.signal_wifi_statusbar_connected_no_internet_4_rounded;
    } else if (status.movement == MovementStatus.moving) {
      icon = Icons.navigation_rounded;
    } else {
      icon = Icons.pause_circle_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: status.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              status.label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: status.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedReadout extends StatelessWidget {
  const _SpeedReadout({
    required this.value,
    required this.unit,
    required this.color,
  });

  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48, maxWidth: 66),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            height: 28,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1,
                ),
              ),
            ),
          ),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.icon,
    required this.text,
    this.faded = false,
    this.maxLines = 1,
    this.color,
  });

  final IconData icon;
  final String text;
  final bool faded;
  final int maxLines;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor =
        color ??
        (faded
            ? theme.colorScheme.outline.withValues(alpha: 0.6)
            : theme.colorScheme.onSurfaceVariant);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 13, color: effectiveColor),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: effectiveColor,
              fontWeight: faded ? FontWeight.normal : FontWeight.w500,
              height: 1.16,
            ),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
