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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackControls(
            state: state,
            onPlay: () => playTriggered = true,
            onPause: () {},
            onResume: () {},
            onReset: () => resetTriggered = true,
            onSeekProgress: (_) {},
            onSpeedChanged: (_) {},
            onFollowChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Bắt đầu'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);

    await tester.tap(find.text('Bắt đầu'));
    await tester.pump();
    expect(playTriggered, isTrue);

    await tester.tap(find.byIcon(Icons.replay_rounded));
    await tester.pump();
    expect(resetTriggered, isTrue);
  });
}
