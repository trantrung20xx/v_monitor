import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import '../../data/models/device_model.dart';
import '../../data/models/location_model.dart';
import '../../domain/entities/route_segment.dart';

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
  final JourneyHistoryStatus status;
  final String? errorMessage;
  final DeviceModel? selectedDevice;
  final DateTime? fromTime;
  final DateTime? toTime;

  // Dữ liệu mẫu GPS
  final List<LocationModel> rawSamples;
  final List<LocationModel> validSamples;
  final List<RouteSegment> segments;
  final int totalCount;
  final bool truncated;

  // Tổng hợp chỉ số
  final double totalDistanceM;
  final int movingDurationS;
  final int stoppedDurationS;
  final double? maxSpeedMps;
  final double? avgSpeedMps;

  // Cấu hình
  final Duration gapThreshold;

  // Trạng thái phát lại (Replay Engine)
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
    this.totalCount = 0,
    this.truncated = false,
    this.totalDistanceM = 0.0,
    this.movingDurationS = 0,
    this.stoppedDurationS = 0,
    this.maxSpeedMps,
    this.avgSpeedMps,
    this.gapThreshold = const Duration(minutes: 5),
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
  bool get isEmpty => status == JourneyHistoryStatus.ready && validSamples.isEmpty;

  /// Tiến độ phát lại từ 0.0 đến 1.0
  double get playbackProgress {
    if (validSamples.length < 2 || fromTime == null || toTime == null || currentReplayTime == null) {
      return 0.0;
    }
    final totalDuration = validSamples.last.measuredAt.difference(validSamples.first.measuredAt).inMilliseconds;
    if (totalDuration <= 0) return 0.0;

    final currentOffset = currentReplayTime!.difference(validSamples.first.measuredAt).inMilliseconds;
    return (currentOffset / totalDuration).clamp(0.0, 1.0);
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
    int? totalCount,
    bool? truncated,
    double? totalDistanceM,
    int? movingDurationS,
    int? stoppedDurationS,
    double? maxSpeedMps,
    double? avgSpeedMps,
    Duration? gapThreshold,
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
    return JourneyHistoryState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      selectedDevice: selectedDevice ?? this.selectedDevice,
      fromTime: fromTime ?? this.fromTime,
      toTime: toTime ?? this.toTime,
      rawSamples: rawSamples ?? this.rawSamples,
      validSamples: validSamples ?? this.validSamples,
      segments: segments ?? this.segments,
      totalCount: totalCount ?? this.totalCount,
      truncated: truncated ?? this.truncated,
      totalDistanceM: totalDistanceM ?? this.totalDistanceM,
      movingDurationS: movingDurationS ?? this.movingDurationS,
      stoppedDurationS: stoppedDurationS ?? this.stoppedDurationS,
      maxSpeedMps: maxSpeedMps ?? this.maxSpeedMps,
      avgSpeedMps: avgSpeedMps ?? this.avgSpeedMps,
      gapThreshold: gapThreshold ?? this.gapThreshold,
      currentReplayTime: currentReplayTime ?? this.currentReplayTime,
      currentPosition: currentPosition ?? this.currentPosition,
      currentSpeedMps: currentSpeedMps ?? this.currentSpeedMps,
      currentHeadingDeg: currentHeadingDeg ?? this.currentHeadingDeg,
      currentSampleIndex: currentSampleIndex ?? this.currentSampleIndex,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      followCamera: followCamera ?? this.followCamera,
      selectedPoint: clearSelectedPoint ? null : (selectedPoint ?? this.selectedPoint),
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
        totalCount,
        truncated,
        totalDistanceM,
        movingDurationS,
        stoppedDurationS,
        maxSpeedMps,
        avgSpeedMps,
        gapThreshold,
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
