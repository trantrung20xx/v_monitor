import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/device_model.dart';
import '../../data/models/location_model.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/tracking_repository.dart';
import '../../domain/entities/gps_validator.dart';
import '../../domain/entities/route_segment.dart';
import 'journey_history_state.dart';

class JourneyHistoryCubit extends Cubit<JourneyHistoryState> {
  final TrackingRepository trackingRepo;
  final DeviceRepository deviceRepo;

  Timer? _replayTimer;
  DateTime? _lastTickRealtime;
  int _queryVersion = 0;

  JourneyHistoryCubit({
    required this.trackingRepo,
    required this.deviceRepo,
  }) : super(const JourneyHistoryState());

  /// Tải danh sách lịch sử vị trí của thiết bị trong khoảng [from, to].
  Future<void> loadHistory({
    required String deviceId,
    required DateTime from,
    required DateTime to,
    Duration? customGapThreshold,
  }) async {
    _stopPlayback();
    final currentVersion = ++_queryVersion;

    emit(state.copyWith(
      status: JourneyHistoryStatus.loading,
      fromTime: from,
      toTime: to,
      clearError: true,
      clearSelectedPoint: true,
    ));

    try {
      // 1. Lấy thông tin thiết bị song song nếu chưa có
      DeviceModel? device = state.selectedDevice;
      if (device == null || device.id != deviceId) {
        device = await deviceRepo.getDevice(deviceId);
      }

      // 2. Gọi API lấy lịch sử hành trình theo khoảng
      final response = await trackingRepo.getLocationHistoryRange(
        deviceId,
        from: from,
        to: to,
      );

      // Nếu đã có request mới hơn được phát ra, bỏ qua response cũ để tránh race condition (Section 59)
      if (currentVersion != _queryVersion || isClosed) return;

      if (response == null) {
        emit(state.copyWith(
          status: JourneyHistoryStatus.ready,
          selectedDevice: device,
          rawSamples: const [],
          validSamples: const [],
          segments: const [],
          totalCount: 0,
          totalDistanceM: 0.0,
          movingDurationS: 0,
          stoppedDurationS: 0,
        ));
        return;
      }

      final rawSamples = response.samples;

      // 3. Xử lý lọc dữ liệu GPS (Outlier detection + valid coordinates)
      final validSamples = GpsValidator.sanitizeSamples(rawSamples);

      // 4. Chia nhỏ thành các Route Segments theo gap threshold
      final gap = customGapThreshold ?? state.gapThreshold;
      final segments = RouteSegment.splitIntoSegments(
        validSamples,
        gapThreshold: gap,
      );

      // 5. Tính toán tổng hợp chỉ số
      var totalDistance = 0.0;
      var totalMoving = 0;
      var totalStopped = 0;
      double? maxSpeed;
      var speedSum = 0.0;
      var speedCount = 0;

      for (final segment in segments) {
        totalDistance += segment.distanceM;
        totalMoving += segment.movingDurationS;
        totalStopped += segment.stoppedDurationS;
        if (segment.maxSpeedMps != null) {
          if (maxSpeed == null || segment.maxSpeedMps! > maxSpeed) {
            maxSpeed = segment.maxSpeedMps;
          }
        }
        if (segment.avgSpeedMps != null) {
          speedSum += segment.avgSpeedMps! * segment.samples.length;
          speedCount += segment.samples.length;
        }
      }

      final initialPos = validSamples.isNotEmpty
          ? LatLng(validSamples.first.latitude, validSamples.first.longitude)
          : null;
      final initialTime = validSamples.isNotEmpty ? validSamples.first.measuredAt : null;
      final initialHeading = validSamples.isNotEmpty ? validSamples.first.headingDeg : null;
      final initialSpeed = validSamples.isNotEmpty ? validSamples.first.speedMps : null;

      emit(state.copyWith(
        status: JourneyHistoryStatus.ready,
        selectedDevice: device,
        rawSamples: rawSamples,
        validSamples: validSamples,
        segments: segments,
        totalCount: response.totalCount,
        truncated: response.truncated,
        totalDistanceM: totalDistance,
        movingDurationS: totalMoving,
        stoppedDurationS: totalStopped,
        maxSpeedMps: maxSpeed,
        avgSpeedMps: speedCount > 0 ? (speedSum / speedCount) : null,
        gapThreshold: gap,
        currentPosition: initialPos,
        currentReplayTime: initialTime,
        currentHeadingDeg: initialHeading,
        currentSpeedMps: initialSpeed,
        currentSampleIndex: 0,
      ));
    } catch (e) {
      if (currentVersion != _queryVersion || isClosed) return;
      emit(state.copyWith(
        status: JourneyHistoryStatus.error,
        errorMessage: 'Lỗi tải lịch sử hành trình: $e',
      ));
    }
  }

