import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/models/device_model.dart';
import '../device_position_animator.dart';
import 'device_icon_canvas.dart';
import 'device_map_icon.dart';

/// Dựng từng thiết bị trong vùng nhìn.
class DeviceMarkerLayer extends StatefulWidget {
  const DeviceMarkerLayer({
    super.key,
    required this.devices,
    required this.markerBuilder,
  });
  final List<DeviceModel> devices;
  final DeviceMapMarker Function(BuildContext, DeviceModel) markerBuilder;

  @override
  State<DeviceMarkerLayer> createState() => _DeviceMarkerLayerState();
}

class _DeviceMarkerLayerState extends State<DeviceMarkerLayer>
    with SingleTickerProviderStateMixin {
  static const _viewportMargin = 140.0;
  static const _normalFrameInterval = Duration(milliseconds: 33);
  static const _largeFleetFrameInterval = Duration(milliseconds: 66);

  List<DeviceMapMarker>? _icons;
  List<LatLng>? _displayPoints;
  ThemeData? _theme;
  bool? _reduceMotion;
  final DevicePositionAnimator _positions = DevicePositionAnimator();
  late final Ticker _ticker;
  Duration _lastAnimatedFrame = Duration.zero;
  Duration _lastPositionSample = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(DeviceMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Snapshot, trạng thái theo thời gian hoặc cấu hình đổi đều dựng lại mô tả.
    _icons = null;
    _displayPoints = null;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Duration get _frameInterval => (_icons?.length ?? 0) > 1000
      ? _largeFleetFrameInterval
      : _normalFrameInterval;

  Duration get _frameTime => SchedulerBinding.instance.currentFrameTimeStamp;

  void _onTick(Duration _) {
    if (!mounted) return;
    final now = _frameTime;
    final active = _positions.hasActive(now);
    if (!active || now - _lastAnimatedFrame >= _frameInterval) {
      _lastAnimatedFrame = now;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final theme = Theme.of(context);
    if (_theme != theme) {
      _theme = theme;
      _icons = null;
      _displayPoints = null;
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion != reduceMotion) {
      _reduceMotion = reduceMotion;
      _icons = null;
      _displayPoints = null;
    }
    // Kéo/zoom chỉ chiếu lại tọa độ, không phân giải trạng thái 5.000 lần mỗi khung.
    final shouldSyncPositions = _icons == null;
    final icons = _icons ??= [
      for (final device in widget.devices)
        if (device.latitude != null && device.longitude != null)
          widget.markerBuilder(context, device),
    ];
    final origin = camera.pixelOrigin;
    final size = camera.size;
    final now = _frameTime;
    if (shouldSyncPositions) {
      final liveIds = <String>{};
      for (final icon in icons) {
        liveIds.add(icon.id);
        final target = camera.project(icon.point);
        final x = target.x - origin.x;
        final y = target.y - origin.y;
        final targetNearViewport =
            x >= -_viewportMargin &&
            y >= -_viewportMargin &&
            x <= size.x + _viewportMargin &&
            y <= size.y + _viewportMargin;
        _positions.update(
          id: icon.id,
          target: icon.point,
          sampleTime: icon.positionTimestamp,
          now: now,
          animate: icon.animatePosition && targetNearViewport && !reduceMotion,
        );
      }
      _positions.retainOnly(liveIds);
    }

    final hasActiveMotion = _positions.hasActive(now);
    final shouldSamplePositions =
        _displayPoints == null ||
        _displayPoints!.length != icons.length ||
        (hasActiveMotion && now - _lastPositionSample >= _frameInterval) ||
        (!hasActiveMotion && _ticker.isActive);
    if (shouldSamplePositions) {
      _lastPositionSample = now;
      _displayPoints = [
        for (final icon in icons) _positions.positionFor(icon.id, now),
      ];
    }

    final markers = <ProjectedDeviceMarker>[];
    for (var index = 0; index < icons.length; index++) {
      final icon = icons[index];
      final point = camera.project(_displayPoints![index]);
      final x = point.x - origin.x;
      final y = point.y - origin.y;
      if (x < -_viewportMargin ||
          y < -_viewportMargin ||
          x > size.x + _viewportMargin ||
          y > size.y + _viewportMargin) {
        continue;
      }
      markers.add(ProjectedDeviceMarker(icon, Offset(x, y)));
    }
    if (hasActiveMotion) {
      if (!_ticker.isActive) {
        _lastAnimatedFrame = now;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
    return MobileLayerTransformer(
      child: RepaintBoundary(child: DeviceIconCanvas(markers: markers)),
    );
  }
}

/// Marker đơn lẻ dùng cùng quy tắc nội suy nhưng chỉ rebuild lớp marker.
/// Tile và các card xung quanh không bị dựng lại theo từng khung chuyển động.
class AnimatedDeviceMarkerLayer extends StatefulWidget {
  const AnimatedDeviceMarkerLayer({
    super.key,
    required this.id,
    required this.target,
    required this.positionTimestamp,
    required this.animate,
    required this.child,
  });

  final String id;
  final LatLng target;
  final DateTime? positionTimestamp;
  final bool animate;
  final Widget child;

  @override
  State<AnimatedDeviceMarkerLayer> createState() =>
      _AnimatedDeviceMarkerLayerState();
}

class _AnimatedDeviceMarkerLayerState extends State<AnimatedDeviceMarkerLayer>
    with SingleTickerProviderStateMixin {
  static const _frameInterval = Duration(milliseconds: 33);
  final DevicePositionAnimator _positions = DevicePositionAnimator();
  late final Ticker _ticker;
  Duration _lastAnimatedFrame = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Duration get _frameTime => SchedulerBinding.instance.currentFrameTimeStamp;

  void _onTick(Duration _) {
    if (!mounted) return;
    final now = _frameTime;
    final active = _positions.hasActive(now);
    if (!active || now - _lastAnimatedFrame >= _frameInterval) {
      _lastAnimatedFrame = now;
      setState(() {});
    }
    if (!active) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final now = _frameTime;
    _positions
      ..retainOnly({widget.id})
      ..update(
        id: widget.id,
        target: widget.target,
        sampleTime: widget.positionTimestamp,
        now: now,
        animate: widget.animate && !MediaQuery.disableAnimationsOf(context),
      );
    final point = _positions.positionFor(widget.id, now);
    if (_positions.hasActive(now)) {
      if (!_ticker.isActive) {
        _lastAnimatedFrame = now;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }

    return RepaintBoundary(
      child: MarkerLayer(
        markers: [
          Marker(
            point: point,
            width: DeviceMapIcon.touchSize,
            height: DeviceMapIcon.touchSize,
            alignment: Alignment.center,
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
