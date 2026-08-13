import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

    // Speed
    String speedStr = '—';
    String speedUnit = '';
    if (device.currentSpeedMps != null && status.movement == MovementStatus.moving) {
      speedStr = (device.currentSpeedMps! * 3.6).toStringAsFixed(1);
      speedUnit = 'km/h';
    } else if (status.movement == MovementStatus.stopped && device.isOnline) {
      speedStr = '0';
      speedUnit = 'km/h';
    }

    // Last seen
    String lastSeenStr = '—';
    if (device.lastSeenAt != null) {
      final now = DateTime.now();
      final diff = now.difference(device.lastSeenAt!.toLocal());
      if (diff.inSeconds < 60) {
        lastSeenStr = 'Vừa xong';
      } else if (diff.inMinutes < 60) {
        lastSeenStr = '${diff.inMinutes} phút trước';
      } else if (diff.inHours < 24) {
        lastSeenStr = '${diff.inHours} giờ trước';
      } else {
        lastSeenStr = DateFormat('HH:mm dd/MM').format(device.lastSeenAt!.toLocal());
      }
    }

    // Location
    String locationStr = '';
    if (address != null && address!.isNotEmpty) {
      locationStr = address!;
    } else if (device.latitude != null && device.longitude != null) {
      locationStr =
          '${device.latitude!.toStringAsFixed(5)}, ${device.longitude!.toStringAsFixed(5)}';
    }

    final bool hasLocation = locationStr.isNotEmpty;
    final String displayName =
        device.name.isNotEmpty ? device.name : device.deviceCode;
    final String? subCode =
        device.name.isNotEmpty && device.name != device.deviceCode
            ? device.deviceCode
            : null;
    final String personName = device.currentPersonName ?? '';
    final bool hasPerson = personName.isNotEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        speedStr,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: status.movement == MovementStatus.moving
                              ? const Color(0xFF2563EB)
                              : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          height: 1,
                        ),
                      ),
                      if (speedUnit.isNotEmpty)
                        Text(
                          speedUnit,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // ── Row 2: Person + Last Seen ──
              Row(
                children: [
                  Expanded(
                    child: _MetaItem(
                      icon: Icons.person_rounded,
                      text: hasPerson ? personName : 'Chưa phân công',
                      faded: !hasPerson,
                    ),
                  ),
                  _MetaItem(
                    icon: Icons.access_time_rounded,
                    text: lastSeenStr,
                    faded: device.lastSeenAt == null,
                  ),
                ],
              ),

              // ── Row 3: Location (if available) ──
              if (hasLocation) ...[
                const SizedBox(height: 6),
                _MetaItem(
                  icon: Icons.location_on_rounded,
                  text: locationStr,
                  maxLines: 2,
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
    } else if (status.movement == MovementStatus.moving) {
      icon = Icons.navigation_rounded;
    } else if (status.connectivity == ConnectivityStatus.stale) {
      icon = Icons.signal_wifi_statusbar_connected_no_internet_4_rounded;
    } else {
      icon = Icons.pause_circle_rounded;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: status.color),
        const SizedBox(width: 3),
        Text(
          status.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: status.color,
          ),
        ),
      ],
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.icon,
    required this.text,
    this.faded = false,
    this.maxLines = 1,
  });

  final IconData icon;
  final String text;
  final bool faded;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = faded
        ? theme.colorScheme.outline.withValues(alpha: 0.6)
        : theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 13, color: color),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: faded ? FontWeight.normal : FontWeight.w500,
            ),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
