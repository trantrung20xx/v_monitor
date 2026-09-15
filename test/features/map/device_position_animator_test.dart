import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:v_monitor/features/map/device_position_animator.dart';

void main() {
  const start = LatLng(10, 106);
  const end = LatLng(10, 106.0001);
  final measuredAt = DateTime.utc(2026, 9, 14, 10);

  test('interpolates only between confirmed GPS targets and ends exactly', () {
    final animator = DevicePositionAnimator();
    animator.update(
      id: 'vehicle',
      target: start,
      sampleTime: measuredAt,
      now: Duration.zero,
      animate: true,
    );
    animator.update(
      id: 'vehicle',
      target: end,
      sampleTime: measuredAt.add(const Duration(seconds: 2)),
      now: Duration.zero,
      animate: true,
    );

    final halfway = animator.positionFor('vehicle', const Duration(seconds: 1));
    expect(halfway.latitude, closeTo(10, 1e-12));
    expect(halfway.longitude, closeTo(106.00005, 1e-9));
    expect(animator.hasActive(const Duration(seconds: 1)), isTrue);
    expect(animator.positionFor('vehicle', const Duration(seconds: 3)), end);
    expect(animator.hasActive(const Duration(seconds: 3)), isFalse);
  });

  test('retargets from the currently displayed point without jumping', () {
    final animator = DevicePositionAnimator();
    animator.update(
      id: 'vehicle',
      target: start,
      sampleTime: measuredAt,
      now: Duration.zero,
      animate: true,
    );
    animator.update(
      id: 'vehicle',
      target: end,
      sampleTime: measuredAt.add(const Duration(seconds: 2)),
      now: Duration.zero,
      animate: true,
    );
    final beforeRetarget = animator.positionFor(
      'vehicle',
      const Duration(seconds: 1),
    );
    const next = LatLng(10, 106.0002);
    animator.update(
      id: 'vehicle',
      target: next,
      sampleTime: measuredAt.add(const Duration(seconds: 4)),
      now: const Duration(seconds: 1),
      animate: true,
    );

    expect(
      animator.positionFor('vehicle', const Duration(seconds: 1)),
      beforeRetarget,
    );
    final halfwayToNext = animator.positionFor(
      'vehicle',
      const Duration(seconds: 2),
    );
    expect(halfwayToNext.longitude, closeTo(106.000125, 1e-9));
  });

  test('snaps when animation is disabled or the GPS jump is implausible', () {
    final animator = DevicePositionAnimator();
    animator.update(
      id: 'vehicle',
      target: start,
      sampleTime: measuredAt,
      now: Duration.zero,
      animate: true,
    );
    animator.update(
      id: 'vehicle',
      target: end,
      sampleTime: measuredAt.add(const Duration(seconds: 2)),
      now: Duration.zero,
      animate: false,
    );
    expect(animator.positionFor('vehicle', Duration.zero), end);
    expect(animator.hasActive(Duration.zero), isFalse);

    const impossible = LatLng(11, 107);
    animator.update(
      id: 'vehicle',
      target: impossible,
      sampleTime: measuredAt.add(const Duration(seconds: 3)),
      now: Duration.zero,
      animate: true,
    );
    expect(animator.positionFor('vehicle', Duration.zero), impossible);
    expect(animator.hasActive(Duration.zero), isFalse);
  });
}
