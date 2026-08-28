// Các lớp vẽ bản đồ lịch sử: polyline theo đoạn, node đầu/cuối/dừng, marker playback
// và popup điểm. Tọa độ đầu vào đã được domain kiểm tra trước.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/device_formatters.dart';
import '../../../core/widgets/device_icon.dart';
import '../../../data/models/location_model.dart';
import '../../../domain/entities/device_status_resolver.dart';
import '../../../domain/entities/gps_validator.dart';
import '../../../domain/entities/route_segment.dart';
import '../journey_history_state.dart';

/// Đại diện cho một điểm Dừng hoặc Đỗ xe được gom cụm tự động từ chuỗi toạ độ GPS.
// Điểm dừng suy ra từ chuỗi mẫu liên tiếp dưới ngưỡng chuyển động; không phải bản
// ghi DeviceEvent được lưu ở backend.
class JourneyStopPoint {
  const JourneyStopPoint({
    required this.sample,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.isPark,
  });

  final LocationModel sample;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds;

  /// Là điểm Đỗ xe (Park) nếu thời gian đứng yên liên tục từ 5 phút (300s) trở lên.
  final bool isPark;

  /// Nhãn thời lượng đỗ đầy đủ (ví dụ: "45 phút", "1 giờ 15 phút").
  String get durationLabel {
    if (durationSeconds >= 3600) {
      final hours = durationSeconds ~/ 3600;
      final mins = (durationSeconds % 3600) ~/ 60;
      if (mins == 0) return '$hours giờ';
      return '$hours giờ $mins phút';
    }
    final mins = durationSeconds ~/ 60;
    if (mins == 0) return '$durationSeconds giây';
    return '$mins phút';
  }

  /// Nhãn thời lượng đỗ rút gọn cho nhãn trên bản đồ (ví dụ: "45p", "1h15p").
  String get compactDurationLabel {
    if (durationSeconds >= 3600) {
      final hours = durationSeconds ~/ 3600;
      final mins = (durationSeconds % 3600) ~/ 60;
      if (mins == 0) return '${hours}h';
      return '${hours}h${mins}p';
    }
    final mins = durationSeconds ~/ 60;
    if (mins == 0) return '${durationSeconds}s';
    return '${mins}p';
  }
}

// Loại nút trình bày trên tuyến: đầu, điểm giữa có nhãn, điểm dừng và cuối.
enum JourneyRouteNodeType { start, place, park, end }

// Model trình bày một node trên bản đồ, giữ sample nguồn và nhãn địa chỉ tùy chọn.
class JourneyRouteNode {
  const JourneyRouteNode({
    required this.sample,
    required this.type,
    this.stopPoint,
  });

  final LocationModel sample;
  final JourneyRouteNodeType type;
  final JourneyStopPoint? stopPoint;
}

// Bộ dựng các layer flutter_map cho hành trình: polyline từng đoạn, mũi tên hướng,
// marker đầu/cuối/dừng, điểm playback và nhãn địa chỉ.
class HistoryMapLayers {
  /// Tính chiều rộng lõi lộ trình tự co giãn theo mức thu phóng.
  /// Giúp lộ trình khi thu nhỏ không bị to đùng và khi phóng to đường phố không bị quá mảnh.
  static double getPolylineCoreWidth(double zoom) {
    if (zoom >= 18) return 8.0;
    if (zoom >= 16) return 6.5;
    if (zoom >= 14) return 5.0;
    if (zoom >= 12) return 3.8;
    if (zoom >= 10) return 2.8;
    return 2.0;
  }

  /// Tính toán chiều rộng lớp viền ngoài (Casing / Glow halo).
  static double getPolylineCasingWidth(double zoom) {
    final core = getPolylineCoreWidth(zoom);
    return core + (zoom >= 14 ? 3.0 : 2.0);
  }

