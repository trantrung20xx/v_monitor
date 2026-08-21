import 'package:flutter/material.dart';

enum ConnectivityStatus { online, offline }

enum DataFreshnessStatus { fresh, stale, unknown }

enum MovementStatus { moving, stopped, unknown }

enum ActivityStatus { active, inactive, unknown }

class ResolvedDeviceStatus {
  const ResolvedDeviceStatus({
    required this.connectivity,
    required this.freshness,
    required this.movement,
    required this.activity,
    required this.label,
    required this.color,
  });

  final ConnectivityStatus connectivity;
  final DataFreshnessStatus freshness;
  final MovementStatus movement;
  final ActivityStatus activity;
  final String label;
  final Color color;
}

class DeviceStateThresholds {
  const DeviceStateThresholds({
    this.onlineTimeout = const Duration(minutes: 5),
    this.gpsStaleTimeout = const Duration(minutes: 2),
    this.movementSpeedThresholdMps = 0.5,
  });

  final Duration onlineTimeout;
  final Duration gpsStaleTimeout;
  final double movementSpeedThresholdMps;
}

class DeviceStatusResolver {
  static const DeviceStateThresholds _fallbackThresholds =
      DeviceStateThresholds();
  static DeviceStateThresholds _runtimeThresholds = _fallbackThresholds;

  static DeviceStateThresholds get defaultThresholds => _runtimeThresholds;

  static double get movingThresholdMps =>
      defaultThresholds.movementSpeedThresholdMps;

  static void configureRuntime({
    required Duration onlineTimeout,
    required double movementSpeedThresholdMps,
  }) {
    _runtimeThresholds = DeviceStateThresholds(
      onlineTimeout: onlineTimeout,
      gpsStaleTimeout: _runtimeThresholds.gpsStaleTimeout,
      movementSpeedThresholdMps: movementSpeedThresholdMps,
    );
  }

  static void resetRuntime() {
    _runtimeThresholds = _fallbackThresholds;
  }

  static ResolvedDeviceStatus resolve({
    required bool isOnline,
    required DateTime? lastSeenAt,
    DateTime? latestMeasuredAt,
    required double? currentSpeedMps,
    required String baseStatus,
    DeviceStateThresholds? thresholds,
  }) {
    final activeThresholds = thresholds ?? defaultThresholds;
    final now = DateTime.now();
    final connectionAge = lastSeenAt == null
        ? null
        : now.difference(lastSeenAt.toLocal());
    // Khi backend cũ chưa trả trường mới, dùng lastSeenAt để giữ tương thích.
    final gpsTimestamp = latestMeasuredAt ?? lastSeenAt;
    final gpsAge = gpsTimestamp == null
        ? null
        : now.difference(gpsTimestamp.toLocal());

    final freshness = gpsAge == null
        ? DataFreshnessStatus.unknown
        : gpsAge > activeThresholds.gpsStaleTimeout
        ? DataFreshnessStatus.stale
        : DataFreshnessStatus.fresh;

    final hasRecentConnection =
        connectionAge != null &&
        connectionAge <= activeThresholds.onlineTimeout;
    final connectivity = isOnline && hasRecentConnection
        ? ConnectivityStatus.online
        : ConnectivityStatus.offline;

    var movement = MovementStatus.unknown;
    if (connectivity == ConnectivityStatus.online &&
        freshness == DataFreshnessStatus.fresh &&
        currentSpeedMps != null) {
      movement = currentSpeedMps > activeThresholds.movementSpeedThresholdMps
          ? MovementStatus.moving
          : MovementStatus.stopped;
    }

    var activity = ActivityStatus.unknown;
    if (baseStatus == 'ACTIVE') {
      activity = ActivityStatus.active;
    } else if (baseStatus == 'INACTIVE') {
      activity = ActivityStatus.inactive;
    }

    var label = 'Không xác định';
    Color color = Colors.grey;

    if (connectivity == ConnectivityStatus.offline) {
      label = 'Ngoại tuyến';
      color = Colors.grey;
    } else if (freshness == DataFreshnessStatus.stale) {
      label = 'Mất tín hiệu GPS';
      color = Colors.redAccent;
    } else if (movement == MovementStatus.moving) {
      label = 'Đang di chuyển';
      color = Colors.blue;
    } else if (movement == MovementStatus.stopped) {
      label = 'Đang dừng';
      color = Colors.orange;
    } else if (connectivity == ConnectivityStatus.online) {
      label = 'Trực tuyến';
      color = Colors.green;
    }

    if (activity == ActivityStatus.inactive) {
      label = 'Không hoạt động';
      color = Colors.grey.shade600;
    }

    return ResolvedDeviceStatus(
      connectivity: connectivity,
      freshness: freshness,
      movement: movement,
      activity: activity,
      label: label,
      color: color,
    );
  }
}