  /// Bắt đầu phát lại hành trình
  void play() {
    if (state.validSamples.length < 2) return;

    // Nếu đã tới điểm kết thúc thì reset về đầu trước khi play lại
    if (state.status == JourneyHistoryStatus.completed || state.currentReplayTime == null) {
      reset();
    }

    _lastTickRealtime = DateTime.now();
    emit(state.copyWith(status: JourneyHistoryStatus.playing));
    _startTimer();
  }

  /// Tạm dừng phát lại
  void pause() {
    _stopPlayback();
    emit(state.copyWith(status: JourneyHistoryStatus.paused));
  }

  /// Tiếp tục phát lại từ vị trí và thời gian hiện tại
  void resume() {
    if (state.status == JourneyHistoryStatus.paused) {
      play();
    }
  }

  /// Đặt lại về điểm bắt đầu của hành trình
  void reset() {
    _stopPlayback();
    if (state.validSamples.isEmpty) return;

    final first = state.validSamples.first;
    emit(state.copyWith(
      status: JourneyHistoryStatus.ready,
      currentPosition: LatLng(first.latitude, first.longitude),
      currentReplayTime: first.measuredAt,
      currentHeadingDeg: first.headingDeg,
      currentSpeedMps: first.speedMps,
      currentSampleIndex: 0,
    ));
  }

  /// Nhảy tới mốc thời gian cụ thể (Seek random time)
  void seekToTime(DateTime targetTime) {
    if (state.validSamples.isEmpty) return;

    final first = state.validSamples.first.measuredAt;
    final last = state.validSamples.last.measuredAt;

    final clampedTime = targetTime.isBefore(first)
        ? first
        : (targetTime.isAfter(last) ? last : targetTime);

    _updateReplayStateAtTime(clampedTime);
  }

  /// Nhảy theo thanh trượt tiến độ (0.0 .. 1.0)
  void seekToProgress(double progress) {
    if (state.validSamples.length < 2) return;

    final first = state.validSamples.first.measuredAt;
    final last = state.validSamples.last.measuredAt;
    final totalMs = last.difference(first).inMilliseconds;

    final targetMs = (totalMs * progress.clamp(0.0, 1.0)).round();
    final targetTime = first.add(Duration(milliseconds: targetMs));

    seekToTime(targetTime);
  }

  /// Tua lùi thời gian phát lại (mặc định 30 giây)
  void stepBackward([Duration duration = const Duration(seconds: 30)]) {
    if (state.validSamples.isEmpty) return;
    final firstTime = state.validSamples.first.measuredAt;
    final currentTime = state.currentReplayTime ?? firstTime;
    final targetTime = currentTime.subtract(duration);
    seekToTime(targetTime.isBefore(firstTime) ? firstTime : targetTime);
  }

  /// Tua tiến thời gian phát lại (mặc định 30 giây)
  void stepForward([Duration duration = const Duration(seconds: 30)]) {
    if (state.validSamples.isEmpty) return;
    final firstTime = state.validSamples.first.measuredAt;
    final lastTime = state.validSamples.last.measuredAt;
    final currentTime = state.currentReplayTime ?? firstTime;
    final targetTime = currentTime.add(duration);
    seekToTime(targetTime.isAfter(lastTime) ? lastTime : targetTime);
  }

  /// Thay đổi tốc độ phát lại (0.5x, 1x, 2x, 4x, 8x, 16x)
  void setPlaybackSpeed(double speed) {
    emit(state.copyWith(playbackSpeed: speed));
  }

  /// Bật/tắt chế độ camera tự động bám theo marker thiết bị
  void toggleFollowCamera([bool? follow]) {
    emit(state.copyWith(followCamera: follow ?? !state.followCamera));
  }

  /// Chọn xem thông tin chi tiết của 1 điểm GPS trên bản đồ
  void selectPoint(LocationModel? point) {
    if (point == null) {
      emit(state.copyWith(clearSelectedPoint: true));
    } else {
      emit(state.copyWith(selectedPoint: point));
    }
  }

  /// Cấu hình lại ngưỡng ngắt quãng thời gian (gap threshold)
  void setGapThreshold(Duration duration) {
    if (state.validSamples.isEmpty) {
      emit(state.copyWith(gapThreshold: duration));
      return;
    }

    final segments = RouteSegment.splitIntoSegments(
      state.validSamples,
      gapThreshold: duration,
    );

    emit(state.copyWith(
      gapThreshold: duration,
      segments: segments,
    ));
  }

  /// Đổi thiết bị đang xem
  void selectDevice(DeviceModel device) {
    if (state.selectedDevice?.id == device.id) return;
    _stopPlayback();
    emit(JourneyHistoryState(
      selectedDevice: device,
      gapThreshold: state.gapThreshold,
      playbackSpeed: state.playbackSpeed,
      followCamera: state.followCamera,
    ));
  }