  /// Xây dựng các lớp Polyline cho từng phân đoạn hành trình
  /// với độ rộng thích ứng theo mức Zoom và viền Casing 2 lớp sắc nét.
  static List<Polyline> buildPolylines({
    required List<RouteSegment> segments,
    required Color primaryColor,
    double currentZoom = 14.0,
  }) {
    final polylines = <Polyline>[];
    final coreWidth = getPolylineCoreWidth(currentZoom);
    final casingWidth = getPolylineCasingWidth(currentZoom);

    for (final seg in segments) {
      // Một polyline cần tối thiểu hai tọa độ; đoạn rỗng hoặc một điểm không tạo thành đường.
      if (seg.samples.length < 2) continue;

      // 1. Lớp viền nền ngoài (Outer Casing) tạo độ tương phản cao trên mọi lớp bản đồ
      polylines.add(
        Polyline(
          points: seg.polylinePoints,
          color: AppPalette.onAccent.withValues(alpha: 0.94),
          strokeWidth: casingWidth,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      );

      // 2. Lớp đường lộ trình chính (Core Path) xanh nổi bật
      polylines.add(
        Polyline(
          points: seg.polylinePoints,
          color: primaryColor,
          strokeWidth: coreWidth,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      );
    }

    return polylines;
  }

  /// Nối hai phân đoạn bị ngắt bằng nét đứt để người dùng hiểu đây là khoảng
  /// không có dữ liệu, không phải quãng đường GPS đã ghi nhận chính xác.
  static List<Polyline> buildGapPolylines({
    required List<RouteSegment> segments,
    double currentZoom = 14.0,
    Color? gapColor,
  }) {
    if (segments.length < 2) return const [];

    final gapWidth = (getPolylineCoreWidth(currentZoom) * 0.72).clamp(2.0, 4.5);
    final gaps = <Polyline>[];

    for (var i = 0; i < segments.length - 1; i++) {
      final current = segments[i];
      final next = segments[i + 1];
      if (current.samples.isEmpty || next.samples.isEmpty) continue;

      gaps.add(
        Polyline(
          points: [
            LatLng(
              current.samples.last.latitude,
              current.samples.last.longitude,
            ),
            LatLng(next.samples.first.latitude, next.samples.first.longitude),
          ],
          color: (gapColor ?? AppThemeColors.light.textSecondary).withValues(
            alpha: 0.72,
          ),
          strokeWidth: gapWidth,
          pattern: StrokePattern.dashed(segments: const [7, 7]),
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      );
    }

    return gaps;
  }

  /// Xây dựng các mũi tên chỉ hướng di chuyển dạng Chevron (^) đâm về hướng đi.
  /// Kích thước mũi tên được đồng bộ tỷ lệ với lòng đường lộ trình (không bị to bè ra ngoài).
  static List<Marker> buildDirectionArrows({
    required List<RouteSegment> segments,
    required double currentZoom,
    required Color arrowColor,
  }) {
    final markers = <Marker>[];

    // Chỉ hiển thị mũi tên khi zoom từ 11.5 trở lên để tránh rối mắt ở mức xem toàn cảnh
    if (currentZoom < 11.5) return markers;

    final coreWidth = getPolylineCoreWidth(currentZoom);
    // Kích thước mũi tên vừa vặn trong lòng đường lộ trình
    final arrowSize = (coreWidth * 1.35).clamp(6.0, 13.0);

    // Khoảng cách mét mục tiêu giữa các mũi tên theo mức zoom
    final targetDistanceM = currentZoom >= 17
        ? 35.0
        : currentZoom >= 15
        ? 70.0
        : currentZoom >= 13
        ? 140.0
        : 280.0;

    const maxArrowCount = 120;

    for (final seg in segments) {
      // Giới hạn tổng marker để hành trình dài không tạo quá nhiều widget trên bản đồ.
      if (markers.length >= maxArrowCount) return markers;
      final samples = seg.samples;
      if (samples.length < 2) continue;

      // Ghi số marker ban đầu để nhận biết đoạn ngắn chưa tạo được ký hiệu hướng.
      final segmentMarkerStart = markers.length;
      // Mũi tên đầu tiên nằm gần nửa khoảng cách chuẩn, tránh dồn sát đầu đoạn.
      var distanceUntilNextArrow = targetDistanceM * 0.55;
      ({LatLng start, LatLng end, double distance, double bearing})?
      longestEdge;

      for (var i = 0; i < samples.length - 1; i++) {
        final p1 = LatLng(samples[i].latitude, samples[i].longitude);
        final p2 = LatLng(samples[i + 1].latitude, samples[i + 1].longitude);

        final dist = GpsValidator.calculateDistanceM(p1, p2);
        // Bỏ cạnh cực ngắn để nhiễu GPS không tạo mũi tên xoay liên tục.
        if (dist < 3.0) continue;

        final bearing = GpsValidator.calculateBearing(p1, p2);
        // Cạnh dài nhất dùng làm vị trí dự phòng nếu đoạn ngắn hơn khoảng rải marker.
        if (longestEdge == null || dist > longestEdge.distance) {
          longestEdge = (start: p1, end: p2, distance: dist, bearing: bearing);
        }

        var offset = distanceUntilNextArrow;
        while (offset <= dist && markers.length < maxArrowCount) {
          // Tỷ lệ offset/dist nội suy marker nằm đúng trên cạnh giữa hai mẫu GPS.
          markers.add(
            _buildDirectionArrow(
              point: GpsValidator.interpolatePosition(p1, p2, offset / dist),
              bearing: bearing,
              size: arrowSize,
              color: arrowColor,
            ),
          );
          offset += targetDistanceM;
        }

        // Phần khoảng cách còn thiếu được mang sang cạnh kế tiếp để mật độ marker đều.
        distanceUntilNextArrow = offset - dist;
        if (markers.length >= maxArrowCount) return markers;
      }

      // Tuyến ngắn vẫn cần một ký hiệu hướng để không bị hiểu như đường hai chiều.
      if (markers.length == segmentMarkerStart && longestEdge != null) {
        markers.add(
          _buildDirectionArrow(
            point: GpsValidator.interpolatePosition(
              longestEdge.start,
              longestEdge.end,
              0.5,
            ),
            bearing: longestEdge.bearing,
            size: arrowSize,
            color: arrowColor,
          ),
        );
      }
    }

    return markers;
  }

  static Marker _buildDirectionArrow({
    required LatLng point,
    required double bearing,
    required double size,
    required Color color,
  }) {
    return Marker(
      point: point,
      width: size + 4,
      height: size + 4,
      alignment: Alignment.center,
      child: Transform.rotate(
        angle: bearing * (math.pi / 180.0),
        child: CustomPaint(
          size: Size(size, size),
          painter: _RouteChevronPainter(
            color: color,
            strokeWidth: (size * 0.22).clamp(1.4, 2.4),
          ),
        ),
      ),
    );
  }

  /// Thuật toán gom cụm tự động quét danh sách điểm GPS theo thời gian
  /// để nhận diện chính xác các Điểm ĐỖ XE (>= 5 phút) và Điểm DỪNG TẠM (< 5 phút).
  static List<JourneyStopPoint> extractStopAndParkPoints(
    List<LocationModel> samples,
  ) {
    if (samples.isEmpty) return const [];

    // Chỉ sao chép và sort khi đầu vào chưa tăng dần, tránh cấp phát lại thông thường.
    final isSorted = _isChronologicallySorted(samples);
    final ordered = isSorted
        ? samples
        : (List<LocationModel>.from(samples)
            ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt)));
    final stops = <JourneyStopPoint>[];
    int? clusterStartIndex;
    DateTime? clusterStartTime;

    void closeStationaryCluster(int endIndex) {
      // Chốt cụm và xóa con trỏ trước để lần gọi sau không sử dụng lại cụm cũ.
      final startIndex = clusterStartIndex;
      final startTime = clusterStartTime;
      clusterStartIndex = null;
      clusterStartTime = null;

      if (startIndex == null || startTime == null || endIndex < startIndex) {
        return;
      }

      final endTime = ordered[endIndex].measuredAt;
      final durationSec = endTime.difference(startTime).inSeconds.abs();
      // Cụm dưới 30 giây được xem là dao động GPS, chưa đủ ý nghĩa để hiển thị.
      if (durationSec < 30) return;

      // Mẫu giữa cụm đại diện vị trí dừng tốt hơn điểm đầu/cuối lúc đổi trạng thái.
      final midIdx = startIndex + ((endIndex - startIndex) ~/ 2);
      stops.add(
        JourneyStopPoint(
          sample: ordered[midIdx],
          startTime: startTime,
          endTime: endTime,
          durationSeconds: durationSec,
          isPark: durationSec >= 300,
        ),
      );
    }

    for (var i = 0; i < ordered.length; i++) {
      final sample = ordered[i];

      // Không nối hai trạng thái đứng yên qua một khoảng mất GPS dài.
      if (i > 0 &&
          sample.measuredAt.difference(ordered[i - 1].measuredAt) >
              const Duration(minutes: 5)) {
        closeStationaryCluster(i - 1);
      }

      final isStationary = _isStationarySample(ordered, i);

      if (isStationary) {
        // Chỉ mở cụm ở mẫu đứng yên đầu tiên; các mẫu sau kéo dài cùng cụm.
        if (clusterStartIndex == null) {
          clusterStartIndex = i;
          clusterStartTime = sample.measuredAt;
        }
      } else {
        // Mẫu chuyển động kết thúc cụm tại mẫu đứng yên ngay trước nó.
        closeStationaryCluster(i - 1);
      }
    }

    closeStationaryCluster(ordered.length - 1);

    return stops;
  }

  static JourneyStopPoint? findStopPoint(
    List<LocationModel> samples,
    LocationModel point,
  ) {
    for (final stop in extractStopAndParkPoints(samples)) {
      if (stop.sample.id == point.id ||
          (stop.sample.measuredAt == point.measuredAt &&
              stop.sample.latitude == point.latitude &&
              stop.sample.longitude == point.longitude)) {
        return stop;
      }
    }
    return null;
  }

  /// Tạo tập node hành trình cố định. Node không phụ thuộc mức zoom hoặc việc
  /// thiết bị có gửi tốc độ hay không, nên cùng một hành trình luôn cho cùng
  /// một chuỗi A -> các mốc địa điểm/đỗ -> B.
  static List<JourneyRouteNode> extractRouteNodes(List<LocationModel> samples) {
    if (samples.isEmpty) return const [];

    // Các phép tính khoảng cách và thời gian phía dưới yêu cầu thứ tự tăng dần.
    final isSorted = _isChronologicallySorted(samples);
    final ordered = isSorted
        ? samples
        : (List<LocationModel>.from(samples)
            ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt)));
    final first = ordered.first;
    if (ordered.length == 1) {
      return [
        // Một mẫu chỉ đủ biểu diễn điểm bắt đầu, chưa có điểm kết thúc độc lập.
        JourneyRouteNode(sample: first, type: JourneyRouteNodeType.start),
      ];
    }

