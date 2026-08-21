import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/data/models/location_history_response.dart';
import 'package:v_monitor/data/models/location_model.dart';
import 'package:v_monitor/data/models/system_settings_model.dart';
import 'package:v_monitor/data/repositories/device_repository.dart';
import 'package:v_monitor/data/repositories/settings_repository.dart';
import 'package:v_monitor/data/repositories/tracking_repository.dart';
import 'package:v_monitor/features/journey_history/journey_history_cubit.dart';
import 'package:v_monitor/features/journey_history/journey_history_state.dart';

class _FakeTrackingRepo implements TrackingRepository {
  LocationHistoryResponse? rangeResponse;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<LocationHistoryResponse?> getLocationHistoryRange(
    String deviceId, {
    required DateTime from,
    required DateTime to,
    int? maxSamples,
  }) async {
    return rangeResponse;
  }
}

class _FakeDeviceRepo implements DeviceRepository {
  DeviceModel? singleDevice;
  List<DeviceModel> devices = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<DeviceModel?> getDevice(String id) async => singleDevice;

  @override
  Future<List<DeviceModel>> getDevices() async => devices;
}

class _FakeSettingsRepo implements SettingsRepository {
  _FakeSettingsRepo(this._settings);

  final _controller = StreamController<SystemSettingsModel>.broadcast();
  SystemSettingsModel _settings;

  @override
  SystemSettingsModel get systemSettings => _settings;

  @override
  Stream<SystemSettingsModel> get systemSettingsChanges => _controller.stream;

  void emitSystemSettings(SystemSettingsModel value) {
    _settings = value;
    _controller.add(value);
  }

  Future<void> close() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeTrackingRepo fakeTracking;
  late _FakeDeviceRepo fakeDevice;
  late _FakeSettingsRepo fakeSettings;
  late JourneyHistoryCubit cubit;

  final sampleDevice = DeviceModel(
    id: 'dev-1',
    deviceCode: 'CAR-001',
    name: 'Xe thử nghiệm 1',
    type: 'VEHICLE',
    status: 'ONLINE',
  );

  setUp(() {
    fakeTracking = _FakeTrackingRepo();
    fakeDevice = _FakeDeviceRepo()..singleDevice = sampleDevice;
    fakeSettings = _FakeSettingsRepo(
      const SystemSettingsModel(
        movementThresholdMps: 1,
        defaultGapThresholdSeconds: 420,
      ),
    );
    cubit = JourneyHistoryCubit(
      trackingRepo: fakeTracking,
      deviceRepo: fakeDevice,
      settingsRepo: fakeSettings,
    );
  });

  tearDown(() async {
    await cubit.close();
    await fakeSettings.close();
  });

