import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/widgets/device_icon.dart';
import '../../data/models/device_model.dart';
import 'dashboard_cubit.dart';
import 'dashboard_state.dart';
import 'widgets/device_list_panel.dart';
import 'widgets/stats_overview.dart';

import '../../data/repositories/device_repository.dart';
import '../../data/repositories/tracking_repository.dart';
import '../../core/network/api_client.dart';
import '../../core/network/websocket_client.dart';

/// Main dashboard page — stats, map, and device list.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DashboardCubit(
        deviceRepo: context.read<DeviceRepository>(),
        websocketClient: context.read<WebsocketClient>(),
      )..loadDashboard(),
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 800;

    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state.error != null) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 16),
                  Text('Không thể kết nối backend', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    state.error!,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.read<DashboardCubit>().loadDashboard(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Dashboard'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<DashboardCubit>().loadDashboard(),
                tooltip: 'Tải lại',
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatsOverview(state: state),
                const SizedBox(height: 16),
                Expanded(
                  child: isWide
                      ? _WideLayout(state: state)
                      : _NarrowLayout(state: state),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Desktop: map left + device list right
class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.state});
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: _DashboardMap(devices: state.devices),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 320,
          child: Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Thiết bị (${state.totalDevices})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: DeviceListPanel(devices: state.devices)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Mobile: map top + device list bottom
class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({required this.state});
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: _DashboardMap(devices: state.devices),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          flex: 1,
          child: Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Thiết bị (${state.totalDevices})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: DeviceListPanel(devices: state.devices)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Embedded map showing all devices with markers.
class _DashboardMap extends StatelessWidget {
  const _DashboardMap({required this.devices});
  final List<DeviceModel> devices;

  @override
  Widget build(BuildContext context) {
    // Filter devices with valid coordinates
    final located = devices.where((d) => d.latitude != null && d.longitude != null).toList();

    // Default center: Hanoi
    const defaultCenter = LatLng(21.0285, 105.8542);
    final center = located.isNotEmpty
        ? LatLng(located.first.latitude!, located.first.longitude!)
        : defaultCenter;

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 12,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.vmonitor.app',
        ),
        MarkerLayer(
          markers: located.map((device) {
            return Marker(
              point: LatLng(device.latitude!, device.longitude!),
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: () => context.pushNamed(
                  'device-detail',
                  pathParameters: {'id': device.id},
                ),
                child: Tooltip(
                  message: '${device.deviceCode} — ${device.statusLabel}',
                  child: Container(
                    decoration: BoxDecoration(
                      color: device.isOnline
                          ? (device.isMoving ? Colors.blue : Colors.green)
                          : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
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
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
