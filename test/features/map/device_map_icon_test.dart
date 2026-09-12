import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/core/theme/app_theme_colors.dart';
import 'package:v_monitor/domain/entities/device_status_resolver.dart';
import 'package:v_monitor/features/map/widgets/device_map_icon.dart';

void main() {
  test(
    'colors follow current connectivity, GPS age, movement and activity',
    () {
      final now = DateTime.now();
      for (final colors in [AppThemeColors.light, AppThemeColors.dark]) {
        for (final (online, seenAge, gpsAge, speed, activity, expected) in [
          (false, 0, 0, 15.0, 'ACTIVE', colors.offline),
          (true, 600, 0, 15.0, 'ACTIVE', colors.offline),
          (true, 0, 180, 15.0, 'ACTIVE', colors.danger),
          (true, 0, 0, 15.0, 'ACTIVE', colors.primary),
          (true, 0, 0, 0.0, 'ACTIVE', colors.warning),
          (true, 0, 0, 0.5, 'ACTIVE', colors.warning),
          (true, 0, 0, null, 'ACTIVE', colors.success),
          (true, 0, 0, 15.0, 'INACTIVE', colors.offline),
        ]) {
          final status = DeviceStatusResolver.resolve(
            isOnline: online,
            lastSeenAt: now.subtract(Duration(seconds: seenAge)),
            latestMeasuredAt: now.subtract(Duration(seconds: gpsAge)),
            currentSpeedMps: speed,
            baseStatus: activity,
          );
          expect(DeviceMapIcon.statusColor(status, colors), expected);
        }
      }
    },
  );

  test(
    'runtime movement threshold is respected without a map-only threshold',
    () {
      addTearDown(DeviceStatusResolver.resetRuntime);
      DeviceStatusResolver.configureRuntime(
        onlineTimeout: const Duration(seconds: 60),
        movementSpeedThresholdMps: 2,
      );
      final status = DeviceStatusResolver.resolve(
        isOnline: true,
        lastSeenAt: DateTime.now(),
        currentSpeedMps: 1,
        baseStatus: 'ACTIVE',
      );
      expect(
        DeviceMapIcon.statusColor(status, AppThemeColors.light),
        AppThemeColors.light.warning,
      );
    },
  );

  testWidgets(
    'rendered car and UAV assets decode and have transparent pixels',
    (tester) async {
      await tester.runAsync(() async {
        for (final asset in [DeviceMapIcon.carAsset, DeviceMapIcon.uavAsset]) {
          final bytes = await rootBundle.load(asset);
          final codec = await ui.instantiateImageCodec(
            bytes.buffer.asUint8List(),
          );
          final frame = await codec.getNextFrame();
          expect(frame.image.width, greaterThanOrEqualTo(108));
          expect(frame.image.height, frame.image.width);
          final rgba = await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(rgba!.getUint8(3), 0);
          frame.image.dispose();
          codec.dispose();
        }
      });
    },
  );
}
