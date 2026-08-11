import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/widgets/device_icon.dart';
import '../../core/widgets/status_badge.dart';
import '../../data/models/device_model.dart';
import '../../data/models/device_event_model.dart';
import '../../data/models/location_model.dart';
import 'device_detail_cubit.dart';

import '../../data/repositories/device_repository.dart';
import '../../data/repositories/tracking_repository.dart';
import '../../core/network/api_client.dart';

/// Device detail page with tabs: Overview, Map, History, Events.
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
            appBar: AppBar(title: const Text('Thiết bị')),
            body: Center(
              child: Text(state.error ?? 'Không tìm thấy thiết bị'),
            ),
          );
        }

        final device = state.device!;

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  DeviceIcon(
                    deviceType: device.deviceType,
                    isOnline: device.isOnline,
                    isMoving: device.isMoving,
                  ),
                  const SizedBox(width: 8),
                  Text(device.deviceCode),
                  const SizedBox(width: 8),
                  StatusBadge(
                    label: device.statusLabel,
                    isOnline: device.isOnline,
                    isMoving: device.isMoving,
                  ),
                ],
              ),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Tổng quan'),
                  Tab(text: 'Bản đồ'),
                  Tab(text: 'Lịch sử'),
                  Tab(text: 'Sự kiện'),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => context.read<DeviceDetailCubit>().load(),
                  tooltip: 'Tải lại',
                ),
              ],
            ),
            body: TabBarView(
              children: [
                _OverviewTab(device: device),
                _MapTab(device: device, locations: state.locations),
                _HistoryTab(locations: state.locations),
                _EventsTab(events: state.events),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Overview tab — device info cards.
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.device});
  final DeviceModel device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Thông tin', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _InfoRow(label: 'Mã thiết bị', value: device.deviceCode),
                  _InfoRow(label: 'Tên', value: device.name),
                  _InfoRow(label: 'Loại', value: _deviceTypeLabel(device.deviceType)),
                  _InfoRow(label: 'Trạng thái', value: device.statusLabel),
                  if (device.currentPersonName != null)
                    _InfoRow(label: 'Người giữ', value: device.currentPersonName!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vị trí hiện tại', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (device.latitude != null && device.longitude != null) ...[
                    _InfoRow(
                      label: 'Tọa độ',
                      value: '${device.latitude!.toStringAsFixed(6)}, ${device.longitude!.toStringAsFixed(6)}',
                    ),
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
                    _InfoRow(
                      label: 'Di chuyển',
                      value: device.isMoving ? 'Có' : 'Không',
                    ),
                  ] else
                    Text(
                      'Chưa có dữ liệu vị trí',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  if (device.lastSeenAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Hoạt động lần cuối: ${_formatTime(device.lastSeenAt!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
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
      final localDt = dt.toLocal();
      return DateFormat('dd/MM/yyyy HH:mm:ss').format(localDt);
    } catch (_) {
      return dt.toString();
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Map tab — shows device position and route.
class _MapTab extends StatelessWidget {
  const _MapTab({required this.device, required this.locations});
  final DeviceModel device;
  final List<LocationModel> locations;

  @override
  Widget build(BuildContext context) {
    final hasPosition = device.latitude != null && device.longitude != null;
    if (!hasPosition && locations.isEmpty) {
      return const Center(child: Text('Chưa có dữ liệu vị trí'));
    }

    final center = hasPosition
        ? LatLng(device.latitude!, device.longitude!)
        : LatLng(locations.first.latitude, locations.first.longitude);

    // Build route polyline from locations
    final routePoints = locations
        .map((l) => LatLng(l.latitude, l.longitude))
        .toList();

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 15,
      ),
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
                color: Colors.blue.withValues(alpha: 0.7),
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
                    color: device.isMoving ? Colors.blue : Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    DeviceIcon.iconFor(device.deviceType),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        // Mark stopped locations
        MarkerLayer(
          markers: locations
              .where((l) => !l.isMoving)
              .map((l) => Marker(
                    point: LatLng(l.latitude, l.longitude),
                    width: 12,
                    height: 12,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.8),
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

/// History tab — list of location samples with timestamps and speed.
class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.locations});
  final List<LocationModel> locations;

  @override
  Widget build(BuildContext context) {
    if (locations.isEmpty) {
      return const Center(child: Text('Chưa có dữ liệu lịch sử'));
    }

    final theme = Theme.of(context);
    final dateFormat = DateFormat('HH:mm:ss');

    // Group by date
    final reversed = locations.reversed.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: reversed.length,
      itemBuilder: (context, index) {
        final loc = reversed[index];
        final speedKmh = (loc.speedMps ?? 0) * 3.6;

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: loc.isMoving ? Colors.blue : Colors.orange,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: Text(
                  dateFormat.format(loc.measuredAt.toLocal()),
                  style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '${speedKmh.toStringAsFixed(1)} km/h',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: loc.isMoving ? Colors.blue : theme.colorScheme.outline,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
              if (loc.headingDeg != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Transform.rotate(
                    angle: (loc.headingDeg! * 3.14159 / 180),
                    child: Icon(
                      Icons.navigation,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Events tab — chronological list of device events.
class _EventsTab extends StatelessWidget {
  const _EventsTab({required this.events});
  final List<DeviceEventModel> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(child: Text('Chưa có sự kiện'));
    }

    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM HH:mm:ss');

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: events.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final event = events[index];
        return ListTile(
          dense: true,
          leading: Icon(
            _eventIcon(event.eventType),
            color: _eventColor(event.eventType),
            size: 20,
          ),
          title: Text(event.eventLabel),
          subtitle: Text(
            dateFormat.format(event.occurredAt.toLocal()),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        );
      },
    );
  }

  IconData _eventIcon(String type) {
    switch (type) {
      case 'ONLINE':
        return Icons.check_circle;
      case 'OFFLINE':
        return Icons.cancel;
      case 'MOVING':
        return Icons.navigation;
      case 'IDLE':
        return Icons.pause_circle;
      case 'ASSIGNED':
        return Icons.person_add;
      case 'UNASSIGNED':
        return Icons.person_remove;
      case 'STARTED':
        return Icons.play_circle;
      case 'STOPPED':
        return Icons.stop_circle;
      default:
        return Icons.info;
    }
  }

  Color _eventColor(String type) {
    switch (type) {
      case 'ONLINE':
        return Colors.green;
      case 'OFFLINE':
        return Colors.grey;
      case 'MOVING':
        return Colors.blue;
      case 'IDLE':
        return Colors.orange;
      case 'ASSIGNED':
        return Colors.teal;
      case 'UNASSIGNED':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
