import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:v_monitor/features/map/widgets/device_icon_canvas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('single markers paint the same PNG pixels as the fleet canvas', (
    tester,
  ) async {
    final atlas = await tester.runAsync(() => DeviceIconAtlas.image);
    final boundaryKey = GlobalKey();
    for (final type in ['VEHICLE', 'UAV_CONTROLLER']) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox.square(
                dimension: 100,
                child: Center(
                  child: DeviceMarkerIcon(
                    deviceType: type,
                    color: Colors.green,
                    headingDegrees: 90,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        final image = await boundary.toImage();
        final actual = await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        final expected = await _paint(
          _marker('a', type, 90, Colors.green),
          atlas!,
        );
        var mismatches = 0;
        for (var offset = 0; offset < expected.lengthInBytes; offset += 4) {
          final actualAlpha = actual!.getUint8(offset + 3);
          final expectedAlpha = expected.getUint8(offset + 3);
          if ((actualAlpha - expectedAlpha).abs() > 2) mismatches++;
          // Transparent RGB and edge rounding can differ after compositing.
          for (var channel = 0; channel < 3; channel++) {
            final actualValue = actual.getUint8(offset + channel) * actualAlpha;
            final expectedValue =
                expected.getUint8(offset + channel) * expectedAlpha;
            if ((actualValue - expectedValue).abs() > 2 * 255) mismatches++;
          }
        }
        expect(mismatches, 0, reason: '$type must use the same shaded PNG');
        image.dispose();
      });
    }
  });

  test(
    'rendered vehicles retain body shading and details while changing status color',
    () async {
      final atlas = await DeviceIconAtlas.image;
      expect(atlas.width, 336);
      expect(atlas.height, 336);
      for (final (type, angle, color) in [
        ('VEHICLE', 0.0, Colors.red),
        ('VEHICLE', 90.0, Colors.blue),
        ('VEHICLE', 180.0, Colors.orange),
        ('VEHICLE', 270.0, Colors.grey),
        ('UAV_CONTROLLER', 0.0, Colors.green),
      ]) {
        final pixels = await _paint(_marker('a', type, angle, color), atlas);
        var minX = 100, minY = 100, maxX = 0, maxY = 0, solidPixels = 0;
        var bodyPixels = 0, detailPixels = 0, outlinePixels = 0;
        final channels = [
          (color.r * 255).round(),
          (color.g * 255).round(),
          (color.b * 255).round(),
        ];
        final dominant = channels.indexOf(
          channels.reduce((a, b) => a > b ? a : b),
        );
        for (var y = 0; y < 100; y++) {
          for (var x = 0; x < 100; x++) {
            final offset = (y * 100 + x) * 4;
            if (pixels.getUint8(offset + 3) < 200) continue;
            solidPixels++;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            final rgb = List.generate(3, (i) => pixels.getUint8(offset + i));
            if (rgb.every((value) => value > 235)) outlinePixels++;
            // Ignore the white contour and its antialiased blend at the edge;
            // the coloured body must still contain both bright and dark detail.
            if ([0, 1, 2].any((i) => rgb[i] > channels[i] + 3)) continue;
            final intensity =
                pixels.getUint8(offset + dominant) / channels[dominant];
            if (intensity > .65) bodyPixels++;
            if (intensity < .4) detailPixels++;
          }
        }
        expect(solidPixels, greaterThan(80));
        expect(outlinePixels, greaterThan(20));
        // A solid alpha tint would lose the glass, tyres and propeller shading.
        expect(bodyPixels, greaterThan(25));
        expect(detailPixels, greaterThan(20));
        expect(maxX - minX + 1, lessThanOrEqualTo(40));
        expect(maxY - minY + 1, lessThanOrEqualTo(40));
        expect(math.max(maxX - minX, maxY - minY), greaterThan(32));
        expect((minX + maxX) / 2, closeTo(49.5, 1));
        expect((minY + maxY) / 2, closeTo(49.5, 1));
        if (type == 'VEHICLE') {
          if (angle % 180 == 0) {
            expect(maxY - minY, greaterThan((maxX - minX) * 1.5));
          } else {
            expect(maxX - minX, greaterThan((maxY - minY) * 1.5));
          }
        }
      }
    },
  );

  test(
    'overlapping icon paint and hit test both select the last device',
    () async {
      final first = _marker('a', 'VEHICLE', 0, Colors.red);
      final last = _marker('b', 'VEHICLE', 0, Colors.blue);
      final projected = [
        ProjectedDeviceMarker(first, const Offset(50, 50)),
        ProjectedDeviceMarker(last, const Offset(50, 50)),
      ];
      expect(
        DeviceIconPainter.hit(projected, const Offset(50, 50))?.marker,
        same(last),
      );
      expect(
        DeviceIconPainter.hit(projected, const Offset(73, 50))?.marker,
        same(last),
      );
      expect(DeviceIconPainter.hit(projected, const Offset(75, 50)), isNull);
      final pixels = await _render(
        DeviceIconPainter(projected, await DeviceIconAtlas.image),
      );
      final lastPixels = await _paint(last, await DeviceIconAtlas.image);
      final firstPixels = await _paint(first, await DeviceIconAtlas.image);
      var matchingPixels = 0;
      for (var i = 0; i < pixels.lengthInBytes; i += 4) {
        if (lastPixels.getUint8(i + 3) < 200) continue;
        final lastAlpha = lastPixels.getUint8(i + 3) / 255;
        final firstAlpha = firstPixels.getUint8(i + 3) / 255;
        final combinedAlpha = lastAlpha + firstAlpha * (1 - lastAlpha);
        for (var channel = 0; channel < 3; channel++) {
          final expected =
              (lastPixels.getUint8(i + channel) * lastAlpha +
                  firstPixels.getUint8(i + channel) *
                      firstAlpha *
                      (1 - lastAlpha)) /
              combinedAlpha;
          expect(pixels.getUint8(i + channel), closeTo(expected, 2));
        }
        expect(pixels.getUint8(i + 3), closeTo(combinedAlpha * 255, 2));
        matchingPixels++;
      }
      expect(matchingPixels, greaterThan(80));
    },
  );
}

DeviceMapMarker _marker(String id, String type, double heading, Color color) =>
    DeviceMapMarker(
      id: id,
      point: const LatLng(10, 106),
      deviceType: type,
      color: color,
      headingDegrees: heading,
      description: id,
      onTap: () {},
    );

Future<ByteData> _paint(DeviceMapMarker marker, ui.Image atlas) => _render(
  DeviceIconPainter([
    ProjectedDeviceMarker(marker, const Offset(50, 50)),
  ], atlas),
);

Future<ByteData> _render(DeviceIconPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(100, 100));
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  picture.dispose();
  return data!;
}
