import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/data/models/location_model.dart';
import 'package:v_monitor/features/journey_history/widgets/history_map_layers.dart';
import 'package:v_monitor/features/journey_history/widgets/point_info_popup.dart';

void main() {
  final samplePoint = LocationModel(
    id: 'sample-1',
    deviceId: 'dev-1',
    measuredAt: DateTime(2026, 8, 17, 10, 30, 0),
    latitude: 21.028511,
    longitude: 105.854211,
    speedMps: 12.5,
    headingDeg: 90.0,
    altitudeM: 15.0,
    accuracyM: 3.5,
    satelliteCount: 8,
  );

  testWidgets('PointInfoPopup prioritizes useful journey information', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PointInfoPopup(point: samplePoint, onClose: () {}),
          ),
        ),
      ),
    );

    expect(find.text('MỐC DI CHUYỂN'), findsOneWidget);
    expect(find.text('Thời gian:'), findsOneWidget);
    expect(find.text('Tốc độ:'), findsOneWidget);
    expect(find.text('Địa chỉ:'), findsOneWidget);
    expect(find.text('Tọa độ:'), findsOneWidget);
    expect(find.text('21.028511, 105.854211'), findsOneWidget);
    expect(find.text('45 km/h'), findsOneWidget);
    expect(find.textContaining('Hướng di chuyển'), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(
      tester.getSize(find.byType(PointInfoPopup)).width,
      lessThanOrEqualTo(310),
    );
  });

  testWidgets('PointInfoPopup explains a parking period in plain language', (
    tester,
  ) async {
    final parkedPoint = LocationModel(
      id: 'park-1',
      deviceId: 'dev-1',
      measuredAt: DateTime(2026, 8, 17, 10, 35),
      latitude: 21.028511,
      longitude: 105.854211,
      speedMps: 0,
      accuracyM: 8,
    );
    final stop = JourneyStopPoint(
      sample: parkedPoint,
      startTime: DateTime(2026, 8, 17, 10, 30),
      endTime: DateTime(2026, 8, 17, 10, 40),
      durationSeconds: 600,
      isPark: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PointInfoPopup(
              point: parkedPoint,
              stopPoint: stop,
              resolveAddress: (_, _) async =>
                  'Số 123 Nguyễn Trãi, P. Thanh Xuân Trung, Hà Nội',
              onClose: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('ĐIỂM ĐỖ XE · 10 phút'), findsOneWidget);
    expect(find.text('Thời lượng đỗ:'), findsOneWidget);
    expect(find.text('10 phút'), findsOneWidget);
    expect(find.text('10:30:00 ➔ 10:40:00 (17/08/2026)'), findsOneWidget);
    expect(
      find.text('Số 123 Nguyễn Trãi, P. Thanh Xuân Trung, Hà Nội'),
      findsOneWidget,
    );
    expect(find.textContaining('Hướng di chuyển'), findsNothing);
  });

  testWidgets(
    'PointInfoPopup invokes onClose when close button (x) is tapped',
    (tester) async {
      var closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PointInfoPopup(
                point: samplePoint,
                onClose: () => closed = true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(closed, isTrue);
    },
  );

  testWidgets(
    'PointInfoPopup invokes onClose when clicking outside via TapRegion',
    (tester) async {
      var closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    key: const Key('outside-area'),
                    color: Colors.blueGrey,
                  ),
                ),
                Positioned(
                  top: 50,
                  right: 50,
                  child: PointInfoPopup(
                    point: samplePoint,
                    onClose: () => closed = true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Tap outside the popup
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();

      expect(closed, isTrue);
    },
  );

  testWidgets(
    'PointInfoPopup does NOT invoke onClose when clicking inside the popup body',
    (tester) async {
      var closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PointInfoPopup(
                point: samplePoint,
                onClose: () => closed = true,
              ),
            ),
          ),
        ),
      );

      // Tap on the text inside the popup
      await tester.tap(find.text('Tốc độ:'));
      await tester.pump();

      expect(closed, isFalse);
    },
  );
}
