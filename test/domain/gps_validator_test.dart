import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:v_monitor/data/models/location_model.dart';
import 'package:v_monitor/domain/entities/gps_validator.dart';

void main() {
  group('GpsValidator Coordinate Tests (Section 13 & 70)', () {
    test('Validates global coordinates across all hemispheres', () {
      // Hà Nội (Bắc, Đông)
      expect(GpsValidator.isValidCoordinate(21.0285, 105.8542), isTrue);

      // Sydney Úc (Nam, Đông)
      expect(GpsValidator.isValidCoordinate(-33.8688, 151.2093), isTrue);

      // New York Mỹ (Bắc, Tây)
      expect(GpsValidator.isValidCoordinate(40.7128, -74.0060), isTrue);

      // Buenos Aires Nam Mỹ (Nam, Tây)
      expect(GpsValidator.isValidCoordinate(-34.6037, -58.3816), isTrue);
    });

    test('Rejects invalid coordinates and NaN/Infinity', () {
      expect(GpsValidator.isValidCoordinate(null, 105.0), isFalse);
      expect(GpsValidator.isValidCoordinate(21.0, null), isFalse);
      expect(GpsValidator.isValidCoordinate(91.0, 105.0), isFalse);
      expect(GpsValidator.isValidCoordinate(-91.0, 105.0), isFalse);
      expect(GpsValidator.isValidCoordinate(21.0, 181.0), isFalse);
      expect(GpsValidator.isValidCoordinate(21.0, -181.0), isFalse);
      expect(GpsValidator.isValidCoordinate(double.nan, 105.0), isFalse);
      expect(GpsValidator.isValidCoordinate(21.0, double.infinity), isFalse);
      expect(GpsValidator.isValidCoordinate(0.0, 0.0), isFalse); // Null Island
    });
  });

  group('GpsValidator Bearing Tests (Section 22 & 69)', () {
    test('Calculates correct 360-degree bearings for 8 cardinal directions', () {
      const pCenter = LatLng(21.0, 105.0);

      // North (~0° / 360°)
      const pNorth = LatLng(21.1, 105.0);
      final bearingN = GpsValidator.calculateBearing(pCenter, pNorth);
      expect(bearingN, closeTo(0.0, 1.0));

      // East (~90°)
      const pEast = LatLng(21.0, 105.1);
      final bearingE = GpsValidator.calculateBearing(pCenter, pEast);
      expect(bearingE, closeTo(90.0, 1.0));

      // South (~180°)
      const pSouth = LatLng(20.9, 105.0);
      final bearingS = GpsValidator.calculateBearing(pCenter, pSouth);
      expect(bearingS, closeTo(180.0, 1.0));

      // West (~270°)
      const pWest = LatLng(21.0, 104.9);
      final bearingW = GpsValidator.calculateBearing(pCenter, pWest);
      expect(bearingW, closeTo(270.0, 1.0));

      // North-East (~45°)
      const pNE = LatLng(21.1, 105.1);
      final bearingNE = GpsValidator.calculateBearing(pCenter, pNE);
      expect(bearingNE, closeTo(45.0, 2.0));

      // South-East (~135°)
      const pSE = LatLng(20.9, 105.1);
      final bearingSE = GpsValidator.calculateBearing(pCenter, pSE);
      expect(bearingSE, closeTo(135.0, 2.0));

      // South-West (~225°)
      const pSW = LatLng(20.9, 104.9);
      final bearingSW = GpsValidator.calculateBearing(pCenter, pSW);
      expect(bearingSW, closeTo(225.0, 2.0));

      // North-West (~315°)
      const pNW = LatLng(21.1, 104.9);
      final bearingNW = GpsValidator.calculateBearing(pCenter, pNW);
      expect(bearingNW, closeTo(315.0, 2.0));
    });
  });

  group('GpsValidator Outlier & Teleport Detection Tests (Section 16)', () {
    test('Sanitizes teleport outlier spikes while preserving authentic points', () {
      final t0 = DateTime(2026, 8, 16, 8, 0, 0);
      final t1 = DateTime(2026, 8, 16, 8, 0, 10);
      final t2 = DateTime(2026, 8, 16, 8, 0, 20);

      final pA = LocationModel(
        id: '1',
        deviceId: 'dev1',
        measuredAt: t0,
        latitude: 21.0285,
        longitude: 105.8542, // Hà Nội
      );

      // Điểm đột biến sang TP.HCM sau 10 giây (vận tốc ~400,000 km/h)
      final pSpike = LocationModel(
        id: '2',
        deviceId: 'dev1',
        measuredAt: t1,
        latitude: 10.8231,
        longitude: 106.6297, // TP.HCM
      );

      // Điểm tiếp theo lại ở Hà Nội
      final pC = LocationModel(
        id: '3',
        deviceId: 'dev1',
        measuredAt: t2,
        latitude: 21.0290,
        longitude: 105.8545, // Hà Nội
      );

      final sanitized = GpsValidator.sanitizeSamples([pA, pSpike, pC]);

      expect(sanitized.length, equals(2));
      expect(sanitized.first.id, equals('1'));
      expect(sanitized.last.id, equals('3'));
    });
  });

  group('GpsValidator Interpolation Tests (Section 30 & 72)', () {
    test('Interpolates exact midpoint at 50% time progress', () {
      const p0 = LatLng(21.0000, 105.0000);
      const p1 = LatLng(21.0100, 105.0200);

      final mid = GpsValidator.interpolatePosition(p0, p1, 0.5);
      expect(mid.latitude, closeTo(21.0050, 0.00001));
      expect(mid.longitude, closeTo(105.0100, 0.00001));

      final start = GpsValidator.interpolatePosition(p0, p1, 0.0);
      expect(start.latitude, closeTo(21.0000, 0.00001));
      expect(start.longitude, closeTo(105.0000, 0.00001));

      final end = GpsValidator.interpolatePosition(p0, p1, 1.0);
      expect(end.latitude, closeTo(21.0100, 0.00001));
      expect(end.longitude, closeTo(105.0200, 0.00001));
    });
  });
}
