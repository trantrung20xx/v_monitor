import 'package:latlong2/latlong.dart';

import '../../domain/entities/gps_validator.dart';

/// Nội suy giữa hai vị trí GPS đã được backend xác nhận.
///
/// Lớp này không dự đoán vị trí theo tốc độ/hướng. Khi hết khoảng chuyển tiếp,
/// marker luôn dừng đúng tại tọa độ mới nhất trong payload realtime.
class DevicePositionAnimator {
  static const minimumTransition = Duration(milliseconds: 250);
  static const defaultTransition = Duration(milliseconds: 750);
  static const maximumTransition = Duration(seconds: 3);
  static const maximumSampleGap = Duration(minutes: 2);
  static const minimumDisplacementM = 0.75;

  final Map<String, _PositionTrack> _tracks = {};

  void update({
    required String id,
    required LatLng target,
    required DateTime? sampleTime,
    required Duration now,
    required bool animate,
  }) {
    final track = _tracks[id];
    if (track == null) {
      _tracks[id] = _PositionTrack(target: target, sampleTime: sampleTime);
      return;
    }

    if (_samePoint(track.target, target)) {
      if (sampleTime != null &&
          (track.sampleTime == null ||
              !sampleTime.isBefore(track.sampleTime!))) {
        track.sampleTime = sampleTime;
      }
      if (!animate && track.isActive(now)) track.snapToTarget();
      return;
    }

    final previousTarget = track.target;
    final previousSampleTime = track.sampleTime;
    final currentPosition = track.positionAt(now);
    final sampleGap = sampleTime != null && previousSampleTime != null
        ? sampleTime.difference(previousSampleTime)
        : null;
    final distanceM = GpsValidator.calculateDistanceM(previousTarget, target);
    final validGap =
        sampleGap == null ||
        (sampleGap >= Duration.zero && sampleGap <= maximumSampleGap);
    final plausibleSpeed = sampleGap == null || sampleGap <= Duration.zero
        ? true
        : distanceM / (sampleGap.inMicroseconds / 1000000) * 3.6 <=
              GpsValidator.defaultMaxSpeedKmh;
    final shouldAnimate =
        animate &&
        distanceM >= minimumDisplacementM &&
        validGap &&
        plausibleSpeed;

    final nextSampleTime =
        sampleTime != null &&
            (previousSampleTime == null ||
                !sampleTime.isBefore(previousSampleTime))
        ? sampleTime
        : previousSampleTime;
    track
      ..sampleTime = nextSampleTime
      ..target = target;
    if (!shouldAnimate) {
      track.snapToTarget();
      return;
    }

    track
      ..from = currentPosition
      ..startedAt = now
      ..duration = _transitionFor(sampleGap);
  }

  LatLng positionFor(String id, Duration now) =>
      _tracks[id]?.positionAt(now) ?? const LatLng(0, 0);

  bool hasActive(Duration now) =>
      _tracks.values.any((track) => track.isActive(now));

  void retainOnly(Set<String> ids) {
    _tracks.removeWhere((id, _) => !ids.contains(id));
  }

  static Duration _transitionFor(Duration? sampleGap) {
    if (sampleGap == null || sampleGap <= Duration.zero) {
      return defaultTransition;
    }
    return Duration(
      microseconds: sampleGap.inMicroseconds.clamp(
        minimumTransition.inMicroseconds,
        maximumTransition.inMicroseconds,
      ),
    );
  }

  static bool _samePoint(LatLng a, LatLng b) =>
      a.latitude == b.latitude && a.longitude == b.longitude;
}

class _PositionTrack {
  _PositionTrack({required this.target, required this.sampleTime})
    : from = target;

  LatLng from;
  LatLng target;
  DateTime? sampleTime;
  Duration startedAt = Duration.zero;
  Duration duration = Duration.zero;

  bool isActive(Duration now) =>
      duration > Duration.zero && now - startedAt < duration;

  LatLng positionAt(Duration now) {
    if (!isActive(now)) return target;
    final elapsed = now - startedAt;
    final progress = elapsed.inMicroseconds / duration.inMicroseconds;
    return GpsValidator.interpolatePosition(from, target, progress);
  }

  void snapToTarget() {
    from = target;
    duration = Duration.zero;
  }
}
