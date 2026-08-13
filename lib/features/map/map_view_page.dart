import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/widgets/device_icon.dart';
import '../../data/models/device_model.dart';
import '../dashboard/dashboard_cubit.dart';
import '../dashboard/dashboard_state.dart';
import 'widgets/device_list_overlay.dart';

import '../../data/repositories/device_repository.dart';

/// Trang Bản đồ toàn màn hình hiển thị toàn bộ thiết bị.
class MapViewPage extends StatefulWidget {
  const MapViewPage({super.key});

  @override
  State<MapViewPage> createState() => _MapViewPageState();
}

class _MapViewPageState extends State<MapViewPage> {
  late DashboardCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = DashboardCubit(
      deviceRepo: context.read<DeviceRepository>(),
    );
    _cubit.loadDashboard();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: const _MapViewBody(),
    );
  }
}

class _MapViewBody extends StatefulWidget {
  const _MapViewBody();

  @override
  State<_MapViewBody> createState() => _MapViewBodyState();
}

class _MapViewBodyState extends State<_MapViewBody> {
  final MapController _mapController = MapController();
  bool _showDesktopList = false;

  void _onDeviceSelected(BuildContext context, DeviceModel device) {
    if (device.latitude != null && device.longitude != null) {
      _mapController.move(LatLng(device.latitude!, device.longitude!), 16.0);
    }
  }

  void _openMobileList(BuildContext context, List<DeviceModel> devices) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return DeviceListOverlay(
              devices: devices,
              onDeviceSelected: (d) {
                Navigator.pop(context);
                _onDeviceSelected(context, d);
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Bản đồ'),
            actions: [
              if (!state.isLoading && state.devices.isNotEmpty)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = MediaQuery.of(context).size.width > 800;
                    return IconButton(
                      icon: const Icon(Icons.list_alt),
                      tooltip: 'Danh sách thiết bị',
                      onPressed: () {
                        if (isDesktop) {
                          setState(() {
                            _showDesktopList = !_showDesktopList;
                          });
                        } else {
                          _openMobileList(context, state.devices);
                        }
                      },
                    );
                  },
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  context.read<DashboardCubit>().loadDashboard();
                },
                tooltip: 'Tải lại',
              ),
            ],
          ),
          body: () {
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            final located = state.devices
                .where((d) => d.latitude != null && d.longitude != null)
                .toList();

            const defaultCenter = LatLng(21.0285, 105.8542);
            final center = located.isNotEmpty
                ? LatLng(located.first.latitude!, located.first.longitude!)
                : defaultCenter;

            final isDesktop = MediaQuery.of(context).size.width > 800;
            if (!isDesktop && _showDesktopList) {
              // Auto hide when resized to mobile
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  _showDesktopList = false;
                });
              });
            }

            return Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 13,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.vmonitor.app',
                    ),
                    MarkerLayer(
                      markers: located.map((device) => _buildMarker(context, device)).toList(),
                    ),
                  ],
                ),
                if (isDesktop && _showDesktopList)
                  Positioned(
                    top: 16,
                    right: 16,
                    bottom: 16,
                    child: DeviceListOverlay(
                      devices: state.devices,
                      onDeviceSelected: (d) => _onDeviceSelected(context, d),
                      onClose: () => setState(() => _showDesktopList = false),
                    ),
                  ),
              ],
            );
          }(),
        );
      },
    );
  }

  Marker _buildMarker(BuildContext context, DeviceModel device) {
    final color = device.isOnline
        ? (device.isMoving ? Colors.blue : Colors.green)
        : Colors.grey;

    return Marker(
      point: LatLng(device.latitude!, device.longitude!),
      width: 120,
      height: 50,
      child: GestureDetector(
        onTap: () => context.pushNamed(
          'device-detail',
          pathParameters: {'id': device.id},
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    DeviceIcon.iconFor(device.deviceType),
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    device.deviceCode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Arrow pointing down
            CustomPaint(
              size: const Size(10, 6),
              painter: _ArrowPainter(color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
