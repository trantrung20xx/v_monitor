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
}
