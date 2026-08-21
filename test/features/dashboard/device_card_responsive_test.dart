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
      batteryPct: 73,
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
    expect(find.text('Hướng'), findsOneWidget);
    expect(find.text('Đông Bắc · 45°'), findsOneWidget);
    expect(find.text('Tốc độ'), findsOneWidget);
    expect(find.text('30 km/h'), findsOneWidget);
    expect(find.text('73%'), findsOneWidget);
    expect(find.text('Kết nối'), findsOneWidget);
    expect(find.text('Trực tuyến'), findsOneWidget);
    expect(
      find.text(
        '123 đường kiểm thử responsive, phường mô phỏng, thành phố Hà Nội',
      ),
      findsOneWidget,
    );
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
    expect(find.text('30 km/h'), findsOneWidget);
    expect(find.text('73%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DeviceCard handles very long address and name without overflow', (
    tester,
  ) async {
    final device = DeviceModel(
      id: 'device-2',
      deviceCode: 'CTRL-EXTREME-LONG-CODE-99999',
      name:
          'Tay điều khiển giám sát hành trình tuần tra biên giới và cứu hộ cứu nạn',
      type: 'UAV_CONTROLLER',
      status: 'ACTIVE',
      isOnline: true,
      latitude: 21.028511,
      longitude: 105.804817,
      currentSpeedMps: 12.5,
      currentHeadingDeg: 245.0,
      batteryPct: 42,
      lastSeenAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    await _pumpAtSize(
      tester,
      const Size(360, 640),
      DeviceCard(
        device: device,
        address:
            'BIDV Tower, 27 Phố Đào Tấn, Phường Cống Vị, Quận Ba Đình, Thành phố Hà Nội, Việt Nam',
        onTap: () {},
      ),
    );

    expect(
      find.text(
        'BIDV Tower, 27 Phố Đào Tấn, Phường Cống Vị, Quận Ba Đình, Thành phố Hà Nội, Việt Nam',
      ),
      findsOneWidget,
    );
    expect(find.text('45 km/h'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('Tây Nam · 245°'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DeviceCard action menu keeps the detail callback', (
    tester,
  ) async {
    final device = DeviceModel(
      id: 'device-menu',
      deviceCode: 'VM-MENU-01',
      name: 'Thiết bị menu',
      type: 'VEHICLE',
      status: 'ACTIVE',
      isOnline: true,
      latitude: 21.028511,
      longitude: 105.804817,
      lastSeenAt: DateTime.now(),
    );
    var detailTapCount = 0;

    await _pumpAtSize(
      tester,
      const Size(390, 640),
      DeviceCard(device: device, onTap: () => detailTapCount++),
    );
    await tester.tap(find.byTooltip('Thao tác thiết bị'));
    await tester.pumpAndSettle();

    expect(find.text('Chi tiết thiết bị'), findsOneWidget);
    await tester.tap(find.text('Chi tiết thiết bị'));
    await tester.pumpAndSettle();

    expect(detailTapCount, 1);
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
