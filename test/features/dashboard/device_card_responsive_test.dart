import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/features/dashboard/widgets/device_card.dart';

void main() {
  testWidgets('DeviceCard stays balanced on narrow and wide viewports', (
    tester,
  ) async {
    final device = DeviceModel(
      id: 'device-1',
      deviceCode: 'VM-ALPHA-0001',
      name: 'Xe tuần tra khu vực trung tâm',
      type: 'VEHICLE',
      status: 'ACTIVE',
      isOnline: true,
      latitude: 21.028511,
      longitude: 105.804817,
      currentSpeedMps: 8.4,
      currentHeadingDeg: 45.0,
      lastSeenAt: DateTime.now().subtract(const Duration(seconds: 20)),
    );

    await _pumpAtSize(
      tester,
      const Size(320, 640),
      DeviceCard(
        device: device,
        address:
            '123 đường kiểm thử responsive, phường mô phỏng, thành phố Hà Nội',
        onTap: () {},
      ),
    );

    expect(find.text('Xe tuần tra khu vực trung tâm'), findsOneWidget);
    expect(find.text('VM-ALPHA-0001'), findsOneWidget);
    expect(find.text('Hướng: Đông Bắc · 45°'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _pumpAtSize(
      tester,
      const Size(1024, 768),
      DeviceCard(
        device: device,
        address:
            '123 đường kiểm thử responsive, phường mô phỏng, thành phố Hà Nội',
        onTap: () {},
      ),
    );

    expect(find.text('Xe tuần tra khu vực trung tâm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
        body: Center(
          child: SizedBox(width: size.width, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
