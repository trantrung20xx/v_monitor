// Máy trạng thái hành trình: chọn thời gian, tải mẫu GPS, làm sạch/chia đoạn, tính tóm tắt
// và điều khiển playback. Timer chỉ tiến con trỏ, không làm thay đổi dữ liệu lịch sử.
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/device_model.dart';
import '../../data/models/location_model.dart';
import '../../data/models/system_settings_model.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/tracking_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/gps_validator.dart';
import '../../domain/entities/route_segment.dart';
import 'journey_history_state.dart';

class JourneyHistoryCubit extends Cubit<JourneyHistoryState> {
  // trackingRepo cung cấp lịch sử; deviceRepo cung cấp hồ sơ; settingsRepo tùy chọn
  // cung cấp ngưỡng runtime và có thể vắng mặt trong bài kiểm thử độc lập.
  final TrackingRepository trackingRepo;
  final DeviceRepository deviceRepo;
  final SettingsRepository? settingsRepo;

  // Timer tạo nhịp hình; lastTickRealtime đo thời gian thật giữa hai nhịp để playback
  // không phụ thuộc chính xác vào tần số timer.
  Timer? _replayTimer;
  DateTime? _lastTickRealtime;
  // Mỗi lần tải tăng version; response cũ không được emit sau một truy vấn mới hơn.
  int _queryVersion = 0;
  // Khi người dùng tự chọn gap, cập nhật hệ thống không ghi đè lựa chọn phiên hiện tại.
  bool _hasCustomGapThreshold = false;
  StreamSubscription<SystemSettingsModel>? _settingsSubscription;

  JourneyHistoryCubit({
    required this.trackingRepo,
    required this.deviceRepo,
    this.settingsRepo,
  }) : super(
         JourneyHistoryState(
           gapThreshold: Duration(
             seconds:
                 settingsRepo?.systemSettings.defaultGapThresholdSeconds ?? 300,
           ),
           movementThresholdMps:
               settingsRepo?.systemSettings.movementThresholdMps ?? 0.5,
         ),
       ) {
    _settingsSubscription = settingsRepo?.systemSettingsChanges.listen(
      // Mỗi snapshot mới tính lại các đại lượng phụ thuộc ngưỡng trên cùng dữ liệu GPS.
      _onSystemSettingsChanged,
    );
  }

