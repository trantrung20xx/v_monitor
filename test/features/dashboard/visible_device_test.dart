import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/domain/entities/device_query_filter.dart';
import 'package:v_monitor/features/dashboard/widgets/device_list_panel.dart';

void main() {
  testWidgets(
    '5000 dashboard devices only register visible cards and release hidden routes',
    (tester) async {
      final devices = List.generate(
        5000,
        (i) => DeviceModel(
          id: '$i',
          deviceCode: 'GPS-$i',
          name: 'Thiết bị có tên dài để kiểm tra bố cục $i',
          type: 'VEHICLE',
          status: 'ACTIVE',
          latitude: 10,
          longitude: 106,
          batteryPct: 100,
          currentSpeedMps: 12,
          lastSeenAt: DateTime.now(),
          isOnline: true,
        ),
      );
      final visible = <String>{};
      void visibility(String id, bool shown) {
        if (shown) {
          visible.add(id);
        } else {
          visible.remove(id);
        }
      }

      for (final width in [320.0, 800.0, 1440.0]) {
        for (final scale in [1.0, 2.0]) {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          Widget app(bool enabled) => MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: TickerMode(
                enabled: enabled,
                child: Scaffold(
                  body: DeviceGrid(
                    devices: devices,
                    searchQuery: '',
                    statusFilter: DeviceFilter.all,
                    deviceAddresses: const {
                      '0':
                          'Địa chỉ rất dài tại một tuyến đường trong thành phố Hồ Chí Minh',
                    },
                    onDeviceVisibilityChanged: visibility,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpWidget(app(true));
          await tester.pump();
          expect(visible.length, inInclusiveRange(1, 100));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(app(false));
          await tester.pump();
          expect(visible, isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
