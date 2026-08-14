import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      expect(status.freshness, equals(DataFreshnessStatus.fresh));
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
        currentSpeedMps: 0,
        baseStatus: 'ACTIVE',
      );

      expect(status.connectivity, equals(ConnectivityStatus.online));
      expect(status.freshness, equals(DataFreshnessStatus.fresh));
      expect(status.movement, equals(MovementStatus.stopped));
      expect(status.label, equals('Đang dừng'));
      expect(status.color, equals(Colors.orange));
    });

    test('resolve() keeps stale GPS separate from connectivity', () {
      final now = DateTime.now();
      final status = DeviceStatusResolver.resolve(
        isOnline: true,
        lastSeenAt: now.subtract(const Duration(minutes: 3)),
        currentSpeedMps: 10.0,
        baseStatus: 'ACTIVE',
      );

      expect(status.connectivity, equals(ConnectivityStatus.online));
      expect(status.freshness, equals(DataFreshnessStatus.stale));
      expect(status.movement, equals(MovementStatus.unknown));
      expect(status.label, equals('Mất tín hiệu GPS'));
      expect(status.color, equals(Colors.redAccent));
    });

    test('resolve() unknown freshness and offline when lastSeenAt is null', () {
      final status = DeviceStatusResolver.resolve(
        isOnline: true,
        lastSeenAt: null,
        currentSpeedMps: 10.0,
        baseStatus: 'ACTIVE',
      );

      expect(status.connectivity, equals(ConnectivityStatus.offline));
      expect(status.freshness, equals(DataFreshnessStatus.unknown));
      expect(status.movement, equals(MovementStatus.unknown));
    });

    test('resolve() offline does not use old speed as movement', () {
      final now = DateTime.now();
      final status = DeviceStatusResolver.resolve(
        isOnline: false,
        lastSeenAt: now,
        currentSpeedMps: 10.0,
        baseStatus: 'ACTIVE',
      );

      expect(status.connectivity, equals(ConnectivityStatus.offline));
      expect(status.freshness, equals(DataFreshnessStatus.fresh));
      expect(status.movement, equals(MovementStatus.unknown));
      expect(status.label, equals('Ngoại tuyến'));
      expect(status.color, equals(Colors.grey));
    });

    test('resolve() offline when lastSeenAt exceeds online timeout', () {
      final now = DateTime.now();
      final status = DeviceStatusResolver.resolve(
        isOnline: true,
        lastSeenAt: now.subtract(const Duration(minutes: 6)),
        currentSpeedMps: 10.0,
        baseStatus: 'ACTIVE',
      );

      expect(status.connectivity, equals(ConnectivityStatus.offline));
      expect(status.freshness, equals(DataFreshnessStatus.stale));
      expect(status.movement, equals(MovementStatus.unknown));
    });

    test('resolve() inactive management status remains explicit', () {
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