  /// Tải danh sách lịch sử vị trí của thiết bị trong khoảng [from, to].
  Future<void> loadHistory({
    required String deviceId,
    required DateTime from,
    required DateTime to,
    Duration? customGapThreshold,
  }) async {
    // Truy vấn mới dừng playback cũ để timer không emit lên dữ liệu đang thay thế.
    _stopPlayback();
    // Version tăng trước request và được chụp cục bộ để phát hiện response đến muộn.
    final currentVersion = ++_queryVersion;

    // Giữ selectedDevice/ngưỡng nhưng xóa điểm đang chọn của hành trình trước.
    emit(
      state.copyWith(
        status: JourneyHistoryStatus.loading,
        fromTime: from,
        toTime: to,
        clearError: true,
        clearSelectedPoint: true,
      ),
    );

    try {
      // Lấy thông tin thiết bị song song nếu state chưa có đúng thiết bị đang chọn.
      DeviceModel? device = state.selectedDevice;
      // Tránh gọi lại endpoint hồ sơ khi state đã giữ đúng deviceId.
      if (device == null || device.id != deviceId) {
        device = await deviceRepo.getDevice(deviceId);
      }

      // Gọi API lấy lịch sử hành trình theo khoảng thời gian thực tế.
      final response = await trackingRepo.getLocationHistoryRange(
        deviceId,
        from: from,
        to: to,
      );

      // Nếu đã có request mới hơn, bỏ response cũ để tránh ghi đè state mới.
      if (currentVersion != _queryVersion || isClosed) return;

      // Repository trả null khi không có payload lịch sử; state ready rỗng khác với lỗi.
      if (response == null) {
        emit(
          state.copyWith(
            status: JourneyHistoryStatus.ready,
            selectedDevice: device,
            rawSamples: const [],
            validSamples: const [],
            segments: const [],
            totalCount: 0,
            totalDistanceM: 0.0,
            movingDurationS: 0,
            stoppedDurationS: 0,
          ),
        );
        return;
      }

      final rawSamples = response.samples;

      // Loại tọa độ sai và điểm nhảy bất thường trước khi vẽ/tính quãng đường.
      // rawSamples vẫn được giữ trong state để thống kê số mẫu nguồn và chẩn đoán.
      final validSamples = GpsValidator.sanitizeSamples(rawSamples);

      // Chia hành trình thành các đoạn tại khoảng mất dữ liệu lớn hơn ngưỡng gap.
      // customGapThreshold chỉ áp dụng cho lần tải này; nếu không có thì dùng state hiện tại.
      final gap = customGapThreshold ?? state.gapThreshold;
      final summary = _buildSummary(
        validSamples,
        gapThreshold: gap,
        movementThresholdMps: state.movementThresholdMps,
      );

      // Bốn giá trị playback khởi tạo từ mẫu hợp lệ đầu tiên; danh sách rỗng dùng null.
      final initialPos = validSamples.isNotEmpty
          ? LatLng(validSamples.first.latitude, validSamples.first.longitude)
          : null;
      final initialTime = validSamples.isNotEmpty
          ? validSamples.first.measuredAt
          : null;
      final initialHeading = validSamples.isNotEmpty
          ? validSamples.first.headingDeg
          : null;
      final initialSpeed = validSamples.isNotEmpty
          ? validSamples.first.speedMps
          : null;
      // Khoảng cách lũy kế cho phép popup điểm bất kỳ đọc quãng đường O(1).
      final cumulativeDistances = _computeCumulativeDistances(
        validSamples,
        gap,
      );

      // Một state ready chứa đồng thời dữ liệu nguồn, dữ liệu sạch, tóm tắt và
      // con trỏ playback để UI không ghép snapshot của nhiều lần emit.
      emit(
        state.copyWith(
          status: JourneyHistoryStatus.ready,
          selectedDevice: device,
          rawSamples: rawSamples,
          validSamples: validSamples,
          segments: summary.segments,
          cumulativeDistancesM: cumulativeDistances,
          totalCount: response.totalCount,
          truncated: response.truncated,
          totalDistanceM: summary.totalDistanceM,
          movingDurationS: summary.movingDurationS,
          stoppedDurationS: summary.stoppedDurationS,
          maxSpeedMps: summary.maxSpeedMps,
          avgSpeedMps: summary.avgSpeedMps,
          gapThreshold: gap,
          currentPosition: initialPos,
          currentReplayTime: initialTime,
          currentHeadingDeg: initialHeading,
          currentSpeedMps: initialSpeed,
          currentSampleIndex: 0,
        ),
      );
    } catch (e) {
      // Lỗi của request cũ bị bỏ qua giống response thành công cũ.
      if (currentVersion != _queryVersion || isClosed) return;
      emit(
        state.copyWith(
          status: JourneyHistoryStatus.error,
          errorMessage: 'Lỗi tải lịch sử hành trình: $e',
        ),
      );
    }
  }

  /// Bắt đầu phát lại hành trình
  void play() {
    // Ít hơn hai điểm không có đoạn thời gian/vị trí để nội suy.
    if (state.validSamples.length < 2) return;

    // Nếu đã tới điểm kết thúc thì đặt lại về đầu trước khi phát lại.
    if (state.status == JourneyHistoryStatus.completed ||
        state.currentReplayTime == null) {
      reset();
    }

    // Mốc thật bắt đầu giúp nhịp đầu tính đúng khoảng thời gian đã trôi.
    _lastTickRealtime = DateTime.now();
    // Emit trạng thái trước khi tạo timer để callback đầu nhận đúng playing.
    emit(state.copyWith(status: JourneyHistoryStatus.playing));
    _startTimer();
  }

  /// Tạm dừng phát lại
  void pause() {
    // Dừng timer nhưng giữ nguyên con trỏ thời gian/vị trí hiện tại.
    _stopPlayback();
    emit(state.copyWith(status: JourneyHistoryStatus.paused));
  }

