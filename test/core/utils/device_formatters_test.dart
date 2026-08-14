import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/core/utils/device_formatters.dart';

void main() {
  test('coordinates include precision and hemisphere labels', () {
    expect(
      DeviceFormatters.coordinates(21.147, 105.8048),
      '21.147000° N, 105.804800° E',
    );
    expect(
      DeviceFormatters.coordinates(-21.147, -105.8048),
      '21.147000° S, 105.804800° W',
    );
  });

  test(
    'coordinatePair uses decimal latitude and longitude for operations UI',
    () {
      expect(
        DeviceFormatters.coordinatePair(21.147, 105.8048),
        '21.147000, 105.804800',
      );
    },
  );

  test('heading includes Vietnamese compass direction and degree value', () {
    expect(DeviceFormatters.heading(0), 'Bắc · 0°');
    expect(DeviceFormatters.heading(45), 'Đông Bắc · 45°');
    expect(DeviceFormatters.heading(90), 'Đông · 90°');
    expect(DeviceFormatters.heading(180), 'Nam · 180°');
    expect(DeviceFormatters.heading(270), 'Tây · 270°');
    expect(DeviceFormatters.heading(359), 'Bắc · 359°');
  });

  test('speedMps formats backend m/s as km/h consistently', () {
    expect(DeviceFormatters.speedMps(null), '--');
    expect(DeviceFormatters.speedMps(0), '0 km/h');
    expect(DeviceFormatters.speedMps(12.5), '45 km/h');
  });
}
