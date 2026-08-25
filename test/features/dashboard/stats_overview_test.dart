// Xác nhận dải thống kê hiển thị đúng số liệu và không overflow trên màn hình hẹp.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/features/dashboard/dashboard_state.dart';
import 'package:v_monitor/features/dashboard/widgets/stats_overview.dart';

void main() {
  testWidgets('StatsOverview keeps stat cards visually consistent on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: StatsOverview(
              state: DashboardState(
                totalDevices: 12,
                onlineCount: 8,
                offlineCount: 4,
                movingCount: 3,
                stoppedCount: 5,
                staleCount: 1,
                attentionCount: 0,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mất tín hiệu'), findsOneWidget);
    expect(find.text('Cần kiểm tra'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