  /// Tiếp tục phát lại từ vị trí và thời gian hiện tại
  void resume() {
    // Chỉ paused được tiếp tục; ready/completed dùng nút play với quy tắc riêng.
    if (state.status == JourneyHistoryStatus.paused) {
      play();
    }
  }

  /// Đặt lại về điểm bắt đầu của hành trình
  void reset() {
    _stopPlayback();
    // Không có mẫu thì giữ state hiện tại, tránh truy cập `.first`.
    if (state.validSamples.isEmpty) return;

    // Đưa cả thời gian, vị trí, hướng, tốc độ và index về cùng mẫu đầu.
    final first = state.validSamples.first;
    emit(
      state.copyWith(
        status: JourneyHistoryStatus.ready,
        currentPosition: LatLng(first.latitude, first.longitude),
        currentReplayTime: first.measuredAt,
        currentHeadingDeg: first.headingDeg,
        currentSpeedMps: first.speedMps,
        currentSampleIndex: 0,
      ),
    );
  }

  /// Nhảy tới một mốc thời gian cụ thể trong giới hạn hành trình.
  void seekToTime(DateTime targetTime) {
    // Không có miền thời gian để clamp khi danh sách rỗng.
    if (state.validSamples.isEmpty) return;

    final first = state.validSamples.first.measuredAt;
    final last = state.validSamples.last.measuredAt;

    // Clamp bảo đảm tìm kiếm nhị phân luôn nhận mốc nằm trong hành trình.
    final clampedTime = targetTime.isBefore(first)
        ? first
        : (targetTime.isAfter(last) ? last : targetTime);

    _updateReplayStateAtTime(clampedTime);
  }

  /// Nhảy theo thanh trượt tiến độ (0.0 .. 1.0)
  void seekToProgress(double progress) {
    // Cần ít nhất hai mốc để quy đổi tỷ lệ thành Duration.
    if (state.validSamples.length < 2) return;

    final first = state.validSamples.first.measuredAt;
    final last = state.validSamples.last.measuredAt;
    final totalMs = last.difference(first).inMilliseconds;

    // Clamp cả giá trị do kéo UI hoặc caller truyền ngoài miền 0..1.
    final targetMs = (totalMs * progress.clamp(0.0, 1.0)).round();
    // Cộng duration vào mốc đầu tạo thời gian tuyệt đối để dùng chung seekToTime.
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
    // null là thao tác đóng popup; giá trị thật là điểm do marker/polyline chọn.
    if (point == null) {
      emit(state.copyWith(clearSelectedPoint: true));
    } else {
      emit(state.copyWith(selectedPoint: point));
    }
  }

  /// Cấu hình lại ngưỡng ngắt quãng thời gian (gap threshold)
  void setGapThreshold(Duration duration) {
    // Ghi nhớ lựa chọn thủ công để stream system settings không ghi đè trong phiên.
    _hasCustomGapThreshold = true;
    // Chưa có dữ liệu chỉ cần lưu ngưỡng cho lần tải sau, không có gì để tính lại.
    if (state.validSamples.isEmpty) {
      emit(state.copyWith(gapThreshold: duration));
      return;
    }

    final summary = _buildSummary(
      state.validSamples,
      gapThreshold: duration,
      movementThresholdMps: state.movementThresholdMps,
    );
    // Cumulative distance cũng phụ thuộc điểm cắt gap nên phải tính lại cùng summary.
    final cumulativeDistances = _computeCumulativeDistances(
      state.validSamples,
      duration,
    );

    emit(
      state.copyWith(
        gapThreshold: duration,
        segments: summary.segments,
        cumulativeDistancesM: cumulativeDistances,
        totalDistanceM: summary.totalDistanceM,
        movingDurationS: summary.movingDurationS,
        stoppedDurationS: summary.stoppedDurationS,
        maxSpeedMps: summary.maxSpeedMps,
        avgSpeedMps: summary.avgSpeedMps,
      ),
    );
  }

