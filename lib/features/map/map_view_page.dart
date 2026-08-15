import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/widgets/device_icon.dart';
import '../../data/models/device_model.dart';
import '../../domain/entities/device_status_resolver.dart';
import '../dashboard/dashboard_cubit.dart';
import '../dashboard/dashboard_state.dart';
import 'widgets/device_list_overlay.dart';

import '../../data/repositories/device_repository.dart';
import '../../data/repositories/geocoding_repository.dart';

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
      geocodingRepo: context.read<GeocodingRepository>(),
    );
    _cubit.loadDashboard();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(value: _cubit, child: const _MapViewBody());
  }
}

class _MapViewBody extends StatefulWidget {
  const _MapViewBody();

  @override
  State<_MapViewBody> createState() => _MapViewBodyState();
}

class _MapViewBodyState extends State<_MapViewBody> {
  static const double _initialZoom = 13;
  static const double _selectedZoom = 18;
  static const double _minZoom = 5;
  static const double _maxZoom = 18;
  static const double _zoomStep = 1;

  final MapController _mapController = MapController();
  bool _showDesktopList = false;
  bool _mapReady = false;
  double _currentZoom = _initialZoom;

  void _onDeviceSelected(BuildContext context, DeviceModel device) {
    if (device.latitude != null && device.longitude != null) {
      if (!_mapReady) return;
      _currentZoom = _selectedZoom;
      _mapController.move(
        LatLng(device.latitude!, device.longitude!),
        _selectedZoom,
        id: 'select-device',
      );
    }
  }

  void _openMobileList(
    BuildContext context,
    List<DeviceModel> devices,
    Map<String, String> addresses,
  ) {
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
              addresses: addresses,
              scrollController: scrollController,
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
  void dispose() {
    _mapController.dispose();
    super.dispose();
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
                          _openMobileList(
                            context,
                            state.devices,
                            state.deviceAddresses,
                          );
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
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0xFFEFF5F8),
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: _initialZoom,
                        minZoom: _minZoom,
                        maxZoom: _maxZoom,
                        onMapReady: () {
                          _mapReady = true;
                          _currentZoom = _initialZoom;
                        },
                        onPositionChanged: (camera, hasGesture) {
                          if (!mounted || camera.zoom == _currentZoom) return;
                          _currentZoom = camera.zoom;
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.vmonitor.app',
                          minZoom: _minZoom,
                          maxZoom: _maxZoom,
                          maxNativeZoom: 19,
                          tileProvider: NetworkTileProvider(
                            silenceExceptions: true,
                          ),
                          errorImage: MemoryImage(
                            TileProvider.transparentImage,
                          ),
                          tileBuilder: _softMapTileBuilder,
                        ),
                        MarkerLayer(
                          markers: located
                              .map((device) => _buildMarker(context, device))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _MapControls(
                      onZoomIn: () => _zoomBy(_zoomStep),
                      onZoomOut: () => _zoomBy(-_zoomStep),
                      onCenter: () => _centerOn(center),
                    ),
                  ),
                ),
                // Empty GPS state overlay
                if (located.isEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.all(32),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 20,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.location_off_rounded,
                                size: 48,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Chưa có thiết bị nào có dữ liệu GPS',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              if (state.devices.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '${state.devices.length} thiết bị đang chờ tín hiệu GPS',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (isDesktop && _showDesktopList)
                  Positioned(
                    top: 16,
                    right: 16,
                    bottom: 16,
                    child: DeviceListOverlay(
                      devices: state.devices,
                      addresses: state.deviceAddresses,
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
    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );
    final isMoving = status.movement == MovementStatus.moving;
    final Color markerColor;
    if (status.connectivity == ConnectivityStatus.offline) {
      markerColor = Colors.grey.shade500;
    } else if (status.freshness == DataFreshnessStatus.stale) {
      markerColor = Colors.redAccent;
    } else if (isMoving) {
      markerColor = const Color(0xFF2563EB);
    } else {
      markerColor = const Color(0xFF16A34A);
    }

    return Marker(
      point: LatLng(device.latitude!, device.longitude!),
      width: 130,
      height: 52,
      child: GestureDetector(
        onTap: () => context.pushNamed(
          'device-detail',
          pathParameters: {'id': device.id},
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: markerColor,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: markerColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    DeviceIcon.iconFor(device.deviceType),
                    color: Colors.white,
                    size: 13,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      device.name.isNotEmpty ? device.name : device.deviceCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (isMoving) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.navigation_rounded,
                      color: Colors.white,
                      size: 10,
                    ),
                  ],
                ],
              ),
            ),
            // Arrow tip
            CustomPaint(
              size: const Size(10, 6),
              painter: _ArrowPainter(markerColor),
            ),
          ],
        ),
      ),
    );
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    final camera = _mapController.camera;
    final nextZoom = (camera.zoom + delta).clamp(_minZoom, _maxZoom).toDouble();
    _currentZoom = nextZoom;
    _mapController.move(camera.center, nextZoom, id: 'map-zoom');
  }

  void _centerOn(LatLng center) {
    if (!_mapReady) return;
    _mapController.move(center, _currentZoom, id: 'map-center');
  }

  Widget _softMapTileBuilder(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: 0.78, child: tileWidget),
        ColoredBox(color: Colors.white.withValues(alpha: 0.14)),
      ],
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

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onCenter,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCenter;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: _decoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MapControlButton(
                icon: Icons.add_rounded,
                tooltip: 'Phóng to bản đồ',
                onPressed: onZoomIn,
              ),
              const SizedBox(width: 34, child: Divider(height: 1)),
              _MapControlButton(
                icon: Icons.remove_rounded,
                tooltip: 'Thu nhỏ bản đồ',
                onPressed: onZoomOut,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: _decoration(),
          child: _MapControlButton(
            icon: Icons.my_location_rounded,
            tooltip: 'Căn giữa bản đồ',
            onPressed: onCenter,
          ),
        ),
      ],
    );
  }

  BoxDecoration _decoration() {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 34,
        height: 34,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          splashRadius: 18,
          icon: Icon(icon, size: 20, color: const Color(0xFF475569)),
        ),
      ),
    );
  }
}
