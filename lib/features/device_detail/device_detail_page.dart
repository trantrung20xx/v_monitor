import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/widgets/device_icon.dart';
import '../../core/utils/map_launcher_service.dart';
import '../../data/models/device_model.dart';
import '../../data/models/device_event_model.dart';
import '../../data/models/location_model.dart';
import '../../data/models/assignment_model.dart';
import '../../data/models/usage_session_model.dart';
import '../../domain/entities/device_status_resolver.dart';
import 'device_detail_cubit.dart';

import '../../data/repositories/device_repository.dart';
import '../../data/repositories/tracking_repository.dart';

/// Chi tiết thiết bị — 3 tabs: Tổng quan & Bản đồ / Lịch sử / Sự kiện.
class DeviceDetailPage extends StatelessWidget {
  const DeviceDetailPage({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        return DeviceDetailCubit(
          deviceId: deviceId,
          deviceRepo: context.read<DeviceRepository>(),
          trackingRepo: context.read<TrackingRepository>(),
        );
      },
      child: const _DeviceDetailView(),
    );
  }
}

class _DeviceDetailView extends StatelessWidget {
  const _DeviceDetailView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DeviceDetailCubit, DeviceDetailState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state.error != null || state.device == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Text(state.error ?? 'Không tìm thấy thiết bị'),
            ),
          );
        }

        final device = state.device!;

        final status = DeviceStatusResolver.resolve(
          isOnline: device.isOnline,
          lastSeenAt: device.lastSeenAt,
          currentSpeedMps: device.currentSpeedMps,
          baseStatus: device.status,
        );

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: Row(
                children: [
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.all(7),
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
                          device.name.isNotEmpty ? device.name : device.deviceCode,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (device.name.isNotEmpty && device.name != device.deviceCode)
                          Text(
                            device.deviceCode,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                              height: 1,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              bottom: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Tổng quan & Bản đồ'),
                  Tab(text: 'Lịch sử sử dụng'),
                  Tab(text: 'Sự kiện hệ thống'),
                ],
              ),
              actions: [
                _ShareLocationMenu(device: device),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => context.read<DeviceDetailCubit>().load(),
                  tooltip: 'Tải lại',
                ),
              ],
            ),
            body: TabBarView(
              children: [
                _OverviewTab(device: device, locations: state.locations, address: state.address),
                _UsageHistoryTab(usages: state.usages, assignments: state.assignments),
                _EventsTab(events: state.events),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Tab 1: Overview + Map ────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.device, required this.locations, this.address});
  final DeviceModel device;
  final List<LocationModel> locations;
  final String? address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Map
          SizedBox(
            height: 280,
            child: _MapWidget(device: device, locations: locations),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Card: Current Status ───────────────────────────────────
                _SectionCard(
                  title: 'Trạng thái hiện tại',
                  icon: Icons.radar_rounded,
                  iconColor: status.color,
                  children: [
                    _InfoRow(label: 'Trạng thái', value: status.label, valueColor: status.color),
                    if (device.currentSpeedMps != null)
                      _InfoRow(
                        label: 'Tốc độ',
                        value: '${(device.currentSpeedMps! * 3.6).toStringAsFixed(1)} km/h',
                      ),
                    if (device.currentHeadingDeg != null)
                      _InfoRow(
                        label: 'Hướng',
                        value: '${device.currentHeadingDeg!.toStringAsFixed(0)}°',
                      ),
                    if (device.lastSeenAt != null)
                      _InfoRow(
                        label: 'Cập nhật lúc',
                        value: _formatTime(device.lastSeenAt!),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Card: Location ─────────────────────────────────────────
                if (device.latitude != null && device.longitude != null)
                  _SectionCard(
                    title: 'Vị trí GPS',
                    icon: Icons.location_on_rounded,
                    iconColor: const Color(0xFF16A34A),
                    children: [
                      _InfoRow(
                        label: 'Kinh độ',
                        value: device.longitude!.toStringAsFixed(6),
                      ),
                      _InfoRow(
                        label: 'Vĩ độ',
                        value: device.latitude!.toStringAsFixed(6),
                      ),
                      if (address != null && address!.isNotEmpty)
                        _InfoRow(label: 'Địa điểm', value: address!),
                    ],
                  ),
                const SizedBox(height: 12),

                // ── Card: Device Info ──────────────────────────────────────
                _SectionCard(
                  title: 'Thông tin thiết bị',
                  icon: Icons.devices_rounded,
                  iconColor: theme.colorScheme.primary,
                  children: [
                    _InfoRow(label: 'Mã thiết bị', value: device.deviceCode),
                    if (device.name.isNotEmpty)
                      _InfoRow(label: 'Tên', value: device.name),
                    _InfoRow(label: 'Loại thiết bị', value: _deviceTypeLabel(device.deviceType)),
                    if (device.currentPersonName != null)
                      _InfoRow(
                        label: 'Người phụ trách',
                        value: device.currentPersonName!,
                        icon: Icons.person_rounded,
                      ),
                    if (device.uavBatteryPct != null)
                      _InfoRow(
                        label: 'Pin UAV',
                        value: '${device.uavBatteryPct}%',
                        icon: Icons.battery_charging_full_rounded,
                      ),
                    if (device.controllerBatteryPct != null)
                      _InfoRow(
                        label: 'Pin điều khiển',
                        value: '${device.controllerBatteryPct}%',
                        icon: Icons.battery_full_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _deviceTypeLabel(String type) {
    switch (type) {
      case 'UAV_CONTROLLER':
        return 'Điều khiển UAV';
      case 'VEHICLE':
        return 'Xe';
      default:
        return 'Khác';
    }
  }

  String _formatTime(DateTime dt) {
    try {
      return DateFormat('HH:mm:ss dd/MM/yyyy').format(dt.toLocal());
    } catch (_) {
      return dt.toString();
    }
  }
}

// ─── Shared detail info row ───────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor, this.icon});
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor ?? theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ─── Map Widget ───────────────────────────────────────────────────────────────

class _MapWidget extends StatelessWidget {
  const _MapWidget({required this.device, required this.locations});
  final DeviceModel device;
  final List<LocationModel> locations;

  @override
  Widget build(BuildContext context) {
    final hasPosition = device.latitude != null && device.longitude != null;
    if (!hasPosition && locations.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_rounded, size: 36, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 8),
              Text(
                'Chưa có dữ liệu vị trí',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    }

    final center = hasPosition
        ? LatLng(device.latitude!, device.longitude!)
        : LatLng(locations.first.latitude, locations.first.longitude);

    final routePoints = locations.map((l) => LatLng(l.latitude, l.longitude)).toList();

    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 15),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.vmonitor.app',
        ),
        if (routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                color: const Color(0xFF2563EB).withValues(alpha: 0.7),
                strokeWidth: 3,
              ),
            ],
          ),
        if (hasPosition)
          MarkerLayer(
            markers: [
              Marker(
                point: center,
                width: 40,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: device.isMoving ? const Color(0xFF2563EB) : const Color(0xFF16A34A),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    DeviceIcon.iconFor(device.deviceType),
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        MarkerLayer(
          markers: locations
              .where((l) => !l.isMoving)
              .map((l) => Marker(
                    point: LatLng(l.latitude, l.longitude),
                    width: 12,
                    height: 12,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706).withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

// ─── Tab 2: Usage History (Usages + Assignments combined) ────────────────────

class _UsageHistoryTab extends StatelessWidget {
  const _UsageHistoryTab({required this.usages, required this.assignments});
  final List<UsageSessionModel> usages;
  final List<AssignmentModel> assignments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (usages.isEmpty && assignments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 48, color: theme.colorScheme.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('Chưa có lịch sử sử dụng',
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    // Build a combined timeline: active assignment on top, then usage sessions
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Active assignment section
        if (assignments.isNotEmpty) ...[
          _TimelineHeader(label: 'Phân công thiết bị'),
          const SizedBox(height: 8),
          ...assignments.map((a) => _AssignmentItem(a: a, dateFormat: dateFormat)),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
        ],

        // Usage sessions
        if (usages.isNotEmpty) ...[
          _TimelineHeader(label: 'Phiên sử dụng'),
          const SizedBox(height: 8),
          ...usages.map((u) => _UsageItem(u: u, dateFormat: dateFormat)),
        ],
      ],
    );
  }
}

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _AssignmentItem extends StatelessWidget {
  const _AssignmentItem({required this.a, required this.dateFormat});
  final AssignmentModel a;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = a.unassignedAt == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: isActive ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: isActive
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: Icon(
              isActive ? Icons.person_rounded : Icons.person_off_rounded,
              size: 18,
              color: isActive ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.outline,
            ),
          ),
          title: Text(
            a.personName ?? 'Người dùng',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (a.personCode != null) Text('Mã: ${a.personCode}', style: theme.textTheme.bodySmall),
              Text('Từ: ${dateFormat.format(a.assignedAt)}', style: theme.textTheme.bodySmall),
              if (!isActive) Text('Đến: ${dateFormat.format(a.unassignedAt!)}', style: theme.textTheme.bodySmall),
              if (a.notes != null) Text('Ghi chú: ${a.notes}', style: theme.textTheme.bodySmall),
            ],
          ),
          trailing: isActive
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Đang giữ',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _UsageItem extends StatelessWidget {
  const _UsageItem({required this.u, required this.dateFormat});
  final UsageSessionModel u;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOngoing = u.endedAt == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.play_circle_rounded, size: 16,
                    color: isOngoing ? const Color(0xFF16A34A) : theme.colorScheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Phiên ${dateFormat.format(u.startedAt.toLocal())}',
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (isOngoing)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Đang diễn ra',
                        style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFF16A34A))),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              // Meta grid
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  if (u.personName != null)
                    _UsageMeta(icon: Icons.person_rounded, text: '${u.personName} (${u.personCode})'),
                  if (u.distanceM != null)
                    _UsageMeta(icon: Icons.route_rounded, text: '${(u.distanceM! / 1000).toStringAsFixed(2)} km'),
                  if (u.maxSpeedMps != null)
                    _UsageMeta(icon: Icons.speed_rounded, text: 'Max ${(u.maxSpeedMps! * 3.6).toStringAsFixed(1)} km/h'),
                  if (u.movingDurationS != null)
                    _UsageMeta(icon: Icons.navigation_rounded, text: '${(u.movingDurationS! / 60).toStringAsFixed(0)} phút di chuyển'),
                  if (u.stoppedDurationS != null)
                    _UsageMeta(icon: Icons.pause_circle_rounded, text: '${(u.stoppedDurationS! / 60).toStringAsFixed(0)} phút dừng'),
                  if (!isOngoing && u.endedAt != null)
                    _UsageMeta(icon: Icons.stop_circle_rounded, text: 'Đến ${dateFormat.format(u.endedAt!.toLocal())}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageMeta extends StatelessWidget {
  const _UsageMeta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

// ─── Tab 3: Events — Timeline visual ─────────────────────────────────────────

class _EventsTab extends StatelessWidget {
  const _EventsTab({required this.events});
  final List<DeviceEventModel> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_rounded, size: 48, color: theme.colorScheme.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('Chưa có sự kiện',
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    final dateFormat = DateFormat('dd/MM HH:mm:ss');

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final isLast = index == events.length - 1;

        return _EventTimelineItem(
          event: event,
          dateFormat: dateFormat,
          isLast: isLast,
        );
      },
    );
  }
}

class _EventTimelineItem extends StatelessWidget {
  const _EventTimelineItem({
    required this.event,
    required this.dateFormat,
    required this.isLast,
  });
  final DeviceEventModel event;
  final DateFormat dateFormat;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _eventColor(event.eventType);
    final icon = _eventIcon(event.eventType);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline column
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: theme.colorScheme.outlineVariant,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.eventLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateFormat.format(event.occurredAt.toLocal()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _eventIcon(String type) {
    switch (type) {
      case 'ONLINE':
        return Icons.check_circle_rounded;
      case 'OFFLINE':
        return Icons.cancel_rounded;
      case 'MOVING':
        return Icons.navigation_rounded;
      case 'IDLE':
        return Icons.pause_circle_rounded;
      case 'ASSIGNED':
        return Icons.person_add_rounded;
      case 'UNASSIGNED':
        return Icons.person_remove_rounded;
      case 'STARTED':
        return Icons.play_circle_rounded;
      case 'STOPPED':
        return Icons.stop_circle_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  Color _eventColor(String type) {
    switch (type) {
      case 'ONLINE':
        return const Color(0xFF16A34A);
      case 'OFFLINE':
        return Colors.grey;
      case 'MOVING':
        return const Color(0xFF2563EB);
      case 'IDLE':
        return const Color(0xFFD97706);
      case 'ASSIGNED':
        return const Color(0xFF0D9488);
      case 'UNASSIGNED':
        return const Color(0xFFDC2626);
      default:
        return Colors.grey;
    }
  }
}

// ─── Share Location ───────────────────────────────────────────────────────────

class _ShareLocationMenu extends StatelessWidget {
  const _ShareLocationMenu({required this.device});
  final DeviceModel device;

  @override
  Widget build(BuildContext context) {
    final hasLocation = MapLauncherService.isValidCoordinate(device.latitude, device.longitude);

    if (!hasLocation) {
      return PopupMenuButton<String>(
        icon: const Icon(Icons.share_location_rounded),
        tooltip: 'Chia sẻ vị trí',
        itemBuilder: (context) => [
          const PopupMenuItem<String>(
            enabled: false,
            child: Text('Vị trí không khả dụng'),
          ),
        ],
      );
    }

    final isStale = device.lastSeenAt != null &&
        DateTime.now().difference(device.lastSeenAt!).inMinutes > 5;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.share_location_rounded),
      tooltip: 'Chia sẻ vị trí',
      onSelected: (value) async {
        if (value == 'google') {
          final success = await MapLauncherService.openGoogleMaps(device.latitude, device.longitude);
          if (!success && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không thể mở Google Maps')),
            );
          }
        } else if (value == 'apple') {
          final success = await MapLauncherService.openAppleMaps(device.latitude, device.longitude);
          if (!success && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không thể mở Apple Maps')),
            );
          }
        } else if (value == 'copy') {
          try {
            await MapLauncherService.copyLocationToClipboard(device, device.latitude, device.longitude);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã copy vị trí')),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Không thể copy vị trí')),
              );
            }
          }
        }
      },
      itemBuilder: (context) => [
        if (isStale) ...[
          PopupMenuItem<String>(
            enabled: false,
            child: Text(
              'Vị trí cũ (${DateFormat('HH:mm dd/MM').format(device.lastSeenAt!.toLocal())})',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
          ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem<String>(
          value: 'google',
          child: Row(children: [Icon(Icons.map_rounded, size: 20), SizedBox(width: 12), Text('Google Maps')]),
        ),
        const PopupMenuItem<String>(
          value: 'apple',
          child: Row(children: [Icon(Icons.apple, size: 20), SizedBox(width: 12), Text('Apple Maps')]),
        ),
        const PopupMenuItem<String>(
          value: 'copy',
          child: Row(children: [Icon(Icons.content_copy_rounded, size: 20), SizedBox(width: 12), Text('Copy Location')]),
        ),
      ],
    );
  }
}