  /// Đổi thiết bị đang xem
  void selectDevice(DeviceModel device) {
    // Chọn lại cùng thiết bị không xóa hành trình hiện tại.
    if (state.selectedDevice?.id == device.id) return;
    // Thiết bị mới bắt đầu bằng state sạch nhưng giữ các tùy chọn playback/ngưỡng.
    _stopPlayback();
    emit(
      JourneyHistoryState(
        selectedDevice: device,
        gapThreshold: state.gapThreshold,
        movementThresholdMps: state.movementThresholdMps,
        playbackSpeed: state.playbackSpeed,
        followCamera: state.followCamera,
      ),
    );
  }

  void _startTimer() {
    // Hủy timer cũ trước khi tạo timer mới để play/resume lặp không tăng số callback.
    _replayTimer?.cancel();
    // 33 ms tương đương khoảng 30 khung hình/giây, đủ mượt mà và không tốn CPU quá mức.
    _replayTimer = Timer.periodic(
      const Duration(milliseconds: 33),
      _onReplayTick,
    );
  }

  void _onReplayTick(Timer timer) {
    // Timer tự dừng nếu state không còn playing hoặc dữ liệu bị thay bằng danh sách ngắn.
    if (state.status != JourneyHistoryStatus.playing ||
        state.validSamples.length < 2) {
      _stopPlayback();
      return;
    }

    // Dùng chênh lệch đồng hồ thật thay vì giả định timer luôn chạy chính xác 33 ms.
    final now = DateTime.now();
    final dtRealtime = now.difference(_lastTickRealtime ?? now);
    _lastTickRealtime = now;

    // Quy đổi thời gian thật đã trôi qua thành thời gian mô phỏng theo playbackSpeed.
    final dtSimulatedMs = (dtRealtime.inMilliseconds * state.playbackSpeed)
        .round();
    // Nhịp 0 ms không cần emit vì chưa tạo tiến triển quan sát được.
    if (dtSimulatedMs <= 0) return;

    final nextTime =
        (state.currentReplayTime ?? state.validSamples.first.measuredAt).add(
          Duration(milliseconds: dtSimulatedMs),
        );

    final lastSampleTime = state.validSamples.last.measuredAt;

    // Chạm hoặc vượt mốc cuối đều khóa con trỏ đúng tại mẫu cuối và chuyển completed.
    if (nextTime.isAfter(lastSampleTime) ||
        nextTime.isAtSameMomentAs(lastSampleTime)) {
      // Đã chạy tới đích cuối cùng
      _stopPlayback();
      final last = state.validSamples.last;
      emit(
        state.copyWith(
          status: JourneyHistoryStatus.completed,
          currentReplayTime: last.measuredAt,
          currentPosition: LatLng(last.latitude, last.longitude),
          currentHeadingDeg: last.headingDeg,
          currentSpeedMps: last.speedMps,
          currentSampleIndex: state.validSamples.length - 1,
        ),
      );
      return;
    }

    _updateReplayStateAtTime(nextTime);
  }

