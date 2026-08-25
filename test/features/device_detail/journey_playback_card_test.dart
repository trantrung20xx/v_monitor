// Xác nhận thẻ phát lại hành trình giữ đủ bước tua, tốc độ và điều khiển chính.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/data/models/location_history_response.dart';
import 'package:v_monitor/data/models/location_model.dart';
import 'package:v_monitor/data/repositories/device_repository.dart';
import 'package:v_monitor/data/repositories/geocoding_repository.dart';
import 'package:v_monitor/data/repositories/tracking_repository.dart';
import 'package:v_monitor/features/device_detail/device_detail_page.dart';

import '../../support/settings_test_scope.dart';

void main() {
  testWidgets(
    'DeviceDetailPage Journey tab renders 30s step buttons and 16x speed option',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final deviceRepo = _FakeDeviceRepository();
      final trackingRepo = _FakeTrackingRepository();
      final geocodingRepo = _FakeGeocodingRepository();

      final t0 = DateTime(2026, 8, 16, 8, 0, 0);
      final t1 = DateTime(2026, 8, 16, 8, 2, 0);

      trackingRepo.historyResponse = LocationHistoryResponse(
        deviceId: 'device-100',
        fromTime: t0,
        toTime: t1,
        samples: [
          LocationModel(
            id: '1',
            deviceId: 'device-100',
            measuredAt: t0,
            latitude: 21.00,
            longitude: 105.00,
          ),
          LocationModel(
            id: '2',
            deviceId: 'device-100',
            measuredAt: t1,
            latitude: 21.01,
            longitude: 105.01,
          ),
        ],
        totalCount: 2,
      );

      await tester.pumpWidget(
        SettingsTestScope(
          child: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<DeviceRepository>.value(value: deviceRepo),
              RepositoryProvider<TrackingRepository>.value(value: trackingRepo),
              RepositoryProvider<GeocodingRepository>.value(
                value: geocodingRepo,
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const DeviceDetailPage(deviceId: 'device-100'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Journey tab (Hành trình)
      await tester.tap(find.text('Hành trình').first);
      await tester.pumpAndSettle();

      final leftPanel = find.byKey(const Key('journey-desktop-left-panel'));
      final timelinePanel = find.byKey(const Key('journey-timeline-card'));
      final mapPanel = find.byKey(const Key('journey-map-card-surface'));
      expect(tester.getSize(leftPanel).height, 596);
      expect(tester.getSize(timelinePanel).height, 596);
      expect(
        tester.getBottomLeft(leftPanel).dy,
        closeTo(tester.getBottomLeft(timelinePanel).dy, 0.01),
      );
      expect(tester.getSize(mapPanel).height, lessThan(596));

      // Timeline và nhãn bản đồ mô tả đầy đủ các node của lộ trình.
      expect(find.text('Lộ trình'), findsNothing);
      expect(find.text('Hướng đi'), findsNothing);
      expect(find.text('Đỗ từ 5 phút'), findsNothing);
      expect(find.text('Lộ trình di chuyển'), findsOneWidget);
      expect(find.text('Vị trí được ghi nhận liên tục'), findsOneWidget);
      expect(find.textContaining('Không có điểm đỗ'), findsNothing);
      expect(find.text('16/08/2026 · 08:00:00'), findsWidgets);
      expect(find.text('16/08/2026 · 08:02:00'), findsWidgets);
      expect(find.byTooltip('Ẩn nhãn mốc hành trình'), findsOneWidget);
      expect(find.text('Số lần đỗ xe'), findsOneWidget);
      expect(find.textContaining('chặng'), findsNothing);
      expect(find.text('Số mẫu GPS'), findsNothing);
      expect(find.text('Vị trí GPS'), findsOneWidget);
      expect(find.text('21.00000° N, 105.00000° E'), findsOneWidget);
      expect(find.textContaining('Hướng di chuyển'), findsNothing);
      expect(find.text('Hà Nội'), findsWidgets);

      await tester.tap(find.byTooltip('Ẩn nhãn mốc hành trình'));
      await tester.pump();
      expect(find.byTooltip('Hiện nhãn mốc hành trình'), findsOneWidget);

      // Verify 60s and 30s replay buttons and speed
      expect(find.byIcon(Icons.fast_rewind_rounded), findsOneWidget);
      expect(find.byIcon(Icons.replay_30_rounded), findsOneWidget);
      expect(find.byIcon(Icons.forward_30_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fast_forward_rounded), findsOneWidget);
      expect(find.text('1x'), findsWidgets);

      // Tap speed dropdown
      await tester.ensureVisible(find.text('1x').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('1x').first);
      await tester.pumpAndSettle();
      expect(find.text('16x'), findsWidgets);
    },
  );
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
      deviceCode: 'CTRL-100',
      name: 'Tay điều khiển 100',
      type: 'UAV_CONTROLLER',
      status: 'ONLINE',
      latitude: 21.0285,
      longitude: 105.8542,
    );
  }

  @override
  Future<List<DeviceModel>> getDevices() async => [];
}

class _FakeTrackingRepository extends TrackingRepository {
  _FakeTrackingRepository() : super(ApiClient());
  LocationHistoryResponse? historyResponse;

  @override
  Future<LocationHistoryResponse?> getLocationHistoryRange(
    String deviceId, {
    required DateTime from,
    required DateTime to,
    int? maxSamples,
  }) async {
    return historyResponse;
  }

  @override
  Future<List<LocationModel>> getLocationHistory(String deviceId) async => [];
}

class _FakeGeocodingRepository extends GeocodingRepository {
  _FakeGeocodingRepository() : super(ApiClient());

  @override
  Future<String?> reverseAddress(double latitude, double longitude) async =>
      'Hà Nội';
}
