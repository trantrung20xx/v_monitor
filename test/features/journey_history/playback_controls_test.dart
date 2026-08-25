// Xác nhận nút/timeline phát lại gọi đúng callback mà không tự sửa dữ liệu hành trình.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:v_monitor/data/models/location_model.dart';
import 'package:v_monitor/features/journey_history/journey_history_state.dart';
import 'package:v_monitor/features/journey_history/widgets/playback_controls.dart';

void main() {
  testWidgets('PlaybackControls renders timeline and triggers playback buttons', (tester) async {
    final t0 = DateTime(2026, 8, 16, 8, 0, 0);
    final t1 = DateTime(2026, 8, 16, 12, 0, 0);

    final state = JourneyHistoryState(
      status: JourneyHistoryStatus.ready,
      validSamples: [
        LocationModel(id: '1', deviceId: 'd', measuredAt: t0, latitude: 21.0, longitude: 105.0),
        LocationModel(id: '2', deviceId: 'd', measuredAt: t1, latitude: 21.1, longitude: 105.1),
      ],
      currentReplayTime: t0,
      currentPosition: const LatLng(21.0, 105.0),
    );

    var playTriggered = false;
    var resetTriggered = false;
    var stepBackward30sTriggered = false;
    var stepBackward60sTriggered = false;
    var stepForward30sTriggered = false;
    var stepForward60sTriggered = false;
    double? selectedSpeed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackControls(
            state: state,
            onPlay: () => playTriggered = true,
            onPause: () {},
            onResume: () {},
            onReset: () => resetTriggered = true,
            onStepBackward30s: () => stepBackward30sTriggered = true,
            onStepBackward60s: () => stepBackward60sTriggered = true,
            onStepForward30s: () => stepForward30sTriggered = true,
            onStepForward60s: () => stepForward60sTriggered = true,
            onSeekProgress: (_) {},
            onSpeedChanged: (s) => selectedSpeed = s,
            onFollowChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Bắt đầu'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.byIcon(Icons.fast_rewind_rounded), findsOneWidget);
    expect(find.byIcon(Icons.replay_30_rounded), findsOneWidget);
    expect(find.byIcon(Icons.forward_30_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fast_forward_rounded), findsOneWidget);

    await tester.tap(find.text('Bắt đầu'));
    await tester.pump();
    expect(playTriggered, isTrue);

    await tester.tap(find.byIcon(Icons.fast_rewind_rounded));
    await tester.pump();
    expect(stepBackward60sTriggered, isTrue);

    await tester.tap(find.byIcon(Icons.replay_30_rounded));
    await tester.pump();
    expect(stepBackward30sTriggered, isTrue);

    await tester.tap(find.byIcon(Icons.forward_30_rounded));
    await tester.pump();
    expect(stepForward30sTriggered, isTrue);

    await tester.tap(find.byIcon(Icons.fast_forward_rounded));
    await tester.pump();
    expect(stepForward60sTriggered, isTrue);

    await tester.tap(find.byIcon(Icons.replay_rounded));
    await tester.pump();
    expect(resetTriggered, isTrue);

    // Test 16x speed selection
    await tester.tap(find.text('1x'));
    await tester.pumpAndSettle();
    expect(find.text('16x'), findsWidgets);
    await tester.tap(find.text('16x').last);
    await tester.pumpAndSettle();
    expect(selectedSpeed, equals(16.0));
  });
}