  /// Cập nhật vị trí, hướng, tốc độ nội suy tại mốc thời gian [targetTime]
  void _updateReplayStateAtTime(DateTime targetTime) {
    final samples = state.validSamples;
    // Guard rỗng bảo vệ cả lời gọi trực tiếp từ seek và tick.
    if (samples.isEmpty) return;

    // Một mẫu không cần nội suy; toàn bộ con trỏ được đồng bộ về chính mẫu đó.
    if (samples.length == 1) {
      final s = samples.first;
      emit(
        state.copyWith(
          currentReplayTime: s.measuredAt,
          currentPosition: LatLng(s.latitude, s.longitude),
          currentHeadingDeg: s.headingDeg,
          currentSpeedMps: s.speedMps,
          currentSampleIndex: 0,
        ),
      );
      return;
    }

    // Tìm đoạn chứa targetTime trong samples đã sắp xếp bằng tìm kiếm nhị phân O(log n).
    int low = 0;
    int high = samples.length - 1;
    int index = 0;

    // Sau vòng lặp, index là mẫu cuối cùng có measuredAt nhỏ hơn targetTime.
    while (low <= high) {
      final mid = low + ((high - low) >> 1);
      // Điểm giữa nằm trước target nên tiếp tục tìm về nửa phải.
      if (samples[mid].measuredAt.isBefore(targetTime)) {
        index = mid;
        low = mid + 1;
      } else {
        // Điểm giữa bằng/sau target nên thu hẹp về nửa trái.
        high = mid - 1;
      }
    }

    // clamp bảo vệ trường hợp index đang là mẫu cuối; khi đó p2 chính là p1.
    final p1 = samples[index];
    final p2 = samples[(index + 1).clamp(0, samples.length - 1)];

    final p1Time = p1.measuredAt;
    final p2Time = p2.measuredAt;

    final segmentGap = p2Time.difference(p1Time);

    // Khoảng cách thời gian vượt ngưỡng nghĩa là GPS mất tín hiệu hoặc thiết bị tắt lâu.
    // Không nội suy qua vùng không có dữ liệu; nhảy thẳng tới mẫu p2.
    if (segmentGap > state.gapThreshold) {
      emit(
        state.copyWith(
          currentReplayTime: p2.measuredAt,
          currentPosition: LatLng(p2.latitude, p2.longitude),
          currentHeadingDeg: p2.headingDeg,
          currentSpeedMps: p2.speedMps,
          currentSampleIndex: index + 1,
        ),
      );
      return;
    }

    final totalMs = p2Time.difference(p1Time).inMilliseconds;
    // Đoạn có cùng timestamp không chia cho 0 và dùng progress 0.
    final progress = totalMs > 0
        ? (targetTime.difference(p1Time).inMilliseconds / totalMs).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    // Nội suy vị trí hiển thị giữa p1 và p2
    final interpolatedPos = GpsValidator.interpolatePosition(
      LatLng(p1.latitude, p1.longitude),
      LatLng(p2.latitude, p2.longitude),
      progress,
    );

    // Ưu tiên heading thiết bị; thiếu heading thì tính hướng thật giữa hai điểm liên tiếp.
    final segmentBearing = GpsValidator.calculateBearing(
      LatLng(p1.latitude, p1.longitude),
      LatLng(p2.latitude, p2.longitude),
    );
    final heading = p1.headingDeg ?? segmentBearing;

    // Tốc độ tại thời điểm
    // Chỉ nội suy khi cả hai đầu có tốc độ; nếu thiếu một đầu thì dùng giá trị còn lại.
    final speed = p1.speedMps != null && p2.speedMps != null
        ? p1.speedMps! + (p2.speedMps! - p1.speedMps!) * progress
        : (p1.speedMps ?? p2.speedMps);

    emit(
      state.copyWith(
        currentReplayTime: targetTime,
        currentPosition: interpolatedPos,
        currentHeadingDeg: heading,
        currentSpeedMps: speed,
        currentSampleIndex: index,
      ),
    );
  }

  void _stopPlayback() {
    // Xóa cả timer và mốc tick để lần play sau không dùng chênh lệch thời gian cũ.
    _replayTimer?.cancel();
    _replayTimer = null;
    _lastTickRealtime = null;
  }

  static List<double> _computeCumulativeDistances(
    List<LocationModel> samples,
    Duration gapThreshold,
  ) {
    // Mỗi phần tử là tổng quãng đường tới mẫu cùng chỉ số; không cộng khoảng đứt
    // hành trình vì đó không phải quãng đường có dữ liệu xác nhận.
    // Danh sách rỗng dùng const để không cấp phát không cần thiết.
    if (samples.isEmpty) return const [];
    // Phần tử đầu luôn bằng 0 vì chưa có đoạn trước nó.
    final distances = List<double>.filled(samples.length, 0.0);
    var running = 0.0;
    for (var i = 1; i < samples.length; i++) {
      final prev = samples[i - 1];
      final curr = samples[i];
      // Chỉ cộng đoạn có khoảng thời gian liên tục theo ngưỡng gap hiện tại.
      if (curr.measuredAt.difference(prev.measuredAt) <= gapThreshold) {
        running += GpsValidator.calculateDistanceM(
          LatLng(prev.latitude, prev.longitude),
          LatLng(curr.latitude, curr.longitude),
        );
      }
      distances[i] = running;
    }
    return distances;
  }