    final parks = extractStopAndParkPoints(
      ordered,
    ).where((stop) => stop.isPark).toList();
    var totalDistanceM = 0.0;
    for (var i = 1; i < ordered.length; i++) {
      final gap = ordered[i].measuredAt.difference(ordered[i - 1].measuredAt);
      // Không cộng đường thẳng xuyên qua khoảng mất dữ liệu vào quãng đường thật.
      if (gap > const Duration(minutes: 5)) continue;
      totalDistanceM += GpsValidator.calculateDistanceM(
        LatLng(ordered[i - 1].latitude, ordered[i - 1].longitude),
        LatLng(ordered[i].latitude, ordered[i].longitude),
      );
    }

    // Mục tiêu khoảng sáu mốc trung gian, có biên để tuyến ngắn/dài vẫn dễ đọc.
    final targetDistanceM = (totalDistanceM / 6).clamp(250.0, 3000.0);
    final placeSamples = <LocationModel>[];
    var distanceSinceNodeM = 0.0;
    var lastNodeTime = first.measuredAt;
    var parkScanIndex = 0;

    for (var i = 1; i < ordered.length - 1; i++) {
      final previous = ordered[i - 1];
      final current = ordered[i];
      final sampleGap = current.measuredAt.difference(previous.measuredAt);
      final startsAfterGap = sampleGap > const Duration(minutes: 5);

      if (!startsAfterGap) {
        // Chỉ tích lũy quãng đường trong cùng một đoạn GPS liên tục.
        distanceSinceNodeM += GpsValidator.calculateDistanceM(
          LatLng(previous.latitude, previous.longitude),
          LatLng(current.latitude, current.longitude),
        );
      }

      final elapsed = current.measuredAt.difference(lastNodeTime);
      // Bỏ điểm đỗ đã quá cũ để mỗi mẫu không phải quét lại toàn bộ danh sách.
      while (parkScanIndex < parks.length &&
          parks[parkScanIndex].sample.measuredAt.isBefore(
            current.measuredAt.subtract(const Duration(minutes: 5)),
          )) {
        parkScanIndex++;
      }
      var nearPark = false;
      // Tránh tạo mốc địa điểm sát điểm đỗ vì hai nhãn sẽ trùng ý nghĩa.
      for (var p = parkScanIndex; p < parks.length; p++) {
        final diffMin = current.measuredAt
            .difference(parks[p].sample.measuredAt)
            .inMinutes
            .abs();
        if (diffMin < 5) {
          nearPark = true;
          break;
        }
        if (parks[p].sample.measuredAt.isAfter(
          current.measuredAt.add(const Duration(minutes: 5)),
        )) {
          break;
        }
      }
      final shouldCreateNode =
          // Khoảng mất GPS đánh dấu đầu của một đoạn dữ liệu mới.
          startsAfterGap ||
          // Đủ quãng đường mục tiêu tạo mốc phân bố đều theo độ dài tuyến.
          distanceSinceNodeM >= targetDistanceM ||
          // Tuyến đi chậm vẫn có mốc sau thời gian dài nếu đã đi ít nhất 100 m.
          (elapsed >= const Duration(minutes: 20) && distanceSinceNodeM >= 100);

      if (shouldCreateNode && !nearPark) {
        // Mốc mới đặt lại cả gốc thời gian và bộ đếm quãng đường.
        placeSamples.add(current);
        lastNodeTime = current.measuredAt;
        distanceSinceNodeM = 0;
      } else if (startsAfterGap) {
        distanceSinceNodeM = 0;
      }
    }

