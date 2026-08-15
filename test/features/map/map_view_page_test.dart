import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/data/repositories/device_repository.dart';
import 'package:v_monitor/data/repositories/geocoding_repository.dart';
import 'package:v_monitor/features/map/map_view_page.dart';

void main() {
  testWidgets('MapViewPage renders map controls and handles taps safely', (
    tester,
  ) async {
    final deviceRepo = _FakeDeviceRepository();
    final geocodingRepo = _FakeGeocodingRepository();
    final flutterErrors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      flutterErrors.add(details);
      previousOnError?.call(details);
    };
    addTearDown(deviceRepo.dispose);
    addTearDown(() => FlutterError.onError = previousOnError);

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<DeviceRepository>.value(value: deviceRepo),
          RepositoryProvider<GeocodingRepository>.value(value: geocodingRepo),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const MapViewPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await tester.pump();

    expect(
      flutterErrors
          .where(
            (details) =>
                details.exceptionAsString().contains('overflowed by') ||
                details.exceptionAsString().contains('A RenderFlex overflowed'),
          )
          .toList(),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}

class _FakeDeviceRepository extends DeviceRepository {
  _FakeDeviceRepository() : super(ApiClient(), WebsocketClient());

  final _updates = StreamController<DeviceModel>.broadcast();

  @override
  Stream<DeviceModel> get deviceUpdates => _updates.stream;

  @override
  Future<List<DeviceModel>> getDevices() async {
    final now = DateTime.now();
    return [
      DeviceModel(
        id: 'device-map-1',
        deviceCode: 'GPS-001',
        name: 'GPS Unit 001',
        type: 'VEHICLE',
        status: 'ACTIVE',
        isOnline: true,
        latitude: 21.0322,
        longitude: 105.80776,
        currentSpeedMps: 8.5,
        currentHeadingDeg: 45,
        lastSeenAt: now.subtract(const Duration(seconds: 20)),
      ),
    ];
  }

  void dispose() {
    _updates.close();
  }
}

class _FakeGeocodingRepository extends GeocodingRepository {
  _FakeGeocodingRepository() : super(ApiClient());

  @override
  Future<String?> reverseAddress(double latitude, double longitude) async {
    return 'Duong Cau Giay, Thu Le, Ha Noi, Viet Nam';
  }
}