  void _startTimer() {
    _replayTimer?.cancel();
    // 33ms ~ 30 frames per second để đảm bảo mượt mà mà không tốn CPU (Section 55 & 56)
    _replayTimer = Timer.periodic(const Duration(milliseconds: 33), _onReplayTick);
  }

  void _onReplayTick(Timer timer) {
    if (state.status != JourneyHistoryStatus.playing || state.validSamples.length < 2) {
      _stopPlayback();
      return;
    }

    final now = DateTime.now();
    final dtRealtime = now.difference(_lastTickRealtime ?? now);
    _lastTickRealtime = now;

    // Tính bước nhảy thời gian mô phỏng dựa theo tốc độ phát (playbackSpeed)
    final dtSimulatedMs = (dtRealtime.inMilliseconds * state.playbackSpeed).round();
    if (dtSimulatedMs <= 0) return;

    final nextTime = (state.currentReplayTime ?? state.validSamples.first.measuredAt)
        .add(Duration(milliseconds: dtSimulatedMs));

    final lastSampleTime = state.validSamples.last.measuredAt;

    if (nextTime.isAfter(lastSampleTime) || nextTime.isAtSameMomentAs(lastSampleTime)) {
      // Đã chạy tới đích cuối cùng
      _stopPlayback();
      final last = state.validSamples.last;
      emit(state.copyWith(
        status: JourneyHistoryStatus.completed,
        currentReplayTime: last.measuredAt,
        currentPosition: LatLng(last.latitude, last.longitude),
        currentHeadingDeg: last.headingDeg,
        currentSpeedMps: last.speedMps,
        currentSampleIndex: state.validSamples.length - 1,
      ));
      return;
    }

    _updateReplayStateAtTime(nextTime);
  }

  /// Cập nhật vị trí, hướng, tốc độ nội suy tại mốc thời gian [targetTime]
  void _updateReplayStateAtTime(DateTime targetTime) {
    final samples = state.validSamples;
    if (samples.isEmpty) return;

    if (samples.length == 1) {
      final s = samples.first;
      emit(state.copyWith(
        currentReplayTime: s.measuredAt,
        currentPosition: LatLng(s.latitude, s.longitude),
        currentHeadingDeg: s.headingDeg,
        currentSpeedMps: s.speedMps,
        currentSampleIndex: 0,
      ));
      return;
    }

    // Tìm vị trí của targetTime trong danh sách samples đã sort
    int index = 0;
    while (index < samples.length - 1 && samples[index + 1].measuredAt.isBefore(targetTime)) {
      index++;
    }

    final p1 = samples[index];
    final p2 = samples[(index + 1).clamp(0, samples.length - 1)];

    final p1Time = p1.measuredAt;
    final p2Time = p2.measuredAt;

    final segmentGap = p2Time.difference(p1Time);

    // Nếu khoảng cách giữa 2 điểm này vượt quá Gap Threshold (mất GPS / tắt máy lâu)
    // -> Tự động nhảy thẳng tới p2 (Section 31)
    if (segmentGap > state.gapThreshold) {
      emit(state.copyWith(
        currentReplayTime: p2.measuredAt,
        currentPosition: LatLng(p2.latitude, p2.longitude),
        currentHeadingDeg: p2.headingDeg,
        currentSpeedMps: p2.speedMps,
        currentSampleIndex: index + 1,
      ));
      return;
    }

    final totalMs = p2Time.difference(p1Time).inMilliseconds;
    final progress = totalMs > 0
        ? (targetTime.difference(p1Time).inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;

    // Nội suy vị trí hiển thị giữa p1 và p2
    final interpolatedPos = GpsValidator.interpolatePosition(
      LatLng(p1.latitude, p1.longitude),
      LatLng(p2.latitude, p2.longitude),
      progress,
    );

    // Tính hướng di chuyển: ưu tiên bearing thực tế giữa 2 điểm liên tiếp (Section 22 & 62)
    final segmentBearing = GpsValidator.calculateBearing(
      LatLng(p1.latitude, p1.longitude),
      LatLng(p2.latitude, p2.longitude),
    );
    final heading = p1.headingDeg ?? segmentBearing;

    // Tốc độ tại thời điểm
    final speed = p1.speedMps != null && p2.speedMps != null
        ? p1.speedMps! + (p2.speedMps! - p1.speedMps!) * progress
        : (p1.speedMps ?? p2.speedMps);

    emit(state.copyWith(
      currentReplayTime: targetTime,
      currentPosition: interpolatedPos,
      currentHeadingDeg: heading,
      currentSpeedMps: speed,
      currentSampleIndex: index,
    ));
  }

  void _stopPlayback() {
    _replayTimer?.cancel();
    _replayTimer = null;
    _lastTickRealtime = null;
  }

  @override
  Future<void> close() {
    _stopPlayback();
    return super.close();
  }
}
