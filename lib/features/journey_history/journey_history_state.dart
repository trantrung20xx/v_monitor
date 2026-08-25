// State bất biến của hành trình: khoảng chọn, mẫu gốc/đã xử lý, đoạn đường, playback,
// điểm đang chọn và thống kê. Các getter chỉ suy ra dữ liệu để trình bày.
import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/device_model.dart';
import '../../data/models/location_model.dart';
import '../../domain/entities/gps_validator.dart';
import '../../domain/entities/route_segment.dart';

// Máy trạng thái phát lại/tải hành trình; mỗi giá trị quyết định nhóm control được bật.
enum JourneyHistoryStatus {
  idle,
  loading,
  ready,
  playing,
  paused,
  completed,
  error,
}

class JourneyHistoryState extends Equatable {
  // status/error điều khiển trạng thái màn hình; selectedDevice xác định nguồn truy vấn.
  final JourneyHistoryStatus status;
  final String? errorMessage;
  final DeviceModel? selectedDevice;
  final DateTime? fromTime;
  final DateTime? toTime;

  // rawSamples là dữ liệu API; validSamples đã qua kiểm tra GPS; segments là các đoạn
  // liên tục; cumulativeDistancesM hỗ trợ đọc nhanh quãng đường tại con trỏ playback.
  final List<LocationModel> rawSamples;
  final List<LocationModel> validSamples;
  final List<RouteSegment> segments;
  final List<double> cumulativeDistancesM;
  final int totalCount;
  final bool truncated;

  // Chỉ số tổng hợp được tính từ validSamples/segments, không lấy số giả từ UI.
  final double totalDistanceM;
  final int movingDurationS;
  final int stoppedDurationS;
  final double? maxSpeedMps;
  final double? avgSpeedMps;

  // Hai ngưỡng quyết định tách đoạn và phân loại di chuyển cho phiên đang xem.
  final Duration gapThreshold;
  final double movementThresholdMps;

  // Trạng thái phát lại: mốc mô phỏng, marker nội suy, mẫu lân cận, tốc độ phát và camera.
  final DateTime? currentReplayTime;
  final LatLng? currentPosition;
  final double? currentSpeedMps;
  final double? currentHeadingDeg;
  final int currentSampleIndex;
  final double playbackSpeed;
  final bool followCamera;
  final LocationModel? selectedPoint;

  const JourneyHistoryState({
    this.status = JourneyHistoryStatus.idle,
    this.errorMessage,
    this.selectedDevice,
    this.fromTime,
    this.toTime,
    this.rawSamples = const [],
    this.validSamples = const [],
    this.segments = const [],
    this.cumulativeDistancesM = const [],
    this.totalCount = 0,
    this.truncated = false,
    this.totalDistanceM = 0.0,
    this.movingDurationS = 0,
    this.stoppedDurationS = 0,
    this.maxSpeedMps,
    this.avgSpeedMps,
    this.gapThreshold = const Duration(minutes: 5),
    this.movementThresholdMps = 0.5,
    this.currentReplayTime,
    this.currentPosition,
    this.currentSpeedMps,
    this.currentHeadingDeg,
    this.currentSampleIndex = 0,
    this.playbackSpeed = 1.0,
    this.followCamera = true,
    this.selectedPoint,
  });

  bool get isLoading => status == JourneyHistoryStatus.loading;
  bool get isPlaying => status == JourneyHistoryStatus.playing;
  bool get isPaused => status == JourneyHistoryStatus.paused;
  bool get isCompleted => status == JourneyHistoryStatus.completed;
  bool get hasRoute => validSamples.length >= 2;
  bool get hasSinglePoint => validSamples.length == 1;
  bool get isEmpty =>
      status == JourneyHistoryStatus.ready && validSamples.isEmpty;

  /// Tiến độ phát lại từ 0.0 đến 1.0
  double get playbackProgress {
    // Tiến độ dựa trên mốc đo đầu/cuối thật, không dựa vào chỉ số mẫu vì khoảng cách
    // thời gian giữa các mẫu có thể không đều.
    if (validSamples.length < 2 ||
        fromTime == null ||
        toTime == null ||
        currentReplayTime == null) {
      return 0.0;
    }
    final totalDuration = validSamples.last.measuredAt
        .difference(validSamples.first.measuredAt)
        .inMilliseconds;
    if (totalDuration <= 0) return 0.0;

    final currentOffset = currentReplayTime!
        .difference(validSamples.first.measuredAt)
        .inMilliseconds;
    return (currentOffset / totalDuration).clamp(0.0, 1.0);
  }