    if (placeSamples.isEmpty && totalDistanceM >= 100 && ordered.length > 2) {
      // Tuyến có di chuyển nhưng chưa đạt điều kiện sẽ dùng một điểm giữa làm dự phòng.
      final middleIndex = ordered.length ~/ 2;
      final fallbackCandidates = <LocationModel>[
        ordered[middleIndex],
        ...ordered.sublist(1, ordered.length - 1),
      ];
      for (final candidate in fallbackCandidates) {
        final duplicatesPark = parks.any(
          (park) =>
              park.sample.measuredAt == candidate.measuredAt &&
              park.sample.latitude == candidate.latitude &&
              park.sample.longitude == candidate.longitude,
        );
        if (!duplicatesPark) {
          // Chỉ cần một mốc dự phòng không trùng điểm đỗ.
          placeSamples.add(candidate);
          break;
        }
      }
    }

    final nodes = <JourneyRouteNode>[
      JourneyRouteNode(sample: first, type: JourneyRouteNodeType.start),
      ...placeSamples.map(
        (sample) =>
            JourneyRouteNode(sample: sample, type: JourneyRouteNodeType.place),
      ),
      ...parks.map(
        (stop) => JourneyRouteNode(
          sample: stop.sample,
          type: JourneyRouteNodeType.park,
          stopPoint: stop,
        ),
      ),
      JourneyRouteNode(sample: ordered.last, type: JourneyRouteNodeType.end),
    ]..sort((a, b) => a.sample.measuredAt.compareTo(b.sample.measuredAt));

