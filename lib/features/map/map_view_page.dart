import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/map_tile_providers.dart';
import '../../core/widgets/device_icon.dart';
import '../../data/models/device_model.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../domain/entities/device_status_resolver.dart';
import '../dashboard/dashboard_cubit.dart';
import '../dashboard/dashboard_state.dart';
import 'widgets/device_list_overlay.dart';

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

  static const Color _primaryBlue = Color(0xFF2563EB);
  static const Color _textMain = Color(0xFF0F172A);
  static const Color _textMuted = Color(0xFF64748B);
  static const Color _borderColor = Color(0xFFE2E8F0);

  final MapController _mapController = MapController();
  bool _showDesktopList = false;
  bool _mapReady = false;
  double _currentZoom = _initialZoom;
  bool _isSatellite = false;

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
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: const Color(0xFFEFF5F8),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            shape: const Border(bottom: BorderSide(color: _borderColor)),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: _textMain),
              tooltip: 'Quay lại',
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/dashboard');
                }
              },
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.travel_explore_rounded,
                    size: 18,
                    color: _primaryBlue,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Bản đồ giám sát',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textMain,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Text(
                    '${state.devices.length} thiết bị',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _textMain,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              if (!state.isLoading && state.devices.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _showDesktopList && isDesktop
                          ? _primaryBlue.withValues(alpha: 0.15)
                          : const Color(0xFFF8FAFC),
                      foregroundColor: _showDesktopList && isDesktop
                          ? _primaryBlue
                          : _textMain,
                      side: BorderSide(
                        color: _showDesktopList && isDesktop
                            ? _primaryBlue
                            : _borderColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact,
                    ),
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
                    icon: const Icon(Icons.list_alt_rounded, size: 16),
                    label: Text(
                      isDesktop ? 'Danh sách (${state.devices.length})' : 'Danh sách',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: _textMain),
                tooltip: 'Làm mới dữ liệu',
                onPressed: () => context.read<DashboardCubit>().loadDashboard(),
              ),
              const SizedBox(width: 4),
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

            if (!isDesktop && _showDesktopList) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
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
                          urlTemplate: MapTileProviders.getUrl(
                            _isSatellite
                                ? AppMapType.satellite
                                : AppMapType.standard,
                          ),
                          userAgentPackageName: 'com.vmonitor.app',
                          minZoom: _minZoom,
                          maxZoom: _maxZoom,
                          maxNativeZoom: MapTileProviders.getMaxZoom(
                            _isSatellite
                                ? AppMapType.satellite
                                : AppMapType.standard,
                          ),
                          tileProvider: NetworkTileProvider(
                            silenceExceptions: true,
                          ),
                          errorImage: MemoryImage(
                            TileProvider.transparentImage,
                          ),
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
                      onToggleMapType: () =>
                          setState(() => _isSatellite = !_isSatellite),
                      isSatellite: _isSatellite,
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
                            color: Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _borderColor),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                                blurRadius: 18,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _primaryBlue.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.location_off_rounded,
                                  size: 36,
                                  color: _primaryBlue,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Chưa có thiết bị nào có dữ liệu GPS',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _textMain,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (state.devices.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${state.devices.length} thiết bị đang chờ tín hiệu GPS',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _textMuted,
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
    final isStale = status.freshness == DataFreshnessStatus.stale;
    final Color markerColor;
    if (status.connectivity == ConnectivityStatus.offline) {
      markerColor = const Color(0xFF64748B);
    } else if (isStale) {
      markerColor = const Color(0xFFDC2626);
    } else if (isMoving) {
      markerColor = const Color(0xFF1677FF);
    } else if (status.movement == MovementStatus.stopped) {
      markerColor = const Color(0xFFD97706);
    } else {
      markerColor = const Color(0xFF16A34A);
    }

    final displayName = device.name.trim().isNotEmpty
        ? device.name.trim()
        : device.deviceCode.trim();

    return Marker(
      point: LatLng(device.latitude!, device.longitude!),
      width: 140,
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
                      displayName,
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
    required this.onToggleMapType,
    required this.isSatellite,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCenter;
  final VoidCallback onToggleMapType;
  final bool isSatellite;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cụm 1: Phóng to, thu nhỏ, căn giữa bản đồ
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
              const SizedBox(width: 32, child: Divider(height: 1, color: Color(0xFFE2E8F0))),
              _MapControlButton(
                icon: Icons.remove_rounded,
                tooltip: 'Thu nhỏ bản đồ',
                onPressed: onZoomOut,
              ),
              const SizedBox(width: 32, child: Divider(height: 1, color: Color(0xFFE2E8F0))),
              _MapControlButton(
                icon: Icons.my_location_rounded,
                tooltip: 'Căn giữa bản đồ',
                onPressed: onCenter,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Cụm 2: Chuyển đổi mode bản đồ (đường phố / vệ tinh) riêng biệt
        DecoratedBox(
          decoration: _decoration(),
          child: _MapControlButton(
            icon: isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
            tooltip: isSatellite
                ? 'Chuyển sang bản đồ đường phố'
                : 'Chuyển sang bản đồ vệ tinh',
            iconColor: isSatellite
                ? const Color(0xFF2563EB)
                : const Color(0xFF475569),
            onPressed: onToggleMapType,
          ),
        ),
      ],
    );
  }

  BoxDecoration _decoration() {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.08),
          blurRadius: 14,
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
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? iconColor;

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
          icon: Icon(
            icon,
            size: 20,
            color: iconColor ?? const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
