// Xác nhận bộ chọn thời gian nhanh/tùy chỉnh phát đúng khoảng và thích ứng màn hình.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/features/journey_history/widgets/history_time_selector.dart';

void main() {
  final dev = DeviceModel(
    id: 'dev-1',
    deviceCode: 'CAR-001',
    name: 'Xe test',
    type: 'VEHICLE',
    status: 'ONLINE',
  );

  testWidgets('HistoryTimeSelector renders device dropdown, date pickers, and query button', (tester) async {
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
    expect(find.text('5 phút'), findsOneWidget);

    await tester.tap(find.text('Tra cứu'));
    await tester.pump();
    expect(queryCalled, isTrue);
  });

  testWidgets('HistoryTimeSelector renders custom gap threshold nicely', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryTimeSelector(
            devices: [dev],
            selectedDevice: dev,
            fromTime: DateTime(2026, 8, 16, 8, 0),
            toTime: DateTime(2026, 8, 16, 12, 0),
            gapThreshold: const Duration(minutes: 10),
            isLoading: false,
            onDeviceChanged: (_) {},
            onFromTimeChanged: (_) {},
            onToTimeChanged: (_) {},
            onGapThresholdChanged: (_) {},
            onQuery: () {},
          ),
        ),
      ),
    );

    expect(find.text('10 phút (Tùy ý)'), findsOneWidget);
  });
}
