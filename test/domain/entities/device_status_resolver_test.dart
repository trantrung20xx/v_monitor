import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:v_monitor/domain/entities/device_status_resolver.dart';

void main() {
  group('DeviceStatusResolver', () {
    test('resolve() online and moving', () {
      final now = DateTime.now();
      final status = DeviceStatusResolver.resolve(
        isOnline: true,
        lastSeenAt: now.subtract(const Duration(seconds: 10)),
        currentSpeedMps: 10.0,
        baseStatus: 'ACTIVE',
      );

      expect(status.connectivity, equals(ConnectivityStatus.online));
      expect(status.movement, equals(MovementStatus.moving));
      expect(status.activity, equals(ActivityStatus.active));
      expect(status.label, equals('Đang di chuyển'));
      expect(status.color, equals(Colors.blue));
    });

    test('resolve() online and stopped', () {
      final now = DateTime.now();
      final status = DeviceStatusResolver.resolve(
        isOnline: true,
        lastSeenAt: now.subtract(const Duration(seconds: 10)),
        currentSpeedMps: 0.1,
        baseStatus: 'ACTIVE',
      );

      expect(status.connectivity, equals(ConnectivityStatus.online));
      expect(status.movement, equals(MovementStatus.stopped));
      expect(status.label, equals('Đang dừng'));
      expect(status.color, equals(Colors.orange));
    });

    test('resolve() stale because lastSeenAt is too old', () {
      final now = DateTime.now();
      final status = DeviceStatusResolver.resolve(
        isOnline: true,
        lastSeenAt: now.subtract(const Duration(seconds: 300)),
        currentSpeedMps: 10.0,
        baseStatus: 'ACTIVE',
      );

      expect(status.connectivity, equals(ConnectivityStatus.stale));
      expect(status.movement, equals(MovementStatus.unknown));
      expect(status.label, equals('Mất tín hiệu (Stale)'));
      expect(status.color, equals(Colors.redAccent));
    });

    test('resolve() stale because lastSeenAt is null', () {
      final status = DeviceStatusResolver.resolve(
        isOnline: true,
        lastSeenAt: null,
        currentSpeedMps: 10.0,
        baseStatus: 'ACTIVE',
      );

      expect(status.connectivity, equals(ConnectivityStatus.stale));
    });

    test('resolve() offline', () {
      final now = DateTime.now();
      final status = DeviceStatusResolver.resolve(
        isOnline: false,
        lastSeenAt: now,
        currentSpeedMps: 10.0,
        baseStatus: 'ACTIVE',
      );

      expect(status.connectivity, equals(ConnectivityStatus.offline));
      expect(status.movement, equals(MovementStatus.unknown));
      expect(status.label, equals('Ngoại tuyến'));
      expect(status.color, equals(Colors.grey));
    });

    test('resolve() offline and inactive', () {
      final now = DateTime.now();
      final status = DeviceStatusResolver.resolve(
        isOnline: false,
        lastSeenAt: now,
        currentSpeedMps: 10.0,
        baseStatus: 'INACTIVE',
      );

      expect(status.connectivity, equals(ConnectivityStatus.offline));
      expect(status.activity, equals(ActivityStatus.inactive));
      expect(status.label, equals('Không hoạt động'));
      expect(status.color, equals(Colors.grey.shade600));
    });
  });
}
