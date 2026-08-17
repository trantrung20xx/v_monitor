import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';
import 'package:v_monitor/data/models/device_event_model.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/data/models/location_model.dart';
import 'package:v_monitor/data/repositories/device_repository.dart';
import 'package:v_monitor/data/repositories/geocoding_repository.dart';
import 'package:v_monitor/data/repositories/tracking_repository.dart';
import 'package:v_monitor/features/device_detail/device_detail_page.dart';

void main() {
  testWidgets('Events Tab renders filter chips and timeline items correctly', (
    tester,
  ) async {
    final deviceRepo = _MockDeviceRepository();
    final trackingRepo = _MockTrackingRepository();
    final geocodingRepo = _MockGeocodingRepository();
    addTearDown(deviceRepo.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<DeviceRepository>.value(value: deviceRepo),
            RepositoryProvider<TrackingRepository>.value(value: trackingRepo),
            RepositoryProvider<GeocodingRepository>.value(value: geocodingRepo),
          ],
          child: const DeviceDetailPage(deviceId: 'device-100'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Click on Events Tab (index 2)
    final eventsTabFinder = find.text('Sự kiện');
    expect(eventsTabFinder, findsOneWidget);
    await tester.tap(eventsTabFinder);
    await tester.pumpAndSettle();

    // Verify Category Filter Chips
    expect(find.text('Tất cả'), findsOneWidget);
    expect(find.text('Kết nối'), findsOneWidget);
    expect(find.text('Di chuyển'), findsOneWidget);
    expect(find.text('Cảnh báo & Khác'), findsOneWidget);

    // Verify Timeline Event Items
    expect(find.text('Thiết bị trực tuyến'), findsOneWidget);
    expect(find.text('Bắt đầu di chuyển'), findsOneWidget);
    expect(find.text('Dừng di chuyển'), findsOneWidget);
    expect(find.text('Tín hiệu GPS khôi phục'), findsOneWidget);

    // Tap on "Di chuyển" filter
    await tester.tap(find.text('Di chuyển'));
    await tester.pumpAndSettle();

    // In Movement filter, only movement events should show
    expect(find.text('Bắt đầu di chuyển'), findsOneWidget);
    expect(find.text('Dừng di chuyển'), findsOneWidget);
    expect(find.text('Thiết bị trực tuyến'), findsNothing);

    // Tap on "Kết nối" filter
    await tester.tap(find.text('Kết nối'));
    await tester.pumpAndSettle();

    expect(find.text('Thiết bị trực tuyến'), findsOneWidget);
    expect(find.text('Bắt đầu di chuyển'), findsNothing);

    // Emit live realtime event via WebSocket
    deviceRepo.emitEvent(
      DeviceEventModel(
        id: 'event-live-1',
        deviceId: 'device-100',
        eventType: 'OFFLINE',
        occurredAt: DateTime.now(),
        description: 'Mất kết nối thiết bị',
      ),
    );
    await tester.pumpAndSettle();

    // Newly emitted live OFFLINE event should appear in Connectivity tab
    expect(find.text('Thiết bị ngoại tuyến'), findsOneWidget);
    expect(find.text('Mất kết nối thiết bị'), findsOneWidget);
  });
}

class _MockDeviceRepository extends DeviceRepository {
  _MockDeviceRepository() : super(ApiClient(), WebsocketClient());

  final _deviceStream = StreamController<DeviceModel>.broadcast();
  final _eventStream = StreamController<DeviceEventModel>.broadcast();

  @override
  Stream<DeviceModel> get deviceUpdates => _deviceStream.stream;

  @override
  Stream<DeviceEventModel> get deviceEvents => _eventStream.stream;

  void emitEvent(DeviceEventModel event) => _eventStream.add(event);

  void dispose() {
    _deviceStream.close();
    _eventStream.close();
  }

  @override
  Future<DeviceModel?> getDevice(String id) async {
    return DeviceModel(
      id: id,
      deviceCode: 'UAV-100',
      name: 'Flycam 100',
      type: 'UAV_CONTROLLER',
      status: 'ONLINE',
      isOnline: true,
      latitude: 21.0322,
      longitude: 105.80776,
      currentAltitudeM: 36.5,
      currentSpeedMps: 12.5,
      currentHeadingDeg: 45,
      lastSeenAt: DateTime.now(),
    );
  }
}

class _MockTrackingRepository extends TrackingRepository {
  _MockTrackingRepository() : super(ApiClient());

  @override
  Future<List<DeviceEventModel>> getEvents(String id) async {
    final now = DateTime.now();
    return [
      DeviceEventModel(
        id: 'ev-1',
        deviceId: id,
        eventType: 'ONLINE',
        occurredAt: now.subtract(const Duration(minutes: 30)),
        description: 'Thiết bị kết nối trực tuyến',
      ),
      DeviceEventModel(
        id: 'ev-2',
        deviceId: id,
        eventType: 'MOVEMENT_STARTED',
        occurredAt: now.subtract(const Duration(minutes: 20)),
        description: 'Bắt đầu di chuyển (45.0 km/h)',
      ),
      DeviceEventModel(
        id: 'ev-3',
        deviceId: id,
        eventType: 'GPS_RESTORED',
        occurredAt: now.subtract(const Duration(minutes: 15)),
        description: 'Khôi phục tín hiệu GPS (14 vệ tinh)',
      ),
      DeviceEventModel(
        id: 'ev-4',
        deviceId: id,
        eventType: 'MOVEMENT_STOPPED',
        occurredAt: now.subtract(const Duration(minutes: 5)),
        description: 'Thiết bị đã dừng lại',
      ),
    ];
  }

  @override
  Future<List<LocationModel>> getLocationHistory(String id) async {
    return [];
  }
}

class _MockGeocodingRepository extends GeocodingRepository {
  _MockGeocodingRepository() : super(ApiClient());

  @override
  Future<String?> reverseAddress(
    double latitude,
    double longitude, {
    bool includeCoordinatesFallback = true,
  }) async {
    return '123 Đường Kim Mã, P. Kim Mã, Q. Ba Đình, Hà Nội';
  }
}
