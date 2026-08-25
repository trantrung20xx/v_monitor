// Màn hình bản đồ realtime: hiển thị marker thiết bị, danh sách nổi, chọn thiết bị,
// zoom/recenter và nguồn tile theo tùy chọn cá nhân.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/map_tile_providers.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/widgets/device_icon.dart';
import '../../data/models/device_model.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/device_status_resolver.dart';
import '../dashboard/dashboard_cubit.dart';
import '../dashboard/dashboard_state.dart';
import '../settings/settings_cubit.dart';
import 'widgets/device_list_overlay.dart';

/// Trang Bản đồ toàn màn hình hiển thị toàn bộ thiết bị.
class MapViewPage extends StatefulWidget {
  const MapViewPage({super.key});

  @override
  State<MapViewPage> createState() => _MapViewPageState();
}

class _MapViewPageState extends State<MapViewPage> {
  // Cubit riêng của route bản đồ dùng repository cấp ứng dụng; route sở hữu và đóng
  // Cubit để subscription realtime không sống sau khi rời màn hình.
  late DashboardCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = DashboardCubit(
      deviceRepo: context.read<DeviceRepository>(),
      geocodingRepo: context.read<GeocodingRepository>(),
      settingsRepo: context.read<SettingsRepository>(),
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
    // BlocProvider.value đưa Cubit đã khởi tạo xuống thân bản đồ mà không tạo instance mới.
    return BlocProvider.value(value: _cubit, child: const _MapViewBody());
  }
}

// Thân bản đồ giữ state trình bày cục bộ như camera, panel danh sách và mức zoom.
class _MapViewBody extends StatefulWidget {
  const _MapViewBody();

  @override
  State<_MapViewBody> createState() => _MapViewBodyState();
}

