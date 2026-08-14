import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';
import 'package:v_monitor/data/models/assignment_model.dart';
import 'package:v_monitor/data/models/device_event_model.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/data/models/location_model.dart';
import 'package:v_monitor/data/models/usage_session_model.dart';
import 'package:v_monitor/data/repositories/device_repository.dart';
import 'package:v_monitor/data/repositories/geocoding_repository.dart';
import 'package:v_monitor/data/repositories/tracking_repository.dart';
import 'package:v_monitor/features/device_detail/device_detail_page.dart';

void main() {
  testWidgets('DeviceDetailPage avoids card overflow across viewport sizes', (
    tester,
  ) async {
    final deviceRepo = _FakeDeviceRepository();
    final trackingRepo = _FakeTrackingRepository();
    final geocodingRepo = _FakeGeocodingRepository();
    final flutterErrors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      flutterErrors.add(details);
      previousOnError?.call(details);
    };
    addTearDown(deviceRepo.dispose);
    addTearDown(() => FlutterError.onError = previousOnError);

    for (final scenario in const [
      _ViewportScenario(Size(320, 740), 3),
      _ViewportScenario(Size(360, 800), 3),
      _ViewportScenario(Size(390, 844), 3),
      _ViewportScenario(Size(430, 932), 3),
      _ViewportScenario(Size(768, 1024), 2),
      _ViewportScenario(Size(1024, 768), 1.5),
      _ViewportScenario(Size(1280, 800), 1),
      _ViewportScenario(Size(1440, 900), 1),
      _ViewportScenario(Size(1920, 1080), 1),
    ]) {
      await _pumpDetailAtSize(
        tester,
        scenario,
        deviceRepo: deviceRepo,
        trackingRepo: trackingRepo,
        geocodingRepo: geocodingRepo,
      );

      expect(find.text('Flycam 100'), findsWidgets);
      expect(find.text('Tổng quan'), findsOneWidget);
      expect(find.text('Hành trình'), findsWidgets);
      expect(find.text('Lịch sử sử dụng'), findsOneWidget);
      expect(find.text('Sự kiện'), findsOneWidget);
      expect(find.text('Vị trí hiện tại'), findsOneWidget);
      expect(find.text('Phiên sử dụng'), findsOneWidget);
      expect(find.text('Hành trình hiện tại'), findsOneWidget);
      expect(find.text('Hoạt động gần đây'), findsOneWidget);
      expect(
        flutterErrors
            .where(
              (details) =>
                  details.exceptionAsString().contains('overflowed by') ||
                  details.exceptionAsString().contains(
                    'A RenderFlex overflowed',
                  ),
            )
            .toList(),
        isEmpty,
      );
      flutterErrors.clear();
      expect(tester.takeException(), isNull);
    }
  });
}

class _ViewportScenario {
  const _ViewportScenario(this.logicalSize, this.devicePixelRatio);

  final Size logicalSize;
  final double devicePixelRatio;
}

Future<void> _pumpDetailAtSize(
  WidgetTester tester,
  _ViewportScenario scenario, {
  required DeviceRepository deviceRepo,
  required TrackingRepository trackingRepo,
  required GeocodingRepository geocodingRepo,
}) async {
  tester.view.devicePixelRatio = scenario.devicePixelRatio;
  tester.view.physicalSize = Size(
    scenario.logicalSize.width * scenario.devicePixelRatio,
    scenario.logicalSize.height * scenario.devicePixelRatio,
  );
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
  await tester.pump(const Duration(milliseconds: 600));
}

class _FakeDeviceRepository extends DeviceRepository {
  _FakeDeviceRepository() : super(ApiClient(), WebsocketClient());

  final _updates = StreamController<DeviceModel>.broadcast();

  @override
  Stream<DeviceModel> get deviceUpdates => _updates.stream;

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
      currentPersonName: 'Nguyễn Văn A',
      lastSeenAt: DateTime.now().subtract(const Duration(seconds: 12)),
    );
  }

  @override
  Future<List<AssignmentModel>> getDeviceAssignments(String id) async => [];

  @override
  Future<List<UsageSessionModel>> getDeviceUsages(String id) async {
    final startedAt = DateTime.now().subtract(
      const Duration(hours: 2, minutes: 14),
    );
    return [
      UsageSessionModel(
        id: 'usage-1',
        deviceId: id,
        personId: 'person-1',
        startedAt: startedAt,
        distanceM: 23700,
        avgSpeedMps: 7.8,
        maxSpeedMps: 16.9,
        movingDurationS: 6120,
        stoppedDurationS: 1920,
        status: 'ACTIVE',
        personName: 'Nguyễn Văn A',
        personCode: 'NV-012',
      ),
    ];
  }

  void dispose() {
    _updates.close();
  }
}

class _FakeTrackingRepository extends TrackingRepository {
  _FakeTrackingRepository() : super(ApiClient());

  @override
  Future<List<DeviceEventModel>> getEvents(String deviceId) async => [
    DeviceEventModel(
      id: 'event-1',
      deviceId: deviceId,
      eventType: 'MOVEMENT_STARTED',
      occurredAt: DateTime.now().subtract(const Duration(minutes: 8)),
    ),
  ];

  @override
  Future<List<LocationModel>> getLocationHistory(String deviceId) async {
    final now = DateTime.now();
    return [
      LocationModel(
        id: 'loc-3',
        deviceId: deviceId,
        measuredAt: now.subtract(const Duration(minutes: 1)),
        latitude: 21.0322,
        longitude: 105.80776,
        altitudeM: 36.5,
        speedMps: 12.5,
        headingDeg: 45,
        accuracyM: 4,
      ),
      LocationModel(
        id: 'loc-2',
        deviceId: deviceId,
        measuredAt: now.subtract(const Duration(minutes: 6)),
        latitude: 21.0299,
        longitude: 105.8052,
        speedMps: 11.2,
        headingDeg: 45,
      ),
      LocationModel(
        id: 'loc-1',
        deviceId: deviceId,
        measuredAt: now.subtract(const Duration(minutes: 12)),
        latitude: 21.0275,
        longitude: 105.8028,
        speedMps: 0,
        headingDeg: 45,
      ),
    ];
  }
}

class _FakeGeocodingRepository extends GeocodingRepository {
  _FakeGeocodingRepository() : super(ApiClient());

  @override
  Future<String?> reverseAddress(double latitude, double longitude) async {
    return 'Cầu Giấy, Hà Nội';
  }
}