  void _onSystemSettingsChanged(SystemSettingsModel value) {
    // Áp dụng ngưỡng server mới và tính lại toàn bộ số liệu suy ra từ cùng samples.
    final nextGap = _hasCustomGapThreshold
        ? state.gapThreshold
        : Duration(seconds: value.defaultGapThresholdSeconds);
    // Ngưỡng chuyển động luôn theo server vì giao diện không có override phiên riêng.
    final nextMovement = value.movementThresholdMps;
    // Khi chưa có mẫu, chỉ cập nhật ngưỡng để lần load kế tiếp dùng giá trị mới.
    if (state.validSamples.isEmpty) {
      emit(
        state.copyWith(
          gapThreshold: nextGap,
          movementThresholdMps: nextMovement,
        ),
      );
      return;
    }

    final summary = _buildSummary(
      state.validSamples,
      gapThreshold: nextGap,
      movementThresholdMps: nextMovement,
    );
    emit(
      state.copyWith(
        gapThreshold: nextGap,
        movementThresholdMps: nextMovement,
        segments: summary.segments,
        totalDistanceM: summary.totalDistanceM,
        movingDurationS: summary.movingDurationS,
        stoppedDurationS: summary.stoppedDurationS,
        maxSpeedMps: summary.maxSpeedMps,
        avgSpeedMps: summary.avgSpeedMps,
        cumulativeDistancesM: _computeCumulativeDistances(
          state.validSamples,
          nextGap,
        ),
      ),
    );
  }

  static _JourneySummary _buildSummary(
    List<LocationModel> samples, {
    required Duration gapThreshold,
    required double movementThresholdMps,
  }) {
    // Tập trung phép tổng hợp tại một nơi để loadHistory, đổi gap và đổi settings
    // luôn cho cùng kết quả đoạn đường, thời lượng và tốc độ.
    final segments = RouteSegment.splitIntoSegments(
      samples,
      gapThreshold: gapThreshold,
      movingThresholdMps: movementThresholdMps,
    );
    // Tổng hợp qua từng segment để khoảng gap không đóng góp khoảng cách/thời lượng giả.
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
      // maxSpeed giữ giá trị lớn nhất đã biết, bỏ segment không có tốc độ.
      if (segment.maxSpeedMps != null &&
          (maxSpeed == null || segment.maxSpeedMps! > maxSpeed)) {
        maxSpeed = segment.maxSpeedMps;
      }
      // Trung bình toàn hành trình được gia quyền theo số mẫu của từng segment.
      if (segment.avgSpeedMps != null) {
        speedSum += segment.avgSpeedMps! * segment.samples.length;
        speedCount += segment.samples.length;
      }
    }
    return _JourneySummary(
      segments: segments,
      totalDistanceM: totalDistance,
      movingDurationS: totalMoving,
      stoppedDurationS: totalStopped,
      maxSpeedMps: maxSpeed,
      avgSpeedMps: speedCount > 0 ? speedSum / speedCount : null,
    );
  }

  @override
  Future<void> close() async {
    _stopPlayback();
    await _settingsSubscription?.cancel();
    await super.close();
  }
}

class _JourneySummary {
  // Giá trị trung gian nội bộ gom kết quả tính toán trước một lần emit duy nhất.
  const _JourneySummary({
    required this.segments,
    required this.totalDistanceM,
    required this.movingDurationS,
    required this.stoppedDurationS,
    required this.maxSpeedMps,
    required this.avgSpeedMps,
  });

  final List<RouteSegment> segments;
  // Đơn vị giữ theo dữ liệu domain: mét, giây và mét/giây; widget chịu trách nhiệm format.
  final double totalDistanceM;
  final int movingDurationS;
  final int stoppedDurationS;
  final double? maxSpeedMps;
  final double? avgSpeedMps;
}
