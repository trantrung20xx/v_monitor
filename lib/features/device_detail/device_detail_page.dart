import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/widgets/device_icon.dart';
import '../../core/widgets/status_badge.dart';
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

/// Chi tiết thiết bị với các tab: Tổng quan, Bản đồ, Phân công, Lịch sử dùng, Sự kiện.
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
        
        final status = DeviceStatusResolver.resolve(
          isOnline: device.isOnline,
          lastSeenAt: device.lastSeenAt,
          currentSpeedMps: device.currentSpeedMps,
          baseStatus: device.status,
        );

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
                    label: status.label,
                    isOnline: status.connectivity == ConnectivityStatus.online,
                    isMoving: status.movement == MovementStatus.moving,
                  ),
                ],
              ),
              bottom: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Tổng quan & Bản đồ'),
                  Tab(text: 'Lịch sử phân công'),
                  Tab(text: 'Lịch sử sử dụng'),
                  Tab(text: 'Sự kiện hệ thống'),
                ],
              ),
              actions: [
                _ShareLocationMenu(device: device),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => context.read<DeviceDetailCubit>().load(),
                  tooltip: 'Tải lại',
                ),
              ],
            ),
            body: TabBarView(
              children: [
                _OverviewTab(device: device, locations: state.locations, address: state.address),
                _AssignmentsTab(assignments: state.assignments),
                _UsagesTab(usages: state.usages),
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
          SizedBox(
            height: 300,
            child: _MapWidget(device: device, locations: locations),
          ),
          Padding(
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
                        _InfoRow(label: 'Trạng thái', value: status.label),
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
                        Text('Trạng thái hiện tại', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        if (device.latitude != null && device.longitude != null) ...[
                          _InfoRow(
                            label: 'Tọa độ',
                            value: 'Kinh độ: ${device.longitude!.toStringAsFixed(6)}\nVĩ độ: ${device.latitude!.toStringAsFixed(6)}',
                          ),
                          if (address != null && address!.isNotEmpty)
                            _InfoRow(
                              label: 'Địa điểm',
                              value: address!,
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
                        ] else
                          Text(
                            'Chưa có dữ liệu vị trí',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          
                        if (device.uavBatteryPct != null)
                          _InfoRow(
                            label: 'Pin UAV',
                            value: '${device.uavBatteryPct}%',
                          ),
                        if (device.controllerBatteryPct != null)
                          _InfoRow(
                            label: 'Pin Điều khiển',
                            value: '${device.controllerBatteryPct}%',
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
        child: const Center(child: Text('Chưa có dữ liệu vị trí', style: TextStyle(color: Colors.grey))),
      );
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

/// Assignments Tab
class _AssignmentsTab extends StatelessWidget {
  const _AssignmentsTab({required this.assignments});
  final List<AssignmentModel> assignments;

  @override
  Widget build(BuildContext context) {
    if (assignments.isEmpty) {
      return const Center(child: Text('Chưa có lịch sử phân công'));
    }

    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: assignments.length,
      itemBuilder: (context, index) {
        final a = assignments[index];
        final isActive = a.unassignedAt == null;
        
        return Card(
          elevation: isActive ? 2 : 0,
          color: isActive ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerHighest,
          child: ListTile(
            leading: Icon(
              isActive ? Icons.person : Icons.person_off,
              color: isActive ? theme.colorScheme.primary : theme.colorScheme.outline,
            ),
            title: Text(
              a.personName ?? 'Người dùng',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a.personCode != null) Text('Mã NV: ${a.personCode}'),
                Text('Bắt đầu: ${dateFormat.format(a.assignedAt)}'),
                if (!isActive) Text('Kết thúc: ${dateFormat.format(a.unassignedAt!)}'),
                if (a.notes != null) Text('Ghi chú: ${a.notes}'),
              ],
            ),
            trailing: isActive
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Đang giữ',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}

/// Usages Tab
class _UsagesTab extends StatelessWidget {
  const _UsagesTab({required this.usages});
  final List<UsageSessionModel> usages;

  @override
  Widget build(BuildContext context) {
    if (usages.isEmpty) {
      return const Center(child: Text('Chưa có lịch sử sử dụng'));
    }

    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: usages.length,
      itemBuilder: (context, index) {
        final u = usages[index];
        final isOngoing = u.endedAt == null;
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Phiên ${dateFormat.format(u.startedAt)}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (isOngoing)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Đang diễn ra',
                          style: theme.textTheme.labelSmall?.copyWith(color: Colors.green),
                        ),
                      ),
                  ],
                ),
                const Divider(),
                if (u.personName != null) ...[
                  _InfoRow(label: 'Người dùng', value: '${u.personName} (${u.personCode})'),
                ],
                _InfoRow(
                  label: 'Thời gian', 
                  value: isOngoing 
                    ? 'Từ ${dateFormat.format(u.startedAt)}'
                    : '${dateFormat.format(u.startedAt)} - ${dateFormat.format(u.endedAt!)}'
                ),
                if (u.distanceM != null)
                  _InfoRow(
                    label: 'Quãng đường', 
                    value: '${(u.distanceM! / 1000).toStringAsFixed(2)} km'
                  ),
                if (u.maxSpeedMps != null)
                  _InfoRow(
                    label: 'Tốc độ tối đa', 
                    value: '${(u.maxSpeedMps! * 3.6).toStringAsFixed(1)} km/h'
                  ),
                if (u.avgSpeedMps != null)
                  _InfoRow(
                    label: 'Tốc độ TB', 
                    value: '${(u.avgSpeedMps! * 3.6).toStringAsFixed(1)} km/h'
                  ),
                if (u.movingDurationS != null)
                  _InfoRow(
                    label: 'Thời gian di chuyển', 
                    value: '${(u.movingDurationS! / 60).toStringAsFixed(0)} phút'
                  ),
                if (u.stoppedDurationS != null)
                  _InfoRow(
                    label: 'Thời gian dừng', 
                    value: '${(u.stoppedDurationS! / 60).toStringAsFixed(0)} phút'
                  ),
              ],
            ),
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

class _ShareLocationMenu extends StatelessWidget {
  const _ShareLocationMenu({required this.device});
  final DeviceModel device;

  @override
  Widget build(BuildContext context) {
    final hasLocation = MapLauncherService.isValidCoordinate(device.latitude, device.longitude);

    if (!hasLocation) {
      return PopupMenuButton<String>(
        icon: const Icon(Icons.share_location),
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
      icon: const Icon(Icons.share_location),
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
              'Vị trí cũ (Cập nhật: ${DateFormat('HH:mm dd/MM').format(device.lastSeenAt!.toLocal())})',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem<String>(
          value: 'google',
          child: Row(
            children: [
              Icon(Icons.map, size: 20),
              SizedBox(width: 12),
              Text('Google Maps'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'apple',
          child: Row(
            children: [
              Icon(Icons.apple, size: 20),
              SizedBox(width: 12),
              Text('Apple Maps'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.content_copy, size: 20),
              SizedBox(width: 12),
              Text('Copy Location'),
            ],
          ),
        ),
      ],
    );
  }
}

