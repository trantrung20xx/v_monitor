import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';
import 'package:v_monitor/data/models/device_event_model.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/data/models/location_history_response.dart';
import 'package:v_monitor/data/models/location_model.dart';
import 'package:v_monitor/data/repositories/device_repository.dart';
import 'package:v_monitor/data/repositories/geocoding_repository.dart';
import 'package:v_monitor/data/repositories/tracking_repository.dart';
import 'package:v_monitor/features/device_detail/device_detail_cubit.dart';
import 'package:v_monitor/features/device_detail/device_detail_page.dart';

void main() {
  group('DeviceDetail Address Persistence Tests', () {
    late _ControlledDeviceRepository deviceRepo;
    late _ControlledTrackingRepository trackingRepo;
    late _ControlledGeocodingRepository geocodingRepo;

    setUp(() {
      deviceRepo = _ControlledDeviceRepository();
      trackingRepo = _ControlledTrackingRepository();
      geocodingRepo = _ControlledGeocodingRepository();
    });

    tearDown(() {
      deviceRepo.dispose();
    });

    test('DeviceDetailCubit does NOT clear address when location updates to a new coordinate', () async {
      geocodingRepo.customAddresses = {
        '21.03220,105.80776': '123 Đường Kim Mã, P. Kim Mã, Q. Ba Đình, Hà Nội',
        '21.03500,105.81000': '456 Đường Cầu Giấy, P. Dịch Vọng, Q. Cầu Giấy, Hà Nội',
      };

      final cubit = DeviceDetailCubit(
        deviceId: 'device-100',
        deviceRepo: deviceRepo,
        trackingRepo: trackingRepo,
        geocodingRepo: geocodingRepo,
      );

      // Load initial state
      await cubit.load();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(cubit.state.address, equals('123 Đường Kim Mã, P. Kim Mã, Q. Ba Đình, Hà Nội'));

      // Set geocoding to be pending / delayed for next coordinate
      final completer = Completer<String?>();
      geocodingRepo.delayedCompleter = completer;

      // Simulate live device location update to new coordinates
      final baseDevice = (await deviceRepo.getDevice('device-100'))!;
      final updatedDevice = DeviceModel(
        id: baseDevice.id,
        deviceCode: baseDevice.deviceCode,
        name: baseDevice.name,
        type: baseDevice.type,
        status: baseDevice.status,
        isOnline: true,
        latitude: 21.0350,
        longitude: 105.8100,
        currentAltitudeM: 40.0,
        currentSpeedMps: 15.0,
        currentHeadingDeg: 90,
        lastSeenAt: DateTime.now(),
      );

      deviceRepo.emitUpdate(updatedDevice);
      await pumpEventQueue();

      // Immediately after update (while geocoding is still pending), address MUST NOT be null (preserving UI block)
      expect(cubit.state.address, equals('123 Đường Kim Mã, P. Kim Mã, Q. Ba Đình, Hà Nội'));
      expect(cubit.state.device?.latitude, equals(21.0350));

      // Resolve delayed geocoding
      completer.complete('456 Đường Cầu Giấy, P. Dịch Vọng, Q. Cầu Giấy, Hà Nội');
      await pumpEventQueue();

      // Address updates cleanly to new text
      expect(cubit.state.address, equals('456 Đường Cầu Giấy, P. Dịch Vọng, Q. Cầu Giấy, Hà Nội'));

      await cubit.close();
    });

    testWidgets('DeviceDetailPage keeps address block rendered while live location changes', (
      tester,
    ) async {
      geocodingRepo.customAddresses = {
        '21.03220,105.80776': '123 Đường Kim Mã, P. Kim Mã, Q. Ba Đình, Hà Nội',
        '21.03500,105.81000': '456 Đường Cầu Giấy, P. Dịch Vọng, Q. Cầu Giấy, Hà Nội',
      };

      final completer = Completer<String?>();
      geocodingRepo.delayedCompleter = null;

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<DeviceRepository>.value(value: deviceRepo),
            RepositoryProvider<TrackingRepository>.value(value: trackingRepo),
            RepositoryProvider<GeocodingRepository>.value(value: geocodingRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const DeviceDetailPage(deviceId: 'device-100'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Verify initial address is rendered
      expect(find.textContaining('123 Đường Kim Mã'), findsOneWidget);

      // Make subsequent geocoding requests wait on completer
      geocodingRepo.delayedCompleter = completer;

      // Trigger live coordinate update
      final baseDevice = (await deviceRepo.getDevice('device-100'))!;
      deviceRepo.emitUpdate(
        DeviceModel(
          id: baseDevice.id,
          deviceCode: baseDevice.deviceCode,
          name: baseDevice.name,
          type: baseDevice.type,
          status: baseDevice.status,
          isOnline: true,
          latitude: 21.0350,
          longitude: 105.8100,
          currentAltitudeM: 40.0,
          currentSpeedMps: 18.0,
          currentHeadingDeg: 90,
          lastSeenAt: DateTime.now(),
        ),
      );

      await tester.pump();

      // The address block MUST STILL BE PRESENT in the widget tree (no flicker / disappearance)
      expect(find.textContaining('123 Đường Kim Mã'), findsOneWidget);
      expect(find.byIcon(Icons.location_on_rounded), findsWidgets);

      // Now complete the geocoding request
      completer.complete('456 Đường Cầu Giấy, P. Dịch Vọng, Q. Cầu Giấy, Hà Nội');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The address text is seamlessly updated to the new address
      expect(find.textContaining('456 Đường Cầu Giấy'), findsOneWidget);
      expect(find.textContaining('123 Đường Kim Mã'), findsNothing);
    });
  });
}

class _ControlledDeviceRepository extends DeviceRepository {
  _ControlledDeviceRepository() : super(ApiClient(), WebsocketClient());

  final _updates = StreamController<DeviceModel>.broadcast();

  @override
  Stream<DeviceModel> get deviceUpdates => _updates.stream;

  void emitUpdate(DeviceModel device) {
    _updates.add(device);
  }

  @override
  Future<DeviceModel?> getDevice(String id) async {
    return DeviceModel(
      id: id,
      deviceCode: 'UAV-100',
      name: 'Flycam 100',
      type: 'UAV_CONTROLLER',
      status: 'UNKNOWN',
      isOnline: true,
      latitude: 21.0322,
      longitude: 105.80776,
      currentAltitudeM: 36.5,
      currentSpeedMps: 12.5,
      currentHeadingDeg: 45,
      lastSeenAt: DateTime.now().subtract(const Duration(seconds: 12)),
    );
  }

  void dispose() {
    _updates.close();
  }
}

class _ControlledTrackingRepository extends TrackingRepository {
  _ControlledTrackingRepository() : super(ApiClient());

  @override
  Future<List<DeviceEventModel>> getEvents(
    String id, {
    int limit = 50,
    int skip = 0,
  }) async {
    final now = DateTime.now();
    return [
      DeviceEventModel(
        id: 'event-1',
        deviceId: id,
        eventType: 'MOVEMENT_STARTED',
        occurredAt: now.subtract(const Duration(minutes: 5)),
        source: 'gps',
      ),
    ];
  }

  @override
  Future<List<LocationModel>> getLocationHistory(
    String id, {
    DateTime? startTime,
    DateTime? endTime,
    int limit = 1000,
  }) async {
    final now = DateTime.now();
    return [
      LocationModel(
        id: 'loc-1',
        deviceId: id,
        latitude: 21.0322,
        longitude: 105.80776,
        measuredAt: now.subtract(const Duration(seconds: 12)),
        altitudeM: 36.5,
        speedMps: 12.5,
        headingDeg: 45,
        accuracyM: 3,
        satelliteCount: 14,
      ),
    ];
  }

  @override
  Future<LocationHistoryResponse?> getLocationHistoryRange(
    String deviceId, {
    required DateTime from,
    required DateTime to,
    int? maxSamples,
  }) async {
    final samples = await getLocationHistory(deviceId);
    return LocationHistoryResponse(
      deviceId: deviceId,
      fromTime: from,
      toTime: to,
      samples: samples,
      totalCount: samples.length,
      truncated: false,
    );
  }
}

class _ControlledGeocodingRepository extends GeocodingRepository {
  _ControlledGeocodingRepository() : super(ApiClient());

  Map<String, String> customAddresses = {};
  Completer<String?>? delayedCompleter;

  @override
  Future<String?> reverseAddress(
    double latitude,
    double longitude, {
    bool includeCoordinatesFallback = true,
  }) async {
    if (delayedCompleter != null) {
      return delayedCompleter!.future;
    }
    final key = '${latitude.toStringAsFixed(5)},${longitude.toStringAsFixed(5)}';
    return customAddresses[key] ?? 'Địa chỉ mặc định ($key)';
  }
}
