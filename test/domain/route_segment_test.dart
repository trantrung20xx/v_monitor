import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/data/models/location_model.dart';
import 'package:v_monitor/domain/entities/route_segment.dart';

void main() {
  group('RouteSegment Tests (Section 24 & 73)', () {
    test('Splits route into segments when time gap exceeds threshold', () {
      final t0 = DateTime(2026, 8, 16, 8, 0, 0);
      final t1 = DateTime(2026, 8, 16, 8, 1, 0); // +1 min
      final t2 = DateTime(2026, 8, 16, 12, 0, 0); // +4 hours gap!
      final t3 = DateTime(2026, 8, 16, 12, 5, 0); // +5 min

      final samples = [
        LocationModel(id: '1', deviceId: 'd', measuredAt: t0, latitude: 21.01, longitude: 105.01, speedMps: 5.0),
        LocationModel(id: '2', deviceId: 'd', measuredAt: t1, latitude: 21.02, longitude: 105.02, speedMps: 5.0),
        LocationModel(id: '3', deviceId: 'd', measuredAt: t2, latitude: 21.05, longitude: 105.05, speedMps: 8.0),
        LocationModel(id: '4', deviceId: 'd', measuredAt: t3, latitude: 21.06, longitude: 105.06, speedMps: 8.0),
      ];

      final segments = RouteSegment.splitIntoSegments(
        samples,
        gapThreshold: const Duration(minutes: 5),
      );

      expect(segments.length, equals(2));
      expect(segments[0].sampleCount, equals(2));
      expect(segments[0].startedAt, equals(t0));
      expect(segments[0].endedAt, equals(t1));

      expect(segments[1].sampleCount, equals(2));
      expect(segments[1].startedAt, equals(t2));
      expect(segments[1].endedAt, equals(t3));
    });

    test('Aggregates moving duration and distance accurately', () {
      final t0 = DateTime(2026, 8, 16, 8, 0, 0);
      final t1 = DateTime(2026, 8, 16, 8, 1, 0); // 60s moving
      final t2 = DateTime(2026, 8, 16, 8, 2, 0); // 60s stopped

      final samples = [
        LocationModel(id: '1', deviceId: 'd', measuredAt: t0, latitude: 21.000, longitude: 105.000, speedMps: 10.0),
        LocationModel(id: '2', deviceId: 'd', measuredAt: t1, latitude: 21.005, longitude: 105.005, speedMps: 0.0),
        LocationModel(id: '3', deviceId: 'd', measuredAt: t2, latitude: 21.005, longitude: 105.005, speedMps: 0.0),
      ];

      final segments = RouteSegment.splitIntoSegments(samples);
      expect(segments.length, equals(1));
      expect(segments.first.distanceM, greaterThan(0));
      expect(segments.first.movingDurationS, equals(60));
      expect(segments.first.stoppedDurationS, equals(60));
    });
  });
}
