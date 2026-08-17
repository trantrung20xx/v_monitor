import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../../core/utils/device_formatters.dart';
import '../../../core/widgets/device_icon.dart';
import '../../../data/models/location_model.dart';
import '../../../domain/entities/gps_validator.dart';
import '../../../domain/entities/route_segment.dart';
import '../journey_history_state.dart';

class HistoryMapLayers {
  /// Xây dựng các lớp Polyline cho từng phân đoạn hành trình.
  static List<Polyline> buildPolylines({
    required List<RouteSegment> segments,
    required Color primaryColor,
  }) {
    final polylines = <Polyline>[];

    for (final seg in segments) {
      if (seg.samples.length < 2) continue;

      polylines.add(
        Polyline(
          points: seg.polylinePoints,
          color: primaryColor,
          strokeWidth: 4.5,
          borderColor: Colors.white.withValues(alpha: 0.9),
          borderStrokeWidth: 2.0,
        ),
      );
    }

    return polylines;
  }

  /// Xây dựng các mũi tên chỉ hướng di chuyển dọc theo từng phân đoạn hành trình.
  static List<Marker> buildDirectionArrows({
    required List<RouteSegment> segments,
    required double currentZoom,
    required Color arrowColor,
  }) {
    final markers = <Marker>[];

    // Điều chỉnh mật độ mũi tên theo zoom level (Section 23)
    final step = currentZoom >= 16
        ? 1
        : currentZoom >= 14
            ? 2
            : currentZoom >= 12
                ? 4
                : 8;

    for (final seg in segments) {
      final samples = seg.samples;
      if (samples.length < 2) continue;

      for (var i = 0; i < samples.length - 1; i += step) {
        final p1 = LatLng(samples[i].latitude, samples[i].longitude);
        final p2 = LatLng(samples[i + 1].latitude, samples[i + 1].longitude);

        final dist = GpsValidator.calculateDistanceM(p1, p2);
        // Chỉ vẽ mũi tên nếu khoảng cách đủ để xác định hướng (>= 3m)
        if (dist < 3.0) continue;

        final midPoint = GpsValidator.interpolatePosition(p1, p2, 0.5);
        final bearing = GpsValidator.calculateBearing(p1, p2);

        markers.add(
          Marker(
            point: midPoint,
            width: 18,
            height: 18,
            child: Transform.rotate(
              angle: bearing * (math.pi / 180.0),
              child: Icon(
                Icons.navigation_rounded,
                size: 14,
                color: arrowColor,
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  /// Chuyển đổi toạ độ địa lý (LatLng) sang toạ độ Pixel màn hình thế giới ở mức Zoom hiện tại
  /// để tính toán khoảng cách va chạm nhãn (Label Anti-Collision & Decluttering).
  static math.Point<double> _latLngToScreenPixel(LatLng latLng, double zoom) {
    final n = math.pow(2.0, zoom);
    final x = ((latLng.longitude + 180.0) / 360.0) * n * 256.0;
    final latRad = latLng.latitude * math.pi / 180.0;
    final y = (1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * n * 256.0;
    return math.Point<double>(x, y);
  }

  /// Xây dựng các Marker Start, End và các điểm nút GPS với nhãn mốc thời gian đầy đủ
  /// (cả Ngày/Tháng/Năm + Giờ:Phút:Giây) theo chuẩn Google Maps Waypoints
  /// và thuật toán Anti-Collision (không chồng chéo, không che lấp nhau).
  static List<Marker> buildSamplePoints({
    required List<LocationModel> validSamples,
    required ValueChanged<LocationModel> onPointSelected,
    required ThemeData theme,
    required double currentZoom,
  }) {
    if (validSamples.isEmpty) return const [];

    final markers = <Marker>[];

    final dateFormat = DateFormat('dd/MM/yyyy');
    final timeFormat = DateFormat('HH:mm:ss');

    final labeledScreenPixels = <math.Point<double>>[];
    const minPixelSpacing = 95.0; // Khoảng cách pixel tối thiểu giữa 2 nhãn text trên màn hình

    // 1. Điểm BẮT ĐẦU (Start - Green Pin)
    final start = validSamples.first;
    final startDt = start.measuredAt.toLocal();
    final startPix = _latLngToScreenPixel(LatLng(start.latitude, start.longitude), currentZoom);
    labeledScreenPixels.add(startPix);

    markers.add(
      Marker(
        point: LatLng(start.latitude, start.longitude),
        width: 140,
        height: 52,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: () => onPointSelected(start),
          child: _buildGoogleStyleMarker(
            title: 'Bắt đầu',
            dateText: dateFormat.format(startDt),
            timeText: timeFormat.format(startDt),
            color: const Color(0xFF16A34A),
            icon: Icons.play_arrow_rounded,
          ),
        ),
      ),
    );

    // 2. Điểm KẾT THÚC (End - Red Pin) nếu có >= 2 điểm
    math.Point<double>? endPix;
    if (validSamples.length >= 2) {
      final end = validSamples.last;
      final endDt = end.measuredAt.toLocal();
      endPix = _latLngToScreenPixel(LatLng(end.latitude, end.longitude), currentZoom);

      markers.add(
        Marker(
          point: LatLng(end.latitude, end.longitude),
          width: 140,
          height: 52,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => onPointSelected(end),
            child: _buildGoogleStyleMarker(
              title: 'Kết thúc',
              dateText: dateFormat.format(endDt),
              timeText: timeFormat.format(endDt),
              color: const Color(0xFFDC2626),
              icon: Icons.flag_rounded,
            ),
          ),
        ),
      );
    }

    // 3. Các điểm NÚT TRUNG GIAN với Thuật toán Thông minh Chống Chồng Chéo (Anti-Collision)
    if (validSamples.length > 2) {
      for (var i = 1; i < validSamples.length - 1; i++) {
        final sample = validSamples[i];
        final sampleDt = sample.measuredAt.toLocal();
        final sampleCoord = LatLng(sample.latitude, sample.longitude);
        final samplePix = _latLngToScreenPixel(sampleCoord, currentZoom);

        // Kiểm tra khoảng cách pixel tới điểm kết thúc
        if (endPix != null) {
          final distToEnd = samplePix.distanceTo(endPix);
          if (distToEnd < minPixelSpacing * 0.85) {
            // Quá gần điểm kết thúc -> chỉ vẽ dot nhỏ, không vẽ text
            markers.add(_buildDotMarker(sample, onPointSelected, theme));
            continue;
          }
        }

        // Kiểm tra khoảng cách pixel tới tất cả các nhãn đã vẽ trước đó
        var isColliding = false;
        for (final p in labeledScreenPixels) {
          if (samplePix.distanceTo(p) < minPixelSpacing) {
            isColliding = true;
            break;
          }
        }

        final isStopped = (sample.speedMps ?? 0) < 0.5;

        if (!isColliding) {
          // Điểm nút đủ khoảng cách -> Vẽ nhãn Timestamp Badge Google Maps Style với cả Ngày & Giờ
          labeledScreenPixels.add(samplePix);

          markers.add(
            Marker(
              point: sampleCoord,
              width: 88,
              height: 44,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: () => onPointSelected(sample),
                child: _buildWaypointTimeBadge(
                  dateText: dateFormat.format(sampleDt),
                  timeText: timeFormat.format(sampleDt),
                  isStopped: isStopped,
                  theme: theme,
                ),
              ),
            ),
          );
        } else {
          // Điểm bị chồng chéo text -> Vẽ dot tròn nhỏ gọn để người dùng vẫn thấy quỹ đạo
          if (currentZoom >= 13) {
            markers.add(_buildDotMarker(sample, onPointSelected, theme));
          }
        }
      }
    }

    return markers;
  }

  /// Marker Dot nhỏ gọn cho các điểm mẫu GPS không gắn nhãn text (tránh rối bản đồ)
  static Marker _buildDotMarker(
    LocationModel sample,
    ValueChanged<LocationModel> onPointSelected,
    ThemeData theme,
  ) {
    return Marker(
      point: LatLng(sample.latitude, sample.longitude),
      width: 12,
      height: 12,
      child: GestureDetector(
        onTap: () => onPointSelected(sample),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: theme.colorScheme.primary, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }

  /// Nhãn mốc thời gian điểm nút (Waypoint Badge) chuẩn phong cách Google Maps
  /// hiển thị gọn gàng cả Ngày/Tháng/Năm và Giờ:Phút:Giây
  static Widget _buildWaypointTimeBadge({
    required String dateText,
    required String timeText,
    required bool isStopped,
    required ThemeData theme,
  }) {
    final badgeColor = isStopped ? const Color(0xFFD97706) : theme.colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1.5)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Dòng 1: Ngày tháng năm
              Text(
                dateText,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 1),
              // Dòng 2: Dot trạng thái + Giờ:Phút:Giây
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    timeText,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Chân định vị nhỏ gắn vào tâm toạ độ
        CustomPaint(
          size: const Size(6, 4),
          painter: _PinTipPainter(const Color(0xFFCBD5E1)),
        ),
      ],
    );
  }

  /// Marker Bắt đầu / Kết thúc nổi bật hiển thị đầy đủ Ngày & Giờ
  static Widget _buildGoogleStyleMarker({
    required String title,
    required String dateText,
    required String timeText,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 12, color: Colors.white),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      '$title · $dateText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              Text(
                timeText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
        CustomPaint(
          size: const Size(8, 5),
          painter: _PinTipPainter(color),
        ),
      ],
    );
  }

  /// Marker cho Replay chuyển động của thiết bị
  static Marker? buildReplayMarker({
    required JourneyHistoryState state,
    required ThemeData theme,
  }) {
    if (state.currentPosition == null) return null;

    final deviceType = state.selectedDevice?.deviceType ?? 'VEHICLE';
    final heading = state.currentHeadingDeg ?? 0.0;
    final speed = state.currentSpeedMps;
    final time = state.currentReplayTime;

    return Marker(
      point: state.currentPosition!,
      width: 140,
      height: 72,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tag thời gian & tốc độ đang phát lại
          if (time != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(5),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Text(
                '${DateFormat('dd/MM/yyyy HH:mm:ss').format(time.toLocal())} · ${DeviceFormatters.speedMps(speed)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(height: 2),
          // Icon thiết bị xoay theo heading
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Transform.rotate(
              angle: heading * (math.pi / 180.0),
              child: Icon(
                DeviceIcon.iconFor(deviceType),
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinTipPainter extends CustomPainter {
  final Color color;
  _PinTipPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
