import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/core/utils/map_launcher_service.dart';
import 'package:v_monitor/data/models/device_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MapLauncherService Coordinate Validation', () {
    test('Valid coordinates return true', () {
      expect(
        MapLauncherService.isValidCoordinate(21.028511, 105.804817),
        isTrue,
      ); // Hanoi
      expect(
        MapLauncherService.isValidCoordinate(-33.856784, 151.215297),
        isTrue,
      ); // Sydney
      expect(MapLauncherService.isValidCoordinate(90.0, 180.0), isTrue);
      expect(MapLauncherService.isValidCoordinate(-90.0, -180.0), isTrue);
    });

    test('Null latitude or longitude returns false', () {
      expect(MapLauncherService.isValidCoordinate(null, 105.0), isFalse);
      expect(MapLauncherService.isValidCoordinate(21.0, null), isFalse);
      expect(MapLauncherService.isValidCoordinate(null, null), isFalse);
    });

    test('Out of bounds latitude returns false', () {
      expect(MapLauncherService.isValidCoordinate(90.001, 105.0), isFalse);
      expect(MapLauncherService.isValidCoordinate(-90.001, 105.0), isFalse);
      expect(MapLauncherService.isValidCoordinate(200.0, 105.0), isFalse);
    });

    test('Out of bounds longitude returns false', () {
      expect(MapLauncherService.isValidCoordinate(21.0, 180.001), isFalse);
      expect(MapLauncherService.isValidCoordinate(21.0, -180.001), isFalse);
      expect(MapLauncherService.isValidCoordinate(21.0, 200.0), isFalse);
    });
  });

  group('MapLauncherService Format Validation', () {
    test('Copy location throws on invalid coordinates', () async {
      final device = DeviceModel(
        id: '1',
        deviceCode: 'DEV01',
        name: 'Test Device',
        type: 'VEHICLE',
        status: 'OFFLINE',
        isOnline: false,
        lastSeenAt: null,
      );

      expect(
        () => MapLauncherService.copyLocationToClipboard(device, null, null),
        throwsException,
      );
    });
  });
}
