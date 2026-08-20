import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../../data/models/location_model.dart';

/// Lớp kiểm định tính hợp lệ của dữ liệu GPS và phát hiện dữ liệu lỗi/nhảy vọt (outlier).
class GpsValidator {
  static const double defaultMaxSpeedKmh = 500.0;
  static const Distance _distance = Distance();

  /// Kiểm tra toạ độ địa lý có nằm trong giới hạn chuẩn toàn cầu (-90..90, -180..180)
  /// và không phải là NaN / Infinity.
  static bool isValidCoordinate(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return false;
    if (latitude.isNaN || latitude.isInfinite) return false;
    if (longitude.isNaN || longitude.isInfinite) return false;
    if (latitude < -90.0 || latitude > 90.0) return false;
    if (longitude < -180.0 || longitude > 180.0) return false;
    // Điểm (0,0) thường là GPS chưa fix được toạ độ ở các module giá rẻ (Null Island)
    if (latitude == 0.0 && longitude == 0.0) return false;
    return true;
  }

  /// Kiểm tra xem một sample có toạ độ hợp lệ hay không.
  static bool isValidSample(LocationModel sample) {
    return isValidCoordinate(sample.latitude, sample.longitude);
  }

  /// Loại các tọa độ GPS sai hoặc điểm nhảy vị trí bất thường khỏi lộ trình.
  /// Lưu ý: Không làm mất dữ liệu gốc, chỉ trả về danh sách điểm hợp lệ phục vụ render/replay.
  static List<LocationModel> sanitizeSamples(
    List<LocationModel> rawSamples, {
    double maxSpeedKmh = defaultMaxSpeedKmh,
  }) {
    if (rawSamples.isEmpty) return const [];

    // 1. Sắp xếp tăng dần theo measuredAt và lọc toạ độ cơ bản
    final sorted = List<LocationModel>.from(rawSamples)
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));

    final validCoords = sorted.where(isValidSample).toList();
    if (validCoords.length <= 2) return validCoords;

    final sanitized = <LocationModel>[validCoords.first];

    for (var i = 1; i < validCoords.length; i++) {
      final prev = sanitized.last;
      final curr = validCoords[i];

      final timeDeltaSeconds = curr.measuredAt.difference(prev.measuredAt).inSeconds;
      
      // Nếu 2 mẫu cùng 1 timestamp chính xác
      if (timeDeltaSeconds <= 0) {
        // Giữ lại mẫu nếu toạ độ thay đổi rất nhỏ hoặc cùng điểm
        continue;
      }

      final distM = _distance.as(
        LengthUnit.Meter,
        LatLng(prev.latitude, prev.longitude),
        LatLng(curr.latitude, curr.longitude),
      );

      final impliedSpeedKmh = (distM / timeDeltaSeconds) * 3.6;

      // Nếu tốc độ suy diễn > ngưỡng (ví dụ 500 km/h) trong khoảng thời gian ngắn -> nghi ngờ teleport jump
      if (impliedSpeedKmh > maxSpeedKmh && timeDeltaSeconds < 300) {
        // Kiểm tra xem có phải là 1 điểm đột biến đơn lẻ (spike) không
        if (i + 1 < validCoords.length) {
          final next = validCoords[i + 1];
          final nextDistM = _distance.as(
            LengthUnit.Meter,
            LatLng(prev.latitude, prev.longitude),
            LatLng(next.latitude, next.longitude),
          );
          final nextTimeDelta = next.measuredAt.difference(prev.measuredAt).inSeconds;
          if (nextTimeDelta > 0) {
            final nextImpliedSpeed = (nextDistM / nextTimeDelta) * 3.6;
            // Nếu điểm tiếp theo lại quay về gần prev thì curr chắc chắn là spike lỗi
            if (nextImpliedSpeed <= maxSpeedKmh) {
              continue; // Bỏ qua điểm đột biến curr
            }
          }
        }
      }

      sanitized.add(curr);
    }

    return sanitized;
  }

  /// Tính góc phương vị (Bearing / Azimuth) giữa 2 điểm toạ độ trên mặt cầu trái đất (0° .. 360°).
  /// 0° = Bắc, 90° = Đông, 180° = Nam, 270° = Tây.
  static double calculateBearing(LatLng start, LatLng end) {
    final lat1 = _degToRad(start.latitude);
    final lon1 = _degToRad(start.longitude);
    final lat2 = _degToRad(end.latitude);
    final lon2 = _degToRad(end.longitude);

    final dLon = lon2 - lon1;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final rad = math.atan2(y, x);
    final deg = _radToDeg(rad);
    return (deg + 360.0) % 360.0;
  }

  /// Tính khoảng cách mét giữa 2 điểm toạ độ.
  static double calculateDistanceM(LatLng a, LatLng b) {
    return _distance.as(LengthUnit.Meter, a, b);
  }

  /// Nội suy vị trí địa lý giữa 2 điểm GPS dựa trên tỉ lệ thời gian t (0.0 .. 1.0).
  static LatLng interpolatePosition(LatLng p1, LatLng p2, double t) {
    final clampedT = t.clamp(0.0, 1.0);
    final lat = p1.latitude + (p2.latitude - p1.latitude) * clampedT;
    final lng = p1.longitude + (p2.longitude - p1.longitude) * clampedT;
    return LatLng(lat, lng);
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
  static double _radToDeg(double rad) => rad * (180.0 / math.pi);
}
