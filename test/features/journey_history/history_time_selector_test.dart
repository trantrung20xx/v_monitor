import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/features/journey_history/widgets/history_time_selector.dart';

void main() {
  testWidgets('HistoryTimeSelector renders device dropdown, date pickers, and query button', (tester) async {
    final dev = DeviceModel(
      id: 'dev-1',
      deviceCode: 'CAR-001',
      name: 'Xe test',
      type: 'VEHICLE',
      status: 'ONLINE',
    );

    var queryCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryTimeSelector(
            devices: [dev],
            selectedDevice: dev,
            fromTime: DateTime(2026, 8, 16, 8, 0),
            toTime: DateTime(2026, 8, 16, 12, 0),
            gapThreshold: const Duration(minutes: 5),
            isLoading: false,
            onDeviceChanged: (_) {},
            onFromTimeChanged: (_) {},
            onToTimeChanged: (_) {},
            onGapThresholdChanged: (_) {},
            onQuery: () => queryCalled = true,
          ),
        ),
      ),
    );

    expect(find.text('Tra cứu'), findsOneWidget);
    expect(find.text('Hôm nay'), findsOneWidget);
    expect(find.text('Hôm qua'), findsOneWidget);
    expect(find.text('24h qua'), findsOneWidget);
    expect(find.text('7 ngày qua'), findsOneWidget);

    await tester.tap(find.text('Tra cứu'));
    await tester.pump();
    expect(queryCalled, isTrue);
  });
}
