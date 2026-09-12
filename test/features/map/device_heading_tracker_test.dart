import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/features/map/device_heading_tracker.dart';

void main() {
  late DeviceHeadingTracker tracker;
  late DateTime base;
  setUp(() {
    tracker = DeviceHeadingTracker();
    base = DateTime.now().subtract(const Duration(seconds: 60));
  });

  DeviceModel fix({
    String id = 'car',
    int seconds = 0,
    double latitude = 10,
    double longitude = 106,
    double? heading,
    double? speed = 10,
    bool online = true,
    DateTime? measuredAt,
  }) => DeviceModel(
    id: id,
    deviceCode: id,
    name: id,
    type: 'VEHICLE',
    status: 'ACTIVE',
    isOnline: online,
    latitude: latitude,
    longitude: longitude,
    currentHeadingDeg: heading,
    currentSpeedMps: speed,
    latestMeasuredAt: measuredAt ?? base.add(Duration(seconds: seconds)),
    lastSeenAt: DateTime.now(),
  );

  test('device heading wins over inferred course, including zero', () {
    tracker.update([fix(heading: 270)]);
    tracker.update([fix(seconds: 5, longitude: 106.0002, heading: 0)]);
    expect(tracker.headingFor('car'), 0);
    tracker.update([fix(seconds: 10, longitude: 106.0004, heading: 123.5)]);
    expect(tracker.headingFor('car'), 123.5);
  });

  for (final (lat, lon, expected) in [
    (10.0002, 106.0, 0.0),
    (10.0002, 106.0002, 44.6),
    (10.0, 106.0002, 90.0),
    (9.9998, 106.0002, 135.4),
    (9.9998, 106.0, 180.0),
    (9.9998, 105.9998, 224.6),
    (10.0, 105.9998, 270.0),
    (10.0002, 105.9998, 315.4),
  ]) {
    test('missing heading infers bearing $expected from valid movement', () {
      tracker.update([fix()]);
      expect(tracker.headingFor('car'), isNull);
      tracker.update([fix(seconds: 5, latitude: lat, longitude: lon)]);
      expect(tracker.headingFor('car'), closeTo(expected, 0.1));
    });
  }

  test('invalid device headings fall back to GPS course', () {
    for (final heading in [-1.0, 360.0, double.nan, double.infinity]) {
      tracker = DeviceHeadingTracker();
      tracker.update([fix(heading: heading)]);
      expect(tracker.headingFor('car'), isNull);
      tracker.update([fix(seconds: 5, longitude: 106.0002, heading: heading)]);
      expect(tracker.headingFor('car'), closeTo(90, 0.01));
    }
  });

  test(
    'small jitter is ignored; short movements accumulate past five metres',
    () {
      tracker.update([fix(heading: 180)]);
      for (var i = 1; i <= 4; i++) {
        tracker.update([fix(seconds: i, longitude: 106 + i * .000009)]);
        expect(tracker.headingFor('car'), 180);
      }
      tracker.update([fix(seconds: 6, longitude: 106.000054)]);
      expect(tracker.headingFor('car'), closeTo(90, 0.01));
    },
  );

  test('stopped vehicle holds course despite heading jitter and GPS drift', () {
    tracker.update([fix(heading: 45)]);
    tracker.update([
      fix(seconds: 5, longitude: 106.0002, speed: 0, heading: 210),
    ]);
    tracker.update([fix(seconds: 10, latitude: 9.9999, speed: 0)]);
    expect(tracker.headingFor('car'), 45);
    tracker.update([fix(seconds: 15, heading: 300)]);
    expect(tracker.headingFor('car'), 300);
  });

  test(
    'same timestamp, old packets and metadata do not rewind the bearing',
    () {
      tracker.update([fix(heading: 40)]);
      tracker.update([fix(seconds: 5, heading: 90)]);
      tracker.update([fix(seconds: 5, heading: 180, longitude: 106.001)]);
      tracker.update([fix(seconds: 1, heading: 270, latitude: 10.001)]);
      expect(tracker.headingFor('car'), 90);
      tracker.update([fix(seconds: 10, latitude: 10.0002)]);
      expect(tracker.headingFor('car'), closeTo(0, .01));
    },
  );

  test('GPS spike and return do not rotate the vehicle', () {
    tracker.update([fix(heading: 0)]);
    tracker.update([fix(seconds: 5, longitude: 107)]);
    expect(tracker.headingFor('car'), 0);
    tracker.update([fix(seconds: 10)]);
    expect(tracker.headingFor('car'), 0);
    tracker.update([fix(seconds: 15, longitude: 106.0002)]);
    expect(tracker.headingFor('car'), closeTo(90, .01));
  });

  test('long gaps establish a new anchor without a guessed course', () {
    tracker.update([
      fix(heading: 30, measuredAt: base.subtract(const Duration(minutes: 3))),
    ]);
    tracker.update([fix(longitude: 106.003)]);
    expect(tracker.headingFor('car'), 30);
    tracker.update([fix(seconds: 5, longitude: 106.003, latitude: 10.0002)]);
    expect(tracker.headingFor('car'), closeTo(0, .01));
  });

  test('offline and stale GPS cannot infer current movement', () {
    tracker.update([
      fix(heading: 30, measuredAt: base.subtract(const Duration(minutes: 4))),
    ]);
    tracker.update([
      fix(
        longitude: 106.0002,
        measuredAt: base.subtract(const Duration(minutes: 3)),
      ),
    ]);
    expect(tracker.headingFor('car'), 30);
    tracker.update([fix(seconds: 5, online: false, longitude: 106.0004)]);
    expect(tracker.headingFor('car'), 30);
  });

  test('moving coordinates with missing speed may supply a course', () {
    tracker.update([fix(speed: null)]);
    tracker.update([fix(seconds: 5, longitude: 106.0002, speed: null)]);
    expect(tracker.headingFor('car'), closeTo(90, .01));
  });

  test('invalid coordinates reset the anchor and never produce NaN', () {
    for (final (lat, lon) in [
      (double.nan, 106.0),
      (10.0, double.infinity),
      (91.0, 106.0),
      (0.0, 0.0),
    ]) {
      tracker.update([fix(heading: 45)]);
      tracker.update([fix(seconds: 5, latitude: lat, longitude: lon)]);
      expect(tracker.headingFor('car'), isNull);
      tracker.update([fix(seconds: 10)]);
      expect(tracker.headingFor('car'), isNull);
    }
  });

  test('crossing the antimeridian still points east', () {
    tracker.update([fix(longitude: 179.9999)]);
    tracker.update([fix(seconds: 5, longitude: -179.9999)]);
    expect(tracker.headingFor('car'), closeTo(90, .01));
  });

  test('future clock errors do not poison the next valid fix', () {
    tracker.update([fix(heading: 0)]);
    tracker.update([
      fix(
        heading: 180,
        measuredAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    ]);
    expect(tracker.headingFor('car'), 0);
    tracker.update([fix(seconds: 5, longitude: 106.0002)]);
    expect(tracker.headingFor('car'), closeTo(90, .01));
  });

  test('devices and deleted IDs do not share heading state', () {
    tracker.update([fix(heading: 45), fix(id: 'uav', heading: 270)]);
    tracker.update([fix(id: 'uav', seconds: 5)]);
    expect(tracker.headingFor('car'), isNull);
    expect(tracker.headingFor('uav'), 270);
    tracker.update([fix(seconds: 10), fix(id: 'uav', seconds: 10)]);
    expect(tracker.headingFor('car'), isNull);
    expect(tracker.headingFor('uav'), 270);
  });
}
