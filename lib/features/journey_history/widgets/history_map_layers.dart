import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

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

  /// Xây dựng các Marker Start, End và các điểm mẫu GPS có thể tap
  static List<Marker> buildSamplePoints({
    required List<LocationModel> validSamples,
    required ValueChanged<LocationModel> onPointSelected,
    required ThemeData theme,
    required double currentZoom,
  }) {
    if (validSamples.isEmpty) return const [];

    final markers = <Marker>[];

    // Điểm BẮT ĐẦU (Start - Green)
    final start = validSamples.first;
    markers.add(
      Marker(
        point: LatLng(start.latitude, start.longitude),
        width: 90,
        height: 52,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: () => onPointSelected(start),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_circle_fill_rounded, size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      'Bắt đầu ${DateFormat('HH:mm').format(start.measuredAt.toLocal())}',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF16A34A)),
            ],
          ),
        ),
      ),
    );

    // Điểm KẾT THÚC (End - Red) nếu có >= 2 điểm
    if (validSamples.length >= 2) {
      final end = validSamples.last;
      markers.add(
        Marker(
          point: LatLng(end.latitude, end.longitude),
          width: 90,
          height: 52,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => onPointSelected(end),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stop_circle_rounded, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'Kết thúc ${DateFormat('HH:mm').format(end.measuredAt.toLocal())}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFFDC2626)),
              ],
            ),
          ),
        ),
      );
    }

    // Các điểm GPS mẫu trung gian (chỉ hiển thị dot khi zoom đủ lớn để tối ưu hiệu năng) (Section 39 & 40)
    if (currentZoom >= 14 && validSamples.length > 2) {
      final sampleStep = currentZoom >= 16 ? 1 : 3;
      for (var i = 1; i < validSamples.length - 1; i += sampleStep) {
        final sample = validSamples[i];
        markers.add(
          Marker(
            point: LatLng(sample.latitude, sample.longitude),
            width: 14,
            height: 14,
            child: GestureDetector(
              onTap: () => onPointSelected(sample),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.primary, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 2),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  /// Xây dựng Marker cho Replay chuyển động của thiết bị
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
                color: const Color(0xFF0F172A).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(4),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Text(
                '${DateFormat('HH:mm:ss').format(time.toLocal())} · ${DeviceFormatters.speedMps(speed)}',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
