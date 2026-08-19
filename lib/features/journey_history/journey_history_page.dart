import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/map_tile_providers.dart';
import '../../data/models/device_model.dart';
import '../../data/models/location_model.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../data/repositories/tracking_repository.dart';
import 'journey_history_cubit.dart';
import 'journey_history_state.dart';
import 'widgets/history_map_layers.dart';
import 'widgets/history_time_selector.dart';
import 'widgets/playback_controls.dart';
import 'widgets/point_info_popup.dart';
import 'widgets/route_summary_band.dart';

class JourneyHistoryPage extends StatefulWidget {
  final String? initialDeviceId;

  const JourneyHistoryPage({super.key, this.initialDeviceId});

  @override
  State<JourneyHistoryPage> createState() => _JourneyHistoryPageState();
}

class _JourneyHistoryPageState extends State<JourneyHistoryPage> {
  late JourneyHistoryCubit _cubit;
  List<DeviceModel> _devices = [];
  bool _isLoadingDevices = false;

  late DateTime _fromTime;
  late DateTime _toTime;

  @override
  void initState() {
    super.initState();
    _cubit = JourneyHistoryCubit(
      trackingRepo: context.read<TrackingRepository>(),
      deviceRepo: context.read<DeviceRepository>(),
    );

    // Mặc định khoảng thời gian: Hôm nay từ 00:00 đến thời điểm hiện tại
    final now = DateTime.now();
    _fromTime = DateTime(now.year, now.month, now.day, 0, 0, 0);
    _toTime = now;

    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoadingDevices = true);
    try {
      final devices = await context.read<DeviceRepository>().getDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _isLoadingDevices = false;
      });

      if (devices.isNotEmpty) {
        DeviceModel? target;
        if (widget.initialDeviceId != null) {
          target = devices.cast<DeviceModel?>().firstWhere(
            (d) => d?.id == widget.initialDeviceId,
            orElse: () => null,
          );
        }
        target ??= devices.first;
        _cubit.selectDevice(target);
        _onQuery();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingDevices = false);
    }
  }

  void _onQuery() {
    final dev = _cubit.state.selectedDevice;
    if (dev == null) return;

    if (_fromTime.isAfter(_toTime) || _fromTime.isAtSameMomentAs(_toTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thời điểm bắt đầu phải nhỏ hơn thời điểm kết thúc.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    _cubit.loadHistory(deviceId: dev.id, from: _fromTime, to: _toTime);
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lịch sử hành trình'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Tải lại',
              onPressed: _onQuery,
            ),
          ],
        ),
        body: BlocConsumer<JourneyHistoryCubit, JourneyHistoryState>(
          listener: (context, state) {
            if (state.errorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage!),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          },
          builder: (context, state) {
            final isDesktop = MediaQuery.of(context).size.width >= 800;

            return Column(
              children: [
                // 1. Header chọn thiết bị & thời gian
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: HistoryTimeSelector(
                    devices: _devices,
                    selectedDevice: state.selectedDevice,
                    fromTime: _fromTime,
                    toTime: _toTime,
                    gapThreshold: state.gapThreshold,
                    isLoading: state.isLoading || _isLoadingDevices,
                    onDeviceChanged: (d) {
                      if (d != null) {
                        _cubit.selectDevice(d);
                        _onQuery();
                      }
                    },
                    onFromTimeChanged: (t) => setState(() => _fromTime = t),
                    onToTimeChanged: (t) => setState(() => _toTime = t),
                    onGapThresholdChanged: (g) => _cubit.setGapThreshold(g),
                    onQuery: _onQuery,
                  ),
                ),

                // 2. Summary Band (Tổng quan quãng đường, vận tốc, mẫu GPS)
                if (state.validSamples.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: RouteSummaryBand(state: state),
                  ),

                // 3. Map Viewport & Replay Controls
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Stack(
                      children: [
                        // Map
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _HistoryMapView(
                            state: state,
                            onPointSelected: (point) =>
                                _cubit.selectPoint(point),
                          ),
                        ),

                        // Popup chi tiết điểm GPS khi tap
                        if (state.selectedPoint != null)
                          Positioned(
                            top: 16,
                            left: 16,
                            right: 16,
                            child: Align(
                              alignment: Alignment.topRight,
                              child: PointInfoPopup(
                                point: state.selectedPoint!,
                                stopPoint: HistoryMapLayers.findStopPoint(
                                  state.validSamples,
                                  state.selectedPoint!,
                                ),
                                resolveAddress: context
                                    .read<GeocodingRepository>()
                                    .reverseAddress,
                                onClose: () => _cubit.selectPoint(null),
                              ),
                            ),
                          ),

                        // Thanh điều khiển Playback Controls (nằm ở phía dưới bản đồ)
                        if (state.validSamples.isNotEmpty)
                          Positioned(
                            left: isDesktop ? 16 : 8,
                            right: isDesktop ? 16 : 8,
                            bottom: isDesktop ? 16 : 8,
                            child: PlaybackControls(
                              state: state,
                              onPlay: () => _cubit.play(),
                              onPause: () => _cubit.pause(),
                              onResume: () => _cubit.resume(),
                              onReset: () => _cubit.reset(),
                              onStepBackward30s: () => _cubit.stepBackward(
                                const Duration(seconds: 30),
                              ),
                              onStepBackward60s: () => _cubit.stepBackward(
                                const Duration(seconds: 60),
                              ),
                              onStepForward30s: () => _cubit.stepForward(
                                const Duration(seconds: 30),
                              ),
                              onStepForward60s: () => _cubit.stepForward(
                                const Duration(seconds: 60),
                              ),
                              onSeekProgress: (p) => _cubit.seekToProgress(p),
                              onSpeedChanged: (s) => _cubit.setPlaybackSpeed(s),
                              onFollowChanged: (f) =>
                                  _cubit.toggleFollowCamera(f),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HistoryMapView extends StatefulWidget {
  final JourneyHistoryState state;
  final ValueChanged<LocationModel?> onPointSelected;

  const _HistoryMapView({required this.state, required this.onPointSelected});

  @override
  State<_HistoryMapView> createState() => _HistoryMapViewState();
}

class _HistoryMapViewState extends State<_HistoryMapView> {
  final MapController _mapController = MapController();
  final Map<String, String> _nodeAddresses = {};
  bool _mapReady = false;
  bool _didRequestInitialAddresses = false;
  int _addressRequestVersion = 0;
  double _currentZoom = 13.0;
  bool _isSatellite = false;
  bool _showRouteLabels = true;
  static const LatLng _defaultCenter = LatLng(21.0285, 105.8542);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didRequestInitialAddresses) {
      _didRequestInitialAddresses = true;
      _loadNodeAddresses(widget.state.validSamples);
    }
  }

  @override
  void didUpdateWidget(covariant _HistoryMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldSamples = oldWidget.state.validSamples;
    final newSamples = widget.state.validSamples;

    if (oldSamples != newSamples && newSamples.isNotEmpty) {
      _loadNodeAddresses(newSamples);
      if (_mapReady) {
        _fitRouteBounds(newSamples);
      }
    }

    // Follow camera theo vị trí replay nếu được bật
    if (_mapReady &&
        widget.state.followCamera &&
        widget.state.currentPosition != null) {
      if (widget.state.isPlaying || widget.state.isCompleted) {
        _mapController.move(widget.state.currentPosition!, _currentZoom);
      }
    }
  }

  Future<void> _loadNodeAddresses(List<LocationModel> samples) async {
    final nodes = HistoryMapLayers.extractRouteNodes(samples);
    if (nodes.isEmpty) return;

    final missing = <JourneyRouteNode>[];
    final queuedKeys = <String>{};
    for (final node in nodes) {
      final key = HistoryMapLayers.routeNodeKey(node.sample);
      if (!_nodeAddresses.containsKey(key) && queuedKeys.add(key)) {
        missing.add(node);
      }
    }
    if (missing.isEmpty) return;

    final requestVersion = ++_addressRequestVersion;
    final repository = context.read<GeocodingRepository>();
    final results = await Future.wait(
      missing.map((node) async {
        final address = await repository.reverseAddress(
          node.sample.latitude,
          node.sample.longitude,
        );
        return MapEntry(HistoryMapLayers.routeNodeKey(node.sample), address);
      }),
    );
    if (!mounted || requestVersion != _addressRequestVersion) return;

    setState(() {
      for (final result in results) {
        final address = result.value?.trim();
        if (address != null && address.isNotEmpty) {
          _nodeAddresses[result.key] = address;
        }
      }
    });
  }

  void _fitRouteBounds(List<LocationModel> samples) {
    if (samples.isEmpty || !_mapReady) return;

    if (samples.length == 1) {
      _mapController.move(
        LatLng(samples.first.latitude, samples.first.longitude),
        15.0,
      );
      return;
    }

    final points = samples.map((s) => LatLng(s.latitude, s.longitude)).toList();
    final bounds = LatLngBounds.fromPoints(points);

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.only(
          left: 40,
          right: 40,
          top: 40,
          bottom: 120,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;

    final initialCenter = state.validSamples.isNotEmpty
        ? LatLng(
            state.validSamples.first.latitude,
            state.validSamples.first.longitude,
          )
        : _defaultCenter;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: _currentZoom,
            minZoom: 4,
            maxZoom: 19,
            onTap: (tapPosition, point) => widget.onPointSelected(null),
            onMapReady: () {
              _mapReady = true;
              if (state.validSamples.isNotEmpty) {
                _fitRouteBounds(state.validSamples);
                _loadNodeAddresses(state.validSamples);
              }
            },
            onPositionChanged: (camera, hasGesture) {
              if (camera.zoom != _currentZoom) {
                setState(() => _currentZoom = camera.zoom);
              }
            },
          ),
          children: [
            // Map Tiles
            TileLayer(
              urlTemplate: MapTileProviders.getUrl(
                _isSatellite ? AppMapType.satellite : AppMapType.standard,
              ),
              userAgentPackageName: 'com.vmonitor.app',
              minZoom: 4,
              maxZoom: 19,
              maxNativeZoom: MapTileProviders.getMaxZoom(
                _isSatellite ? AppMapType.satellite : AppMapType.standard,
              ),
              tileProvider: NetworkTileProvider(silenceExceptions: true),
              errorImage: MemoryImage(TileProvider.transparentImage),
            ),

            // Polyline Layer cho lộ trình
            if (state.segments.isNotEmpty)
              PolylineLayer(
                polylines: HistoryMapLayers.buildPolylines(
                  segments: state.segments,
                  primaryColor: theme.colorScheme.primary,
                ),
              ),

            // Mũi tên chỉ hướng di chuyển
            if (state.segments.isNotEmpty)
              MarkerLayer(
                markers: HistoryMapLayers.buildDirectionArrows(
                  segments: state.segments,
                  currentZoom: _currentZoom,
                  arrowColor: const Color(0xFF0F172A),
                ),
              ),

            // Các mốc GPS: Start, End, trung gian
            if (state.validSamples.isNotEmpty)
              MarkerLayer(
                markers: HistoryMapLayers.buildSamplePoints(
                  validSamples: state.validSamples,
                  onPointSelected: widget.onPointSelected,
                  nodeAddresses: _nodeAddresses,
                  showLabels: _showRouteLabels,
                ),
              ),

            // Replay Device Marker
            if (state.currentPosition != null)
              MarkerLayer(
                markers: [
                  HistoryMapLayers.buildReplayMarker(
                    state: state,
                    theme: theme,
                  )!,
                ],
              ),
          ],
        ),

        // Zoom in/out & Satellite controls góc trái
        Positioned(
          left: 16,
          top: 16,
          child: _MapZoomControls(
            onZoomIn: () {
              if (!_mapReady) return;
              _mapController.move(
                _mapController.camera.center,
                _currentZoom + 1,
              );
            },
            onZoomOut: () {
              if (!_mapReady) return;
              _mapController.move(
                _mapController.camera.center,
                _currentZoom - 1,
              );
            },
            onFitBounds: () {
              if (state.validSamples.isNotEmpty) {
                _fitRouteBounds(state.validSamples);
              }
            },
            onToggleMapType: () => setState(() => _isSatellite = !_isSatellite),
            isSatellite: _isSatellite,
            onToggleLabels: () =>
                setState(() => _showRouteLabels = !_showRouteLabels),
            showLabels: _showRouteLabels,
          ),
        ),

        // Trạng thái Loading
        if (state.isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.15),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2.5),
                        SizedBox(width: 16),
                        Text(
                          'Đang tải dữ liệu GPS...',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Trạng thái Empty
        if (!state.isLoading && state.isEmpty)
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
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 16),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.route_outlined,
                        size: 48,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Không có dữ liệu vị trí trong khoảng thời gian đã chọn.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Hãy chọn khoảng thời gian khác hoặc kiểm tra lại thiết bị.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else if (!state.isLoading && state.hasSinglePoint)
          Positioned(
            top: 16,
            left: 72,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                'Chỉ có 1 mốc vị trí trong khoảng này.',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MapZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitBounds;
  final VoidCallback onToggleMapType;
  final VoidCallback onToggleLabels;
  final bool isSatellite;
  final bool showLabels;

  const _MapZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitBounds,
    required this.onToggleMapType,
    required this.onToggleLabels,
    required this.isSatellite,
    required this.showLabels,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cụm 1: Phóng to, thu nhỏ, vừa toàn bộ lộ trình
        Container(
          decoration: _boxDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.add_rounded,
                  size: 20,
                  color: Color(0xFF1677FF),
                ),
                tooltip: 'Phóng to',
                onPressed: onZoomIn,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 32, child: Divider(height: 1)),
              IconButton(
                icon: const Icon(
                  Icons.remove_rounded,
                  size: 20,
                  color: Color(0xFF1677FF),
                ),
                tooltip: 'Thu nhỏ',
                onPressed: onZoomOut,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 32, child: Divider(height: 1)),
              IconButton(
                icon: const Icon(
                  Icons.fit_screen_rounded,
                  size: 18,
                  color: Color(0xFF1677FF),
                ),
                tooltip: 'Vừa toàn bộ lộ trình',
                onPressed: onFitBounds,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Cụm 2: Kiểu bản đồ và bật/tắt nhãn node hành trình
        Container(
          decoration: _boxDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
                  size: 18,
                  color: const Color(0xFF1677FF),
                ),
                tooltip: isSatellite
                    ? 'Chuyển sang bản đồ đường phố'
                    : 'Chuyển sang bản đồ vệ tinh',
                onPressed: onToggleMapType,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 32, child: Divider(height: 1)),
              IconButton(
                icon: Icon(
                  showLabels ? Icons.label_off_rounded : Icons.label_rounded,
                  size: 18,
                  color: const Color(0xFF1677FF),
                ),
                tooltip: showLabels
                    ? 'Ẩn nhãn mốc hành trình'
                    : 'Hiện nhãn mốc hành trình',
                onPressed: onToggleLabels,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
      ],
    );
  }
}
