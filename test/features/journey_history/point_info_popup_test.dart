import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/data/models/location_model.dart';
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

  testWidgets('PointInfoPopup renders detailed GPS information', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PointInfoPopup(
              point: samplePoint,
              onClose: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Chi tiết mốc GPS'), findsOneWidget);
    expect(find.text('Thời gian'), findsOneWidget);
    expect(find.text('Vận tốc'), findsOneWidget);
    expect(find.text('Hướng'), findsOneWidget);
    expect(find.text('Tọa độ'), findsOneWidget);
    expect(find.text('Độ cao'), findsOneWidget);
    expect(find.text('Độ chính xác'), findsOneWidget);
    expect(find.text('Vệ tinh'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('PointInfoPopup invokes onClose when close button (x) is tapped', (tester) async {
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
  });

  testWidgets('PointInfoPopup invokes onClose when clicking outside via TapRegion', (tester) async {
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
  });

  testWidgets('PointInfoPopup does NOT invoke onClose when clicking inside the popup body', (tester) async {
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
    await tester.tap(find.text('Vận tốc'));
    await tester.pump();

    expect(closed, isFalse);
  });
}
