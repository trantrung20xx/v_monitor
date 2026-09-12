import 'package:latlong2/latlong.dart';

import '../../data/models/device_model.dart';
import '../../domain/entities/device_status_resolver.dart';
import '../../domain/entities/gps_validator.dart';

/// Hướng hiển thị cục bộ; không ghi đè hướng GPS hoặc trạng thái từ backend.
class DeviceHeadingTracker {
  static const minimumDisplacementM = 5.0;
  static const maximumGap = Duration(minutes: 2);
  final _tracks = <String, _HeadingTrack>{};

  double? headingFor(String deviceId) => _tracks[deviceId]?.heading;

  void update(List<DeviceModel> devices) {
    final ids = <String>{};
    for (final device in devices) {
      ids.add(device.id);
      final track = _tracks.putIfAbsent(device.id, _HeadingTrack.new);
      if (identical(track.device, device)) continue;
      track.device = device;
      _updateTrack(track, device);
    }
    _tracks.removeWhere((id, _) => !ids.contains(id));
  }

  void _updateTrack(_HeadingTrack track, DeviceModel device) {
    if (!GpsValidator.isValidCoordinate(device.latitude, device.longitude)) {
      track.anchor = null;
      track.lastFix = null;
      track.heading = null;
      return;
    }
    final timestamp = device.latestMeasuredAt ?? device.lastSeenAt;
    if (timestamp != null &&
        timestamp.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      // Đồng hồ thiết bị sai không được chặn các mẫu đúng giờ đến sau.
      return;
    }
    final supplied = device.currentHeadingDeg;
    final reported =
        supplied != null && supplied.isFinite && supplied >= 0 && supplied < 360
        ? supplied
        : null;
    final fix = timestamp == null
        ? null
        : _Fix(LatLng(device.latitude!, device.longitude!), timestamp);
    final previous = track.lastFix;

    // Presence, metadata và gói cùng/cũ timestamp không tạo một đoạn đường mới.
    if (fix != null && previous != null && !fix.time.isAfter(previous.time)) {
      return;
    }
    if (fix == null) {
      track.heading ??= reported;
      return;
    }
    track.lastFix = fix;
    if (previous == null) {
      track.anchor = fix;
      track.heading = reported;
      return;
    }

    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      latestMeasuredAt: device.latestMeasuredAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );
    final canFollow =
        status.connectivity == ConnectivityStatus.online &&
        status.freshness == DataFreshnessStatus.fresh &&
        status.movement != MovementStatus.stopped;
    if (!canFollow) {
      // Xe dừng giữ hướng cuối, tránh quay qua lại theo nhiễu GPS.
      track.heading ??= reported;
      track.anchor = fix;
      return;
    }
    if (reported != null) {
      track.heading = reported;
      track.anchor = fix;
      return;
    }

    final elapsed = fix.time.difference(previous.time);
    final stepM = GpsValidator.calculateDistanceM(previous.point, fix.point);
    final speedKmh = stepM / (elapsed.inMicroseconds / 1000000) * 3.6;
    if (elapsed > maximumGap || speedKmh > GpsValidator.defaultMaxSpeedKmh) {
      // Đứt quãng hoặc nhảy GPS: lấy lại mốc, không suy hướng từ đoạn lỗi.
      track.anchor = fix;
      return;
    }
    final anchor = track.anchor ?? previous;
    if (fix.time.difference(anchor.time) > maximumGap) {
      track.anchor = fix;
      return;
    }
    final distanceM = GpsValidator.calculateDistanceM(anchor.point, fix.point);
    if (distanceM < minimumDisplacementM) return;
    track.heading = GpsValidator.calculateBearing(anchor.point, fix.point);
    track.anchor = fix;
  }
}

class _HeadingTrack {
  DeviceModel? device;
  _Fix? anchor;
  _Fix? lastFix;
  double? heading;
}

class _Fix {
  const _Fix(this.point, this.time);
  final LatLng point;
  final DateTime time;
}
