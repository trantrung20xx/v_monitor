// Chia lịch sử GPS thành các đoạn liên tục, tính khoảng cách/thời lượng và phân loại
// di chuyển/dừng theo ngưỡng. Kết quả được journey UI dùng để vẽ và tóm tắt.
import 'package:latlong2/latlong.dart';
import '../../data/models/location_model.dart';
import 'gps_validator.dart';

/// Đại diện cho một phân đoạn hành trình GPS liên tục (không bị đứt quãng thời gian lớn).
class RouteSegment {
  // samples giữ dữ liệu nguồn của đoạn; polylinePoints là dạng tối ưu cho flutter_map;
  // các số liệu còn lại được tính một lần khi dựng đoạn.
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
    // Không sửa list đầu vào. Chỉ tạo bản sao khi phát hiện thứ tự measuredAt chưa tăng dần.
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
        // Khoảng im lặng lớn kết thúc đoạn hiện tại; không nối đường hay cộng thời
        // lượng/quãng đường qua vùng không có dữ liệu xác nhận.
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
    // Một mẫu đơn lẻ tạo đoạn hợp lệ có quãng đường/thời lượng bằng 0.
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

      // Mỗi cặp liên tiếp đóng góp quãng đường và thời lượng đúng một lần.
      final dt = p2.measuredAt.difference(p1.measuredAt).inSeconds;
      if (dt > 0) {
        final speed = (p1.speedMps ?? p2.speedMps) ?? (dist / dt);
        // Ưu tiên tốc độ thiết bị ở hai đầu; thiếu cả hai mới dùng tốc độ suy từ
        // khoảng cách/thời gian để phân loại moving/stopped.
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
    // Fast path O(n) tránh copy/sort khi API đã trả đúng thứ tự.
    for (var i = 1; i < list.length; i++) {
      if (list[i].measuredAt.isBefore(list[i - 1].measuredAt)) {
        return false;
      }
    }
    return true;
  }
}