    return nodes;
  }

  static String routeNodeKey(LocationModel sample) {
    return '${sample.latitude.toStringAsFixed(5)},'
        '${sample.longitude.toStringAsFixed(5)}';
  }

  /// Không coi tốc độ bị thiếu là 0. Nếu cảm biến không gửi tốc độ, chỉ suy
  /// luận xe đứng yên khi hai mốc gần nhau và cách nhau không quá 2 phút.
  static bool _isStationarySample(List<LocationModel> samples, int index) {
    final sample = samples[index];
    final threshold = DeviceStatusResolver.movingThresholdMps;
    // Tốc độ thiết bị gửi là nguồn ưu tiên; chỉ suy diễn khi trường này bị thiếu.
    if (sample.speedMps != null) return sample.speedMps! <= threshold;

    LocationModel? other;
    if (index > 0) {
      other = samples[index - 1];
    } else if (samples.length > 1) {
      other = samples[1];
    }
    if (other == null) return false;

    // Hai mẫu cách nhau quá lâu không đủ tin cậy để suy ra vận tốc.
    final seconds = sample.measuredAt
        .difference(other.measuredAt)
        .inSeconds
        .abs();
    if (seconds == 0 || seconds > 120) return false;

    final distance = GpsValidator.calculateDistanceM(
      LatLng(sample.latitude, sample.longitude),
      LatLng(other.latitude, other.longitude),
    );
    // Dùng cùng ngưỡng với resolver để bản đồ không có định nghĩa di chuyển riêng.
    return distance / seconds <= threshold;
  }

  /// Xây dựng đầy đủ node hành trình và nhãn của chúng. Các node này không bị
  /// ẩn theo zoom hoặc theo thuật toán chống chồng lấn: xuất phát, địa điểm
  /// trung gian, đỗ xe và kết thúc luôn có mặt trên bản đồ.
  static List<Marker> buildSamplePoints({
    required List<LocationModel> validSamples,
    required ValueChanged<LocationModel> onPointSelected,
    Map<String, String> nodeAddresses = const {},
    bool showLabels = true,
    bool showAddresses = true,
    AppThemeColors colors = AppThemeColors.light,
  }) {
    if (validSamples.isEmpty) return const [];

    // Thứ tự ba danh sách quyết định marker đầu/cuối được vẽ trên các marker còn lại.
    final placeMarkers = <Marker>[];
    final parkMarkers = <Marker>[];
    final topMarkers = <Marker>[];
    final dateTimeFormat = DateFormat('dd/MM/yyyy · HH:mm:ss');
    // Marker đầy đủ giữ nguyên canvas cũ. Khi chỉ hiện thời gian, canvas co theo
    // đúng lượng nội dung của từng loại node để bong bóng không kéo ngang làm
    // chắn màn hình.
    final startEndMarkerSize = !showLabels
        ? const Size.square(24)
        : showAddresses
        ? const Size(260, 170)
        : const Size(170, 112);
    final parkMarkerSize = !showLabels
        ? const Size.square(24)
        : showAddresses
        ? const Size(250, 170)
        : const Size(226, 90);
    final placeMarkerSize = !showLabels
        ? const Size.square(24)
        : showAddresses
        ? const Size(250, 170)
        : const Size(164, 86);
    final nodes = extractRouteNodes(validSamples);
    final startNode = nodes.firstWhere(
      (node) => node.type == JourneyRouteNodeType.start,
    );
    final start = startNode.sample;
    final startDt = start.measuredAt.toLocal();

    topMarkers.add(
      Marker(
        point: LatLng(start.latitude, start.longitude),
        width: startEndMarkerSize.width,
        height: startEndMarkerSize.height,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () => onPointSelected(start),
          child: _buildStartEndMarkerWidget(
            title: 'BẮT ĐẦU',
            dateTimeText: dateTimeFormat.format(startDt),
            addressText: _nodeAddress(start, nodeAddresses),
            showAddress: showAddresses,
            color: colors.success,
            icon: Icons.play_arrow_rounded,
            showLabel: showLabels,
          ),
        ),
      ),
    );

    if (validSamples.length >= 2) {
      // Chỉ dựng marker kết thúc khi có ít nhất hai mẫu trong hành trình.
      final end = nodes
          .firstWhere((node) => node.type == JourneyRouteNodeType.end)
          .sample;
      final endDt = end.measuredAt.toLocal();

      topMarkers.add(
        Marker(
          point: LatLng(end.latitude, end.longitude),
          width: startEndMarkerSize.width,
          height: startEndMarkerSize.height,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () => onPointSelected(end),
            child: _buildStartEndMarkerWidget(
              title: 'KẾT THÚC',
              dateTimeText: dateTimeFormat.format(endDt),
              addressText: _nodeAddress(end, nodeAddresses),
              showAddress: showAddresses,
              color: colors.danger,
              icon: Icons.flag_rounded,
              showLabel: showLabels,
            ),
          ),
        ),
      );
    }

    for (final node in nodes.where(
      (node) => node.type == JourneyRouteNodeType.park,
    )) {
      final stop = node.stopPoint!;
      final stopCoord = LatLng(stop.sample.latitude, stop.sample.longitude);
      final stopDt = stop.startTime.toLocal();
      parkMarkers.add(
        Marker(
          point: stopCoord,
          width: parkMarkerSize.width,
          height: parkMarkerSize.height,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () => onPointSelected(stop.sample),
            child: _buildParkMarkerWidget(
              durationText: stop.compactDurationLabel,
              dateTimeText: dateTimeFormat.format(stopDt),
              addressText: _nodeAddress(stop.sample, nodeAddresses),
              showAddress: showAddresses,
              showLabel: showLabels,
              colors: colors,
            ),
          ),
        ),
      );
    }

    for (final node in nodes.where(
      (node) => node.type == JourneyRouteNodeType.place,
    )) {
      final sample = node.sample;
      placeMarkers.add(
        Marker(
          point: LatLng(sample.latitude, sample.longitude),
          width: placeMarkerSize.width,
          height: placeMarkerSize.height,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () => onPointSelected(sample),
            child: _buildPlaceNodeWidget(
              dateTimeText: dateTimeFormat.format(sample.measuredAt.toLocal()),
              addressText: _nodeAddress(sample, nodeAddresses),
              showAddress: showAddresses,
              showLabel: showLabels,
              colors: colors,
            ),
          ),
        ),
      );
    }

    return [...placeMarkers, ...parkMarkers, ...topMarkers];
  }

  static String _nodeAddress(
    LocationModel sample,
    Map<String, String> nodeAddresses,
  ) {
    // Geocoding chưa có kết quả vẫn fallback tọa độ để không hiển thị ô trống.
    return nodeAddresses[routeNodeKey(sample)] ??
        DeviceFormatters.coordinates(sample.latitude, sample.longitude);
  }

  static Widget _buildPlaceNodeWidget({
    required String dateTimeText,
    required String addressText,
    required bool showAddress,
    required bool showLabel,
    required AppThemeColors colors,
  }) {
    return _buildRouteNodeMarker(
      showLabel: showLabel,
      shrinkLabelWidth: !showAddress,
      bubbleFillColor: colors.surface,
      bubbleBorderColor: colors.primaryBorder,
      nodeColor: colors.primaryStrong,
      nodeChild: Container(
        width: 5,
        height: 5,
        decoration: const BoxDecoration(
          color: AppPalette.onAccent,
          shape: BoxShape.circle,
        ),
      ),
      label: Container(
        key: const Key('journey-place-node-label'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: colors.primaryBorder, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dateTimeText,
              style: TextStyle(
                color: colors.primaryStrong,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.1,
              ),
            ),
            if (showAddress) ...[
              const SizedBox(height: 2),
              Text(
                addressText,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Điểm đỗ xe [P] kèm thời lượng và mốc giờ để nhận biết trực quan.
  static Widget _buildParkMarkerWidget({
    required String durationText,
    required String dateTimeText,
    required String addressText,
    required bool showAddress,
    required bool showLabel,
    required AppThemeColors colors,
  }) {
    final color = colors.orange;
    return _buildRouteNodeMarker(
      showLabel: showLabel,
      shrinkLabelWidth: !showAddress,
      bubbleFillColor: color,
      bubbleBorderColor: AppPalette.onAccent,
      nodeColor: color,
      nodeChild: const Text(
        'P',
        style: TextStyle(
          color: AppPalette.onAccent,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      label: Container(
        key: const Key('journey-park-node-label'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.onAccent, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.26),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: showAddress ? MainAxisSize.max : MainAxisSize.min,
              children: [
                const Icon(
                  Icons.local_parking_rounded,
                  size: 13,
                  color: AppPalette.onAccent,
                ),
                const SizedBox(width: 4),
                if (showAddress)
                  Expanded(
                    child: Text(
                      'ĐỖ $durationText · $dateTimeText',
                      style: const TextStyle(
                        color: AppPalette.onAccent,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                else
                  Text(
                    'ĐỖ $durationText · $dateTimeText',
                    style: const TextStyle(
                      color: AppPalette.onAccent,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
            if (showAddress) ...[
              const SizedBox(height: 2),
              Text(
                addressText,
                style: const TextStyle(
                  color: AppPalette.onAccent,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Điểm bắt đầu/kết thúc nổi bật, hiển thị đầy đủ ngày và giờ.
  static Widget _buildStartEndMarkerWidget({
    required String title,
    required String dateTimeText,
    required String addressText,
    required bool showAddress,
    required Color color,
    required IconData icon,
    required bool showLabel,
  }) {
    return _buildRouteNodeMarker(
      showLabel: showLabel,
      shrinkLabelWidth: !showAddress,
      bubbleFillColor: color,
      bubbleBorderColor: AppPalette.onAccent,
      nodeColor: color,
      nodeChild: Icon(icon, size: 10, color: AppPalette.onAccent),
      label: Container(
        key: const Key('journey-start-end-node-label'),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: AppPalette.onAccent.withValues(alpha: 0.8),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 2.5),
            ),
            BoxShadow(
              color: AppPalette.shadow.withValues(alpha: 0.26),
              blurRadius: 4,
              offset: Offset(0, 1.5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: AppPalette.onAccent),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppPalette.onAccent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              dateTimeText,
              style: TextStyle(
                color: AppPalette.onAccent.withValues(alpha: 0.9),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (showAddress) ...[
              const SizedBox(height: 2),
              Text(
                addressText,
                style: const TextStyle(
                  color: AppPalette.onAccent,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _buildRouteNodeMarker({
    required bool showLabel,
    required bool shrinkLabelWidth,
    required Widget label,
    required Color bubbleFillColor,
    required Color bubbleBorderColor,
    required Color nodeColor,
    required Widget nodeChild,
  }) {
    const nodeSize = 18.0;
    const tailHeight = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerOffset = constraints.maxHeight / 2;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (showLabel)
              Positioned(
                left: 6,
                right: 6,
                bottom: centerOffset + nodeSize / 2 + tailHeight,
                child: shrinkLabelWidth
                    ? Align(alignment: Alignment.center, child: label)
                    : label,
              ),
            if (showLabel)
              Positioned(
                left: 0,
                right: 0,
                bottom: centerOffset + nodeSize / 2,
                child: Center(
                  child: CustomPaint(
                    size: const Size(14, tailHeight),
                    painter: _MarkerBubbleTailPainter(
                      fillColor: bubbleFillColor,
                      borderColor: bubbleBorderColor,
                    ),
                  ),
                ),
              ),
            Container(
              width: nodeSize,
              height: nodeSize,
              decoration: BoxDecoration(
                color: nodeColor,
                shape: BoxShape.circle,
                border: Border.all(color: AppPalette.onAccent, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppPalette.shadow.withValues(alpha: 0.26),
                    blurRadius: 3,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: nodeChild,
            ),
          ],
        );
      },
    );
  }

  /// Điểm đánh dấu vị trí thiết bị trong lúc phát lại.
  static Marker? buildReplayMarker({
    required JourneyHistoryState state,
    required ThemeData theme,
  }) {
    // Chưa nội suy được vị trí thì không dựng marker giả tại tâm bản đồ.
    if (state.currentPosition == null) return null;
    final appColors =
        theme.extension<AppThemeColors>() ??
        (theme.brightness == Brightness.dark
            ? AppThemeColors.dark
            : AppThemeColors.light);

    final deviceType = state.selectedDevice?.deviceType ?? 'VEHICLE';
    final heading = state.currentHeadingDeg ?? 0.0;
    final speed = state.currentSpeedMps;

    return Marker(
      point: state.currentPosition!,
      width: 86,
      height: 52,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: appColors.primary,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppPalette.onAccent, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: appColors.primary.withValues(alpha: 0.28),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              DeviceFormatters.speedMps(speed),
              style: const TextStyle(
                color: AppPalette.onAccent,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Icon thiết bị xoay theo heading
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: appColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: AppPalette.onAccent, width: 2),
              boxShadow: [
                BoxShadow(
                  color: appColors.primary.withValues(alpha: 0.5),
                  blurRadius: 7,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Transform.rotate(
              angle: heading * (math.pi / 180.0),
              child: Icon(
                DeviceIcon.iconFor(deviceType),
                color: AppPalette.onAccent,
                size: 15,
              ),
            ),
          ),
        ],
      ),
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

/// Đuôi bong bóng nối label với đúng tâm node GPS trên đường lộ trình.
// Painter vẽ phần đuôi bong bóng của nhãn marker về đúng tọa độ.
class _MarkerBubbleTailPainter extends CustomPainter {
  const _MarkerBubbleTailPainter({
    required this.fillColor,
    required this.borderColor,
  });

  final Color fillColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = fillColor);

    final sidePath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(
      sidePath,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkerBubbleTailPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor;
  }
}

/// Bộ vẽ tùy chỉnh tạo mũi tên chỉ hướng dạng hai nét chụm đầu (chevron ^).
/// với nét vẽ bo tròn và bóng đổ tương phản cao dọc theo lộ trình.
// Painter vẽ chevron chỉ hướng dọc tuyến, dùng góc đã tính từ các mẫu GPS.
class _RouteChevronPainter extends CustomPainter {
  const _RouteChevronPainter({required this.color, this.strokeWidth = 2.0});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Đường path mũi tên chevron 2 đường kẻ cụp đầu vào nhau
    final path = Path()
      ..moveTo(w * 0.15, h * 0.72)
      ..lineTo(w * 0.50, h * 0.26)
      ..lineTo(w * 0.85, h * 0.72);

    // Vẽ bóng đổ nhẹ phía dưới
    final shadowPaint = Paint()
      ..color = AppPalette.shadow.withValues(alpha: 0.4)
      ..strokeWidth = strokeWidth + 0.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path.shift(const Offset(0, 0.5)), shadowPaint);

    // Vẽ nét mũi tên chính
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RouteChevronPainter oldDelegate) {
    return color != oldDelegate.color || strokeWidth != oldDelegate.strokeWidth;
  }
}
