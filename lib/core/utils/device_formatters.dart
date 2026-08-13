import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/device_event_model.dart';
import '../../data/models/device_model.dart';
import '../../data/models/usage_session_model.dart';
import '../../domain/entities/device_status_resolver.dart';

class DeviceFormatters {
  static final DateFormat _shortDateTime = DateFormat('HH:mm dd/MM');
  static final DateFormat _longDateTime = DateFormat('dd/MM/yyyy HH:mm');

  static String displayName(DeviceModel device) {
    if (device.name.trim().isNotEmpty) return device.name.trim();
    if (device.deviceCode.trim().isNotEmpty) return device.deviceCode.trim();
    return 'Unknown device';
  }

  static String deviceTypeLabel(String type) {
    switch (type.toUpperCase()) {
      case 'UAV_CONTROLLER':
        return 'UAV controller';
      case 'VEHICLE':
        return 'Vehicle';
      default:
        return 'Other device';
    }
  }

  static String statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'ONLINE':
        return 'Online';
      case 'OFFLINE':
        return 'Offline';
      case 'ACTIVE':
        return 'Active';
      case 'INACTIVE':
        return 'Inactive';
      case 'MAINTENANCE':
        return 'Maintenance';
      case 'RETIRED':
        return 'Retired';
      default:
        return 'Unknown';
    }
  }

  static IconData statusIcon(ResolvedDeviceStatus status) {
    if (status.connectivity == ConnectivityStatus.stale) {
      return Icons.signal_wifi_statusbar_connected_no_internet_4_rounded;
    }
    if (status.connectivity == ConnectivityStatus.offline) {
      return Icons.wifi_off_rounded;
    }
    if (status.movement == MovementStatus.moving) {
      return Icons.near_me_rounded;
    }
    return Icons.pause_circle_outline_rounded;
  }

  static String speed(DeviceModel device, ResolvedDeviceStatus status) {
    if (status.movement == MovementStatus.stopped) return '0 km/h';
    if (device.currentSpeedMps == null) return '--';
    return '${(device.currentSpeedMps! * 3.6).toStringAsFixed(1)} km/h';
  }

  static String speedValue(DeviceModel device) {
    if (device.currentSpeedMps == null) return '--';
    return (device.currentSpeedMps! * 3.6).toStringAsFixed(1);
  }

  static String battery(DeviceModel device) {
    if (device.uavBatteryPct != null) return '${device.uavBatteryPct}% UAV';
    if (device.controllerBatteryPct != null) {
      return '${device.controllerBatteryPct}% controller';
    }
    return '--';
  }

  static String currentUser(DeviceModel device) {
    final name = device.currentPersonName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Unassigned';
  }

  static String coordinates(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return '--';
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }

  static String location(DeviceModel device, String? address) {
    final value = address?.trim();
    if (value != null && value.isNotEmpty) return value;
    return coordinates(device.latitude, device.longitude);
  }

  static String lastSeen(DateTime? value) {
    if (value == null) return '--';
    final local = value.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return _shortDateTime.format(local);
  }

  static String dateTime(DateTime? value) {
    if (value == null) return '--';
    return _longDateTime.format(value.toLocal());
  }

  static String duration(DateTime start, DateTime? end) {
    final diff = (end ?? DateTime.now()).difference(start);
    if (diff.inMinutes < 1) return '${diff.inSeconds}s';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  static String secondsDuration(int? seconds) {
    if (seconds == null) return '--';
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remaining = minutes.remainder(60);
    if (remaining == 0) return '${hours}h';
    return '${hours}h ${remaining}m';
  }

  static String distance(double? meters) {
    if (meters == null) return '--';
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  static String usageStatus(UsageSessionModel usage) {
    if (usage.endedAt == null || usage.status == 'ACTIVE') return 'Ongoing';
    switch (usage.status) {
      case 'COMPLETED':
        return 'Completed';
      case 'CANCELLED':
        return 'Cancelled';
      default:
        return usage.status;
    }
  }

  static String eventLabel(DeviceEventModel event) {
    switch (event.eventType) {
      case 'DEVICE_STARTED':
      case 'STARTED':
        return 'Device started';
      case 'DEVICE_STOPPED':
      case 'STOPPED':
        return 'Device stopped';
      case 'MOVEMENT_STARTED':
      case 'MOVING':
        return 'Movement started';
      case 'MOVEMENT_STOPPED':
      case 'IDLE':
        return 'Movement stopped';
      case 'USER_ASSIGNED':
      case 'ASSIGNED':
        return 'User assigned';
      case 'USER_RELEASED':
      case 'UNASSIGNED':
        return 'User released';
      case 'GPS_LOST':
        return 'GPS lost';
      case 'GPS_RESTORED':
        return 'GPS restored';
      case 'ONLINE':
        return 'Online';
      case 'OFFLINE':
        return 'Offline';
      case 'BATTERY_LOW':
        return 'Battery low';
      case 'STATUS_CHANGE':
        return 'Status changed';
      case 'ERROR':
        return 'Device error';
      default:
        return 'Event (${event.eventType})';
    }
  }
}
