import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/core/utils/device_formatters.dart';
import 'package:v_monitor/data/models/user_settings_model.dart';

void main() {
  setUp(DeviceFormatters.resetRuntime);
  tearDown(DeviceFormatters.resetRuntime);

  test('coordinates include precision and hemisphere labels', () {
    expect(
      DeviceFormatters.coordinates(21.147, 105.8048),
      '21.14700° N, 105.80480° E',
    );
    expect(
      DeviceFormatters.coordinates(-21.147, -105.8048),
      '21.14700° S, 105.80480° W',
    );
  });

  test('coordinatePair uses readable decimal degrees with hemispheres', () {
    expect(
      DeviceFormatters.coordinatePair(21.147, 105.8048),
      '21.14700° N, 105.80480° E',
    );
  });

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

  test('speed unit changes presentation without changing telemetry value', () {
    DeviceFormatters.configureSpeedUnit(SpeedUnit.mps);
    expect(DeviceFormatters.speedMps(10), '10 m/s');
    expect(DeviceFormatters.speedMps(12.5), '12.5 m/s');

    DeviceFormatters.configureSpeedUnit(SpeedUnit.kmh);
    expect(DeviceFormatters.speedMps(10), '36 km/h');
  });

  test('batteryPct distinguishes missing data from an empty battery', () {
    expect(DeviceFormatters.batteryPct(null), '--');
    expect(DeviceFormatters.batteryPct(0), '0%');
    expect(DeviceFormatters.batteryPct(87), '87%');
  });
}