class _MapViewBodyState extends State<_MapViewBody> {
  // Giới hạn camera khớp khả năng nguồn tile; selectedZoom dùng khi chọn thiết bị.
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
    // Chỉ di chuyển camera khi backend đã trả đủ tọa độ và FlutterMap đã sẵn sàng.
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
    // Mobile dùng bottom sheet kéo được để danh sách không che bản đồ vĩnh viễn;
    // dữ liệu thiết bị/địa chỉ là snapshot hiện tại từ DashboardState.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppPalette.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          snap: true,
          snapSizes: const [0.35, 0.65, 0.92],
          builder: (context, scrollController) {
            return DeviceListOverlay(
              devices: devices,
              addresses: addresses,
              scrollController: scrollController,
              isMobileSheet: true,
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
    // SettingsCubit cung cấp loại tile; DashboardCubit cung cấp thiết bị, tọa độ và
    // địa chỉ. Breakpoint 800 px chỉ quyết định layout, không đổi dữ liệu nghiệp vụ.
    final appColors = context.appColors;
    final isDesktop = MediaQuery.of(context).size.width > 800;
    final mapType = context.watch<SettingsCubit>().state.userSettings.mapType;
    final isSatellite = mapType == AppMapType.satellite;

    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        // Scaffold gồm AppBar thao tác và một Stack bản đồ toàn vùng ở body.
        return Scaffold(
          backgroundColor: appColors.mapBackground,
          appBar: AppBar(
            backgroundColor: appColors.surface,
            elevation: 0,
            shape: Border(bottom: BorderSide(color: appColors.border)),
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_rounded,
                color: appColors.textPrimary,
              ),
              tooltip: 'Quay lại',
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.goNamed('dashboard');
                }
              },
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: appColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    Icons.travel_explore_rounded,
                    size: 17,
                    color: appColors.primary,
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    'Bản đồ giám sát',
                    style: TextStyle(
                      fontSize: isDesktop ? 16 : 15,
                      fontWeight: FontWeight.w700,
                      color: appColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: appColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: appColors.border),
                    ),
                    child: Text(
                      '${state.devices.length} thiết bị',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: appColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (!state.isLoading && state.devices.isNotEmpty) ...[
                if (isDesktop)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 4,
                    ),
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _showDesktopList
                            ? appColors.primary.withValues(alpha: 0.15)
                            : appColors.surfaceSubtle,
                        foregroundColor: _showDesktopList
                            ? appColors.primary
                            : appColors.textPrimary,
                        side: BorderSide(
                          color: _showDesktopList
                              ? appColors.primary
                              : appColors.border,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        setState(() {
                          _showDesktopList = !_showDesktopList;
                        });
                      },
                      icon: const Icon(Icons.list_alt_rounded, size: 16),
                      label: Text(
                        'Danh sách (${state.devices.length})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                else
                  IconButton(
                    icon: Badge(
                      isLabelVisible: state.devices.isNotEmpty,
                      label: Text(
                        '${state.devices.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: appColors.primary,
                      textColor: AppPalette.onAccent,
                      child: Icon(
                        Icons.list_alt_rounded,
                        color: appColors.textPrimary,
                      ),
                    ),
                    tooltip: 'Danh sách thiết bị',
                    onPressed: () => _openMobileList(
                      context,
                      state.devices,
                      state.deviceAddresses,
                    ),
                  ),
              ],
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: appColors.textPrimary),
                tooltip: 'Làm mới dữ liệu',
                onPressed: () => context.read<DashboardCubit>().loadDashboard(),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: () {
            // Loading chỉ che trong lần lấy snapshot REST đầu; cập nhật WebSocket sau
            // đó được hợp nhất vào state mà không thay toàn màn hình bằng spinner.
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            // Marker chỉ được tạo cho thiết bị có đủ cả latitude và longitude thật.
            // Thiết bị thiếu GPS vẫn xuất hiện trong danh sách và số đếm tổng.
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

            // Thứ tự lớp: tile/marker ở đáy, điều khiển camera, empty overlay,
            // nút mobile hoặc panel desktop ở trên cùng.
            return Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: appColors.mapBackground,
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
                        // URL và max zoom lấy từ MapTileProviders theo tùy chọn cá
                        // nhân; lỗi tile dùng ảnh trong suốt để không phá layout.
                        TileLayer(
                          urlTemplate: MapTileProviders.getUrl(
                            isSatellite
                                ? AppMapType.satellite
                                : AppMapType.standard,
                          ),
                          userAgentPackageName: 'com.vmonitor.app',
                          minZoom: _minZoom,
                          maxZoom: _maxZoom,
                          maxNativeZoom: MapTileProviders.getMaxZoom(
                            isSatellite
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
                        // Marker được dựng từ danh sách đã lọc tọa độ, mỗi marker mở
                        // route chi tiết theo id database của thiết bị.
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
                          context.read<SettingsCubit>().updateMapType(
                            isSatellite
                                ? AppMapType.standard
                                : AppMapType.satellite,
                          ),
                      isSatellite: isSatellite,
                    ),
                  ),
                ),
                // Lớp thông báo khi chưa có dữ liệu GPS.
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
                            color: appColors.surface.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: appColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: appColors.shadow.withValues(alpha: 0.12),
                                blurRadius: 18,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: appColors.primary.withValues(
                                    alpha: 0.08,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.location_off_rounded,
                                  size: 36,
                                  color: appColors.primary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Chưa có thiết bị nào có dữ liệu GPS',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: appColors.textPrimary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (state.devices.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${state.devices.length} thiết bị đang chờ tín hiệu GPS',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: appColors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                // Nút thao tác nổi trên màn hình di động.
                if (!isDesktop && !state.isLoading && state.devices.isNotEmpty)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.extended(
                      heroTag: 'mobile-map-device-list-fab',
                      elevation: 3,
                      highlightElevation: 5,
                      backgroundColor: appColors.surface,
                      foregroundColor: appColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(color: appColors.border),
                      ),
                      icon: const Icon(Icons.list_alt_rounded, size: 18),
                      label: Text(
                        'Danh sách (${state.devices.length})',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: appColors.textPrimary,
                        ),
                      ),
                      onPressed: () => _openMobileList(
                        context,
                        state.devices,
                        state.deviceAddresses,
                      ),
                    ),
                  ),
                // Bảng thiết bị nổi trên màn hình desktop.
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
    // Resolver dùng isOnline/lastSeen/GPS/speed thật để chọn màu và biểu tượng;
    // widget không tạo thêm trạng thái vận hành riêng cho bản đồ.
    final appColors = context.appColors;
    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      latestMeasuredAt: device.latestMeasuredAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );
    final isMoving = status.movement == MovementStatus.moving;
    final isStale = status.freshness == DataFreshnessStatus.stale;
    final Color markerColor;
    if (status.connectivity == ConnectivityStatus.offline) {
      markerColor = appColors.offline;
    } else if (isStale) {
      markerColor = appColors.danger;
    } else if (isMoving) {
      markerColor = appColors.primary;
    } else if (status.movement == MovementStatus.stopped) {
      markerColor = appColors.warning;
    } else {
      markerColor = appColors.success;
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
                    color: AppPalette.onAccent,
                    size: 13,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        color: AppPalette.onAccent,
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
                      color: AppPalette.onAccent,
                      size: 10,
                    ),
                  ],
                ],
              ),
            ),
            // Mũi nhọn nối nhãn với điểm tọa độ.
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
    // Clamp mức zoom trong giới hạn tile trước khi điều khiển camera.
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

// Vẽ mũi nhọn nhỏ nối nhãn marker với đúng điểm tọa độ trên bản đồ.
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

// Cụm nút nổi điều khiển zoom, căn giữa và đổi loại bản đồ; callback do state cha xử lý.
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
          decoration: _decoration(context),
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
              const SizedBox(width: 34, child: Divider(height: 1)),
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
          decoration: _decoration(context),
          child: _MapControlButton(
            icon: isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
            tooltip: isSatellite
                ? 'Chuyển sang bản đồ đường phố'
                : 'Chuyển sang bản đồ vệ tinh',
            iconColor: context.appColors.primary,
            onPressed: onToggleMapType,
          ),
        ),
      ],
    );
  }

  BoxDecoration _decoration(BuildContext context) {
    final appColors = context.appColors;
    return BoxDecoration(
      color: appColors.surface.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: appColors.border),
      boxShadow: [
        BoxShadow(
          color: appColors.shadow.withValues(alpha: 0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}

// Nút bản đồ vuông dùng tooltip/semantics và màu theme thống nhất cho từng hành động.
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
            size: 18,
            color: iconColor ?? context.appColors.primary,
          ),
        ),
      ),
    );
  }
}
