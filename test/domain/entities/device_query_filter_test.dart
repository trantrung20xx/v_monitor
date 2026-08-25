// Xác nhận tìm kiếm/bộ lọc thiết bị chỉ tạo lát cắt hiển thị và kết hợp điều kiện đúng.
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/domain/entities/device_query_filter.dart';

void main() {
  group('DeviceQueryFilter', () {
    test('matches device name, code, and type', () {
      final devices = [
        _device(id: '1', name: 'Truck 01', code: 'XE-001', type: 'VEHICLE'),
        _device(
          id: '2',
          name: 'Tay điều khiển Alpha',
          code: 'CTRL-002',
          type: 'UAV_CONTROLLER',
        ),
      ];

      expect(DeviceQueryFilter.filter(devices, query: 'truck 01'), [
        devices[0],
      ]);
      expect(DeviceQueryFilter.filter(devices, query: 'ctrl-002'), [
        devices[1],
      ]);
      expect(DeviceQueryFilter.filter(devices, query: 'uav_controller'), [
        devices[1],
      ]);
    });

    test('filters by resolved status', () {
      final now = DateTime.now();
      final moving = _device(id: 'moving', lastSeenAt: now, speedMps: 12);
      final stopped = _device(id: 'stopped', lastSeenAt: now, speedMps: 0);
      final stale = _device(
        id: 'stale',
        lastSeenAt: now.subtract(const Duration(minutes: 3)),
        speedMps: 12,
      );
      final offline = _device(
        id: 'offline',
        isOnline: false,
        lastSeenAt: now,
        speedMps: 12,
      );
      final devices = [moving, stopped, stale, offline];

      expect(
        DeviceQueryFilter.filter(devices, statusFilter: DeviceFilter.moving),
        [moving],
      );
      expect(
        DeviceQueryFilter.filter(devices, statusFilter: DeviceFilter.stopped),
        [stopped],
      );
      expect(
        DeviceQueryFilter.filter(devices, statusFilter: DeviceFilter.stale),
        [stale],
      );
      expect(
        DeviceQueryFilter.filter(devices, statusFilter: DeviceFilter.offline),
        [offline],
      );
    });
  });
}

DeviceModel _device({
  required String id,
  String name = 'Device',
  String code = 'DEV',
  String type = 'VEHICLE',
  bool isOnline = true,
  DateTime? lastSeenAt,
  double? speedMps,
}) {
  return DeviceModel(
    id: id,
    deviceCode: code,
    name: name,
    type: type,
    status: 'ACTIVE',
    isOnline: isOnline,
    currentSpeedMps: speedMps,
    lastSeenAt: lastSeenAt ?? DateTime.now(),
  );
}