  group('JourneyHistoryCubit Tests (Section 54, 68, 71)', () {
    test('Initial state is idle', () {
      expect(cubit.state.status, equals(JourneyHistoryStatus.idle));
      expect(cubit.state.validSamples, isEmpty);
      expect(cubit.state.playbackSpeed, equals(1.0));
      expect(cubit.state.followCamera, isTrue);
      expect(cubit.state.gapThreshold, const Duration(seconds: 420));
      expect(cubit.state.movementThresholdMps, 1);
    });

    test(
      'runtime settings update defaults but preserve a custom journey gap',
      () async {
        fakeSettings.emitSystemSettings(
          const SystemSettingsModel(
            movementThresholdMps: 2,
            defaultGapThresholdSeconds: 600,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state.gapThreshold, const Duration(seconds: 600));
        expect(cubit.state.movementThresholdMps, 2);

        cubit.setGapThreshold(const Duration(seconds: 900));
        fakeSettings.emitSystemSettings(
          const SystemSettingsModel(
            movementThresholdMps: 3,
            defaultGapThresholdSeconds: 300,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state.gapThreshold, const Duration(seconds: 900));
        expect(cubit.state.movementThresholdMps, 3);
      },
    );

    test(
      'Loads history and sorts samples chronologically ascending (Section 68)',
      () async {
        final t0 = DateTime(2026, 8, 16, 8, 0, 0);
        final t1 = DateTime(2026, 8, 16, 8, 15, 0);
        final t2 = DateTime(2026, 8, 16, 8, 30, 0);

        // Trả về không đúng thứ tự từ nguồn
        fakeTracking.rangeResponse = LocationHistoryResponse(
          deviceId: 'dev-1',
          fromTime: t0,
          toTime: t2,
          samples: [
            LocationModel(
              id: '2',
              deviceId: 'dev-1',
              measuredAt: t1,
              latitude: 21.01,
              longitude: 105.01,
            ),
            LocationModel(
              id: '3',
              deviceId: 'dev-1',
              measuredAt: t2,
              latitude: 21.02,
              longitude: 105.02,
            ),
            LocationModel(
              id: '1',
              deviceId: 'dev-1',
              measuredAt: t0,
              latitude: 21.00,
              longitude: 105.00,
            ),
          ],
          totalCount: 3,
        );

        await cubit.loadHistory(deviceId: 'dev-1', from: t0, to: t2);

        expect(cubit.state.status, equals(JourneyHistoryStatus.ready));
        expect(cubit.state.validSamples.length, equals(3));
        // Kiểm tra thứ tự đúng: t0 -> t1 -> t2
        expect(cubit.state.validSamples[0].id, equals('1'));
        expect(cubit.state.validSamples[1].id, equals('2'));
        expect(cubit.state.validSamples[2].id, equals('3'));
        expect(cubit.state.currentPosition, isNotNull);
      },
    );

    test('Handles empty history data gracefully (Section 44)', () async {
      final t0 = DateTime(2026, 8, 16, 8, 0, 0);
      final t1 = DateTime(2026, 8, 16, 9, 0, 0);

      fakeTracking.rangeResponse = LocationHistoryResponse(
        deviceId: 'dev-1',
        fromTime: t0,
        toTime: t1,
        samples: const [],
        totalCount: 0,
      );

      await cubit.loadHistory(deviceId: 'dev-1', from: t0, to: t1);

      expect(cubit.state.status, equals(JourneyHistoryStatus.ready));
      expect(cubit.state.isEmpty, isTrue);
      expect(cubit.state.validSamples, isEmpty);
    });

    test('Handles single-point history properly (Section 45)', () async {
      final t0 = DateTime(2026, 8, 16, 8, 0, 0);
      final t1 = DateTime(2026, 8, 16, 9, 0, 0);

      fakeTracking.rangeResponse = LocationHistoryResponse(
        deviceId: 'dev-1',
        fromTime: t0,
        toTime: t1,
        samples: [
          LocationModel(
            id: '1',
            deviceId: 'dev-1',
            measuredAt: t0,
            latitude: 21.00,
            longitude: 105.00,
          ),
        ],
        totalCount: 1,
      );

      await cubit.loadHistory(deviceId: 'dev-1', from: t0, to: t1);

      expect(cubit.state.hasSinglePoint, isTrue);
      expect(cubit.state.hasRoute, isFalse);
    });

    test(
      'Play, Pause, Resume, Reset, Seek, Speed, and Device Switch (Section 71 & 47)',
      () async {
        final t0 = DateTime(2026, 8, 16, 8, 0, 0);
        final t1 = DateTime(2026, 8, 16, 8, 2, 0);

        fakeTracking.rangeResponse = LocationHistoryResponse(
          deviceId: 'dev-1',
          fromTime: t0,
          toTime: t1,
          samples: [
            LocationModel(
              id: '1',
              deviceId: 'dev-1',
              measuredAt: t0,
              latitude: 21.00,
              longitude: 105.00,
            ),
            LocationModel(
              id: '2',
              deviceId: 'dev-1',
              measuredAt: t1,
              latitude: 21.01,
              longitude: 105.01,
            ),
          ],
          totalCount: 2,
        );

        await cubit.loadHistory(deviceId: 'dev-1', from: t0, to: t1);

        // Play
        cubit.play();
        expect(cubit.state.status, equals(JourneyHistoryStatus.playing));

        // Pause
        cubit.pause();
        expect(cubit.state.status, equals(JourneyHistoryStatus.paused));

        // Resume
        cubit.resume();
        expect(cubit.state.status, equals(JourneyHistoryStatus.playing));

        // Change speed to 16x
        cubit.setPlaybackSpeed(16.0);
        expect(cubit.state.playbackSpeed, equals(16.0));

        // Seek progress 50% (1 minute in, 8:01:00)
        cubit.seekToProgress(0.5);
        expect(cubit.state.currentPosition, isNotNull);
        final midTime = cubit.state.currentReplayTime!;
        expect(midTime, equals(DateTime(2026, 8, 16, 8, 1, 0)));

        // Step forward 30s (8:01:30)
        cubit.stepForward(const Duration(seconds: 30));
        expect(
          cubit.state.currentReplayTime,
          equals(DateTime(2026, 8, 16, 8, 1, 30)),
        );

        // Step forward 60s (8:02:00 / clamps to t1)
        cubit.stepForward(const Duration(seconds: 60));
        expect(cubit.state.currentReplayTime, equals(t1));

        // Seek back to 8:01:30
        cubit.seekToTime(DateTime(2026, 8, 16, 8, 1, 30));

        // Step backward 30s (8:01:00)
        cubit.stepBackward(const Duration(seconds: 30));
        expect(
          cubit.state.currentReplayTime,
          equals(DateTime(2026, 8, 16, 8, 1, 0)),
        );

        // Step backward 60s (8:00:00 / clamps to t0)
        cubit.stepBackward(const Duration(seconds: 60));
        expect(cubit.state.currentReplayTime, equals(t0));

        // Reset
        cubit.reset();
        expect(cubit.state.currentReplayTime, equals(t0));

        // Chuyển sang một thiết bị khác phải xóa dữ liệu phát lại của thiết bị cũ.
        final dev2 = DeviceModel(
          id: 'dev-2',
          deviceCode: 'CTRL-002',
          name: 'Tay điều khiển 2',
          type: 'UAV_CONTROLLER',
          status: 'ONLINE',
        );
        cubit.selectDevice(dev2);
        expect(cubit.state.selectedDevice?.id, equals('dev-2'));
        expect(cubit.state.validSamples, isEmpty);
      },
    );
  });
}
