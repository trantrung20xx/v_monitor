import 'package:flutter/material.dart';

enum ConnectivityStatus {
  online,
  offline,
  stale
}

enum MovementStatus {
  moving,
  stopped,
  unknown
}

enum ActivityStatus {
  active,
  inactive,
  unknown
}

class ResolvedDeviceStatus {
  final ConnectivityStatus connectivity;
  final MovementStatus movement;
  final ActivityStatus activity;
  final String label;
  final Color color;

  const ResolvedDeviceStatus({
    required this.connectivity,
    required this.movement,
    required this.activity,
    required this.label,
    required this.color,
  });
}

class DeviceStatusResolver {
  static const double movingThresholdMps = 0.5;
  static const int staleThresholdSeconds = 120; // 2 minutes

  static ResolvedDeviceStatus resolve({
    required bool isOnline,
    required DateTime? lastSeenAt,
    required double? currentSpeedMps,
    required String baseStatus, // ACTIVE, INACTIVE, UNKNOWN
  }) {
    final now = DateTime.now();
    bool isStale = false;

    if (lastSeenAt != null) {
      final diff = now.difference(lastSeenAt).inSeconds;
      if (diff > staleThresholdSeconds) {
        isStale = true;
      }
    } else {
      isStale = true; // No data means stale/unknown
    }

    // Determine connectivity
    ConnectivityStatus connectivity = ConnectivityStatus.offline;
    if (isOnline && !isStale) {
      connectivity = ConnectivityStatus.online;
    } else if (isOnline && isStale) {
      connectivity = ConnectivityStatus.stale;
    }

    // Determine movement
    MovementStatus movement = MovementStatus.unknown;
    if (connectivity == ConnectivityStatus.online) {
      if (currentSpeedMps != null) {
        movement = currentSpeedMps > movingThresholdMps
            ? MovementStatus.moving
            : MovementStatus.stopped;
      } else {
        movement = MovementStatus.stopped;
      }
    } else {
      movement = MovementStatus.unknown; // Offline/stale cannot be moving reliably
    }

    // Determine activity
    ActivityStatus activity = ActivityStatus.unknown;
    if (baseStatus == 'ACTIVE') {
      activity = ActivityStatus.active;
    } else if (baseStatus == 'INACTIVE') {
      activity = ActivityStatus.inactive;
    }

    // Determine overall label and color
    String label = 'Không xác định';
    Color color = Colors.grey;

    if (connectivity == ConnectivityStatus.online) {
      if (movement == MovementStatus.moving) {
        label = 'Đang di chuyển';
        color = Colors.blue;
      } else {
        label = 'Đang dừng';
        color = Colors.orange;
      }
    } else if (connectivity == ConnectivityStatus.stale) {
      label = 'Mất tín hiệu (Stale)';
      color = Colors.redAccent;
    } else {
      label = 'Ngoại tuyến';
      color = Colors.grey;
    }

    if (activity == ActivityStatus.inactive) {
      label = 'Không hoạt động';
      color = Colors.grey.shade600;
    }

    return ResolvedDeviceStatus(
      connectivity: connectivity,
      movement: movement,
      activity: activity,
      label: label,
      color: color,
    );
  }
}
