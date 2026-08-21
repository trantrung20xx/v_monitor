import 'package:latlong2/latlong.dart';
import '../../data/models/location_model.dart';
import 'gps_validator.dart';

/// Đại diện cho một phân đoạn hành trình GPS liên tục (không bị đứt quãng thời gian lớn).
class RouteSegment {
  final List<LocationModel> samples;
  final List<LatLng> polylinePoints;
  final double distanceM;
  final int movingDurationS;
  final int stoppedDurationS;
  final double? maxSpeedMps;
  final double? avgSpeedMps;

  RouteSegment({
    required this.samples,
    List<LatLng>? polylinePoints,
    required this.distanceM,
    required this.movingDurationS,
    required this.stoppedDurationS,
    this.maxSpeedMps,
    this.avgSpeedMps,
  }) : polylinePoints = polylinePoints ??
            samples.map((s) => LatLng(s.latitude, s.longitude)).toList(growable: false);

  DateTime get startedAt => samples.first.measuredAt;
  DateTime get endedAt => samples.last.measuredAt;
  int get sampleCount => samples.length;

  /// Tách danh sách mẫu GPS thành các phân đoạn hành trình dựa trên ngưỡng gián đoạn thời gian (gap threshold).
  static List<RouteSegment> splitIntoSegments(
    List<LocationModel> samples, {
    Duration gapThreshold = const Duration(minutes: 5),
    double movingThresholdMps = 0.5,
  }) {
    if (samples.isEmpty) return const [];

    final isSorted = _isChronologicallySorted(samples);
    final sorted = isSorted
        ? samples
        : (List<LocationModel>.from(samples)
          ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt)));

    final segments = <RouteSegment>[];
    var currentGroup = <LocationModel>[sorted.first];

    for (var i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final curr = sorted[i];

      final diff = curr.measuredAt.difference(prev.measuredAt);

      if (diff > gapThreshold) {
        // Hoàn thành segment hiện tại
        if (currentGroup.isNotEmpty) {
          segments.add(_buildSegment(currentGroup, movingThresholdMps));
        }
        currentGroup = [curr];
      } else {
        currentGroup.add(curr);
      }
    }

    if (currentGroup.isNotEmpty) {
      segments.add(_buildSegment(currentGroup, movingThresholdMps));
    }

    return segments;
  }

  static RouteSegment _buildSegment(
    List<LocationModel> items,
    double movingThresholdMps,
  ) {
    if (items.length < 2) {
      return RouteSegment(
        samples: items,
        distanceM: 0.0,
        movingDurationS: 0,
        stoppedDurationS: 0,
        maxSpeedMps: items.first.speedMps,
        avgSpeedMps: items.first.speedMps,
      );
    }

    var totalDistance = 0.0;
    var movingSeconds = 0;
    var stoppedSeconds = 0;
    var maxSpeed = 0.0;
    var speedSum = 0.0;
    var speedCount = 0;

    for (var i = 1; i < items.length; i++) {
      final p1 = items[i - 1];
      final p2 = items[i];

      final dist = GpsValidator.calculateDistanceM(
        LatLng(p1.latitude, p1.longitude),
        LatLng(p2.latitude, p2.longitude),
      );
      totalDistance += dist;

      final dt = p2.measuredAt.difference(p1.measuredAt).inSeconds;
      if (dt > 0) {
        final speed = (p1.speedMps ?? p2.speedMps) ?? (dist / dt);
        final isMoving = (p1.speedMps != null && p1.speedMps! > movingThresholdMps) ||
            (p2.speedMps != null && p2.speedMps! > movingThresholdMps) ||
            ((dist / dt) > movingThresholdMps);
        if (isMoving) {
          movingSeconds += dt;
        } else {
          stoppedSeconds += dt;
        }

        if (speed > maxSpeed) maxSpeed = speed;
        speedSum += speed;
        speedCount++;
      }
    }

    final points = items
        .map((s) => LatLng(s.latitude, s.longitude))
        .toList(growable: false);

    return RouteSegment(
      samples: items,
      polylinePoints: points,
      distanceM: totalDistance,
      movingDurationS: movingSeconds,
      stoppedDurationS: stoppedSeconds,
      maxSpeedMps: speedCount > 0 ? maxSpeed : null,
      avgSpeedMps: speedCount > 0 ? (speedSum / speedCount) : null,
    );
  }

  static bool _isChronologicallySorted(List<LocationModel> list) {
    for (var i = 1; i < list.length; i++) {
      if (list[i].measuredAt.isBefore(list[i - 1].measuredAt)) {
        return false;
      }
    }
    return true;
  }
}
