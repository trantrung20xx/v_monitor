// Xác nhận danh sách nổi lọc thiết bị và vừa viewport di động không overflow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/features/map/widgets/device_list_overlay.dart';

void main() {
  testWidgets('DeviceListOverlay filters and fits in a mobile viewport', (
    tester,
  ) async {
    final now = DateTime.now();
    final devices = [
      _device(
        id: 'alpha',
        name: 'Xe Alpha',
        code: 'XE-ALPHA',
        speedMps: 9,
        lastSeenAt: now.subtract(const Duration(seconds: 30)),
      ),
      _device(
        id: 'bravo',
        name: 'Xe Bravo',
        code: 'XE-BRAVO',
        speedMps: 0,
        lastSeenAt: now.subtract(const Duration(seconds: 40)),
      ),
      _device(
        id: 'charlie',
        name: 'Xe Charlie',
        code: 'XE-CHARLIE',
        speedMps: 12,
        lastSeenAt: now.subtract(const Duration(minutes: 4)),
      ),
    ];

    await _pumpAtSize(
      tester,
      const Size(360, 720),
      DeviceListOverlay(devices: devices, onDeviceSelected: (_) {}),
    );

    expect(find.text('Thiết bị trên bản đồ'), findsOneWidget);
    expect(find.text('Xe Alpha'), findsOneWidget);
    expect(find.text('Xe Bravo'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Di chuyển'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Di chuyển'));
    await tester.pumpAndSettle();

    expect(find.text('Xe Alpha'), findsOneWidget);
    expect(find.text('Xe Bravo'), findsNothing);

    await tester.enterText(find.byType(TextField), 'charlie');
    await tester.pumpAndSettle();

    expect(find.text('Không tìm thấy thiết bị phù hợp'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

DeviceModel _device({
  required String id,
  required String name,
  required String code,
  required double speedMps,
  required DateTime lastSeenAt,
}) {
  return DeviceModel(
    id: id,
    deviceCode: code,
    name: name,
    type: 'VEHICLE',
    status: 'ACTIVE',
    isOnline: true,
    currentSpeedMps: speedMps,
    lastSeenAt: lastSeenAt,
    latitude: 21.0,
    longitude: 105.0,
  );
}

Future<void> _pumpAtSize(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
