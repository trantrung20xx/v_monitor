import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/data/models/location_history_response.dart';
import 'package:v_monitor/data/models/location_model.dart';
import 'package:v_monitor/data/repositories/device_repository.dart';
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

void main() {
  late _FakeTrackingRepo fakeTracking;
  late _FakeDeviceRepo fakeDevice;
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
    cubit = JourneyHistoryCubit(
      trackingRepo: fakeTracking,
      deviceRepo: fakeDevice,
    );
  });

  tearDown(() {
    cubit.close();
  });

  group('JourneyHistoryCubit Tests (Section 54, 68, 71)', () {
    test('Initial state is idle', () {
      expect(cubit.state.status, equals(JourneyHistoryStatus.idle));
      expect(cubit.state.validSamples, isEmpty);
      expect(cubit.state.playbackSpeed, equals(1.0));
      expect(cubit.state.followCamera, isTrue);
    });

    test('Loads history and sorts samples chronologically ascending (Section 68)', () async {
      final t0 = DateTime(2026, 8, 16, 8, 0, 0);
      final t1 = DateTime(2026, 8, 16, 8, 15, 0);
      final t2 = DateTime(2026, 8, 16, 8, 30, 0);

      // Trả về không đúng thứ tự từ nguồn
      fakeTracking.rangeResponse = LocationHistoryResponse(
        deviceId: 'dev-1',
        fromTime: t0,
        toTime: t2,
        samples: [
          LocationModel(id: '2', deviceId: 'dev-1', measuredAt: t1, latitude: 21.01, longitude: 105.01),
          LocationModel(id: '3', deviceId: 'dev-1', measuredAt: t2, latitude: 21.02, longitude: 105.02),
          LocationModel(id: '1', deviceId: 'dev-1', measuredAt: t0, latitude: 21.00, longitude: 105.00),
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
    });

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
          LocationModel(id: '1', deviceId: 'dev-1', measuredAt: t0, latitude: 21.00, longitude: 105.00),
        ],
        totalCount: 1,
      );

      await cubit.loadHistory(deviceId: 'dev-1', from: t0, to: t1);

      expect(cubit.state.hasSinglePoint, isTrue);
      expect(cubit.state.hasRoute, isFalse);
    });

    test('Play, Pause, Resume, Reset, Seek, Speed, and Device Switch (Section 71 & 47)', () async {
      final t0 = DateTime(2026, 8, 16, 8, 0, 0);
      final t1 = DateTime(2026, 8, 16, 8, 10, 0);

      fakeTracking.rangeResponse = LocationHistoryResponse(
        deviceId: 'dev-1',
        fromTime: t0,
        toTime: t1,
        samples: [
          LocationModel(id: '1', deviceId: 'dev-1', measuredAt: t0, latitude: 21.00, longitude: 105.00),
          LocationModel(id: '2', deviceId: 'dev-1', measuredAt: t1, latitude: 21.01, longitude: 105.01),
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

      // Change speed
      cubit.setPlaybackSpeed(2.0);
      expect(cubit.state.playbackSpeed, equals(2.0));

      // Seek progress 50%
      cubit.seekToProgress(0.5);
      expect(cubit.state.currentPosition, isNotNull);

      // Reset
      cubit.reset();
      expect(cubit.state.currentReplayTime, equals(t0));

      // Switch device
      final dev2 = DeviceModel(id: 'dev-2', deviceCode: 'FLY-002', name: 'Flycam 2', type: 'UAV_CONTROLLER', status: 'ONLINE');
      cubit.selectDevice(dev2);
      expect(cubit.state.selectedDevice?.id, equals('dev-2'));
      expect(cubit.state.validSamples, isEmpty);
    });
  });
}