  /// Quãng đường đã đi tính đến thời điểm phát lại / điểm đang chọn hiện tại (m)
  double get currentDistanceM {
    // Ưu tiên mảng cộng dồn O(1); nhánh tính lại giữ tương thích state cũ/test chưa
    // cung cấp cumulativeDistancesM và không cộng qua gap.
    if (cumulativeDistancesM.isNotEmpty) {
      if (currentSampleIndex <= 0) return 0.0;
      final targetIndex = currentSampleIndex.clamp(
        0,
        cumulativeDistancesM.length - 1,
      );
      return cumulativeDistancesM[targetIndex];
    }

    if (validSamples.length < 2 || currentSampleIndex <= 0) return 0.0;

    var distance = 0.0;
    final targetIndex = currentSampleIndex.clamp(0, validSamples.length - 1);

    for (var i = 1; i <= targetIndex; i++) {
      final prev = validSamples[i - 1];
      final curr = validSamples[i];
      if (curr.measuredAt.difference(prev.measuredAt) <= gapThreshold) {
        distance += GpsValidator.calculateDistanceM(
          LatLng(prev.latitude, prev.longitude),
          LatLng(curr.latitude, curr.longitude),
        );
      }
    }
    return distance;
  }

  JourneyHistoryState copyWith({
    JourneyHistoryStatus? status,
    String? errorMessage,
    bool clearError = false,
    DeviceModel? selectedDevice,
    DateTime? fromTime,
    DateTime? toTime,
    List<LocationModel>? rawSamples,
    List<LocationModel>? validSamples,
    List<RouteSegment>? segments,
    List<double>? cumulativeDistancesM,
    int? totalCount,
    bool? truncated,
    double? totalDistanceM,
    int? movingDurationS,
    int? stoppedDurationS,
    double? maxSpeedMps,
    double? avgSpeedMps,
    Duration? gapThreshold,
    double? movementThresholdMps,
    DateTime? currentReplayTime,
    LatLng? currentPosition,
    double? currentSpeedMps,
    double? currentHeadingDeg,
    int? currentSampleIndex,
    double? playbackSpeed,
    bool? followCamera,
    LocationModel? selectedPoint,
    bool clearSelectedPoint = false,
  }) {
    // clearError/clearSelectedPoint tách thao tác gán null khỏi trường không truyền;
    // các trường còn lại mặc định giữ giá trị snapshot hiện tại.
    return JourneyHistoryState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      selectedDevice: selectedDevice ?? this.selectedDevice,
      fromTime: fromTime ?? this.fromTime,
      toTime: toTime ?? this.toTime,
      rawSamples: rawSamples ?? this.rawSamples,
      validSamples: validSamples ?? this.validSamples,
      segments: segments ?? this.segments,
      cumulativeDistancesM: cumulativeDistancesM ?? this.cumulativeDistancesM,
      totalCount: totalCount ?? this.totalCount,
      truncated: truncated ?? this.truncated,
      totalDistanceM: totalDistanceM ?? this.totalDistanceM,
      movingDurationS: movingDurationS ?? this.movingDurationS,
      stoppedDurationS: stoppedDurationS ?? this.stoppedDurationS,
      maxSpeedMps: maxSpeedMps ?? this.maxSpeedMps,
      avgSpeedMps: avgSpeedMps ?? this.avgSpeedMps,
      gapThreshold: gapThreshold ?? this.gapThreshold,
      movementThresholdMps: movementThresholdMps ?? this.movementThresholdMps,
      currentReplayTime: currentReplayTime ?? this.currentReplayTime,
      currentPosition: currentPosition ?? this.currentPosition,
      currentSpeedMps: currentSpeedMps ?? this.currentSpeedMps,
      currentHeadingDeg: currentHeadingDeg ?? this.currentHeadingDeg,
      currentSampleIndex: currentSampleIndex ?? this.currentSampleIndex,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      followCamera: followCamera ?? this.followCamera,
      selectedPoint: clearSelectedPoint
          ? null
          : (selectedPoint ?? this.selectedPoint),
    );
  }

  @override
  List<Object?> get props => [
    status,
    errorMessage,
    selectedDevice,
    fromTime,
    toTime,
    rawSamples,
    validSamples,
    segments,
    cumulativeDistancesM,
    totalCount,
    truncated,
    totalDistanceM,
    movingDurationS,
    stoppedDurationS,
    maxSpeedMps,
    avgSpeedMps,
    gapThreshold,
    movementThresholdMps,
    currentReplayTime,
    currentPosition,
    currentSpeedMps,
    currentHeadingDeg,
    currentSampleIndex,
    playbackSpeed,
    followCamera,
    selectedPoint,
  ];
}
