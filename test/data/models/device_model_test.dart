// Xác nhận DeviceModel parse đúng hồ sơ quản lý, latest state và các trường nullable.
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/data/models/device_model.dart';

void main() {
  test('battery_pct is parsed as the battery level of the device', () {
    final device = DeviceModel.fromJson({
      'id': 'device-1',
      'device_code': 'CAR-001',
      'name': 'Xe giám sát',
      'device_type': 'VEHICLE',
      'status': 'ONLINE',
      'battery_pct': 64,
    });

    expect(device.batteryPct, 64);
  });

  test('missing battery_pct remains unknown instead of becoming zero', () {
    final device = DeviceModel.fromJson({
      'id': 'device-2',
      'device_code': 'CTRL-001',
      'name': 'Tay điều khiển',
      'device_type': 'UAV_CONTROLLER',
      'status': 'ONLINE',
    });

    expect(device.batteryPct, isNull);
  });

  test('is_enabled defaults to true and parses an explicit lock', () {
    final defaultDevice = DeviceModel.fromJson({
      'id': 'device-3',
      'device_code': 'CAR-003',
      'name': 'Xe mặc định',
      'device_type': 'VEHICLE',
      'status': 'UNKNOWN',
    });
    final disabledDevice = DeviceModel.fromJson({
      'id': 'device-4',
      'device_code': 'CAR-004',
      'name': 'Xe tạm khóa',
      'device_type': 'VEHICLE',
      'status': 'UNKNOWN',
      'is_enabled': false,
    });

    expect(defaultDevice.isEnabled, isTrue);
    expect(disabledDevice.isEnabled, isFalse);
  });
}
