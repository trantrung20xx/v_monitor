import '../../data/models/device_model.dart';
import 'device_status_resolver.dart';

enum DeviceFilter { all, online, offline, moving, stopped, stale }

class DeviceQueryFilter {
  const DeviceQueryFilter._();

  static List<DeviceModel> filter(
    List<DeviceModel> devices, {
    String query = '',
    DeviceFilter statusFilter = DeviceFilter.all,
  }) {
    final normalizedQuery = query.trim().toLowerCase();

    return devices.where((device) {
      if (!_matchesSearch(device, normalizedQuery)) return false;
      return _matchesStatus(device, statusFilter);
    }).toList();
  }

  static bool _matchesSearch(DeviceModel device, String query) {
    if (query.isEmpty) return true;
    return device.name.toLowerCase().contains(query) ||
        device.deviceCode.toLowerCase().contains(query) ||
        device.deviceType.toLowerCase().contains(query);
  }

  static bool _matchesStatus(DeviceModel device, DeviceFilter filter) {
    if (filter == DeviceFilter.all) return true;

    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      latestMeasuredAt: device.latestMeasuredAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );

    switch (filter) {
      case DeviceFilter.all:
        return true;
      case DeviceFilter.online:
        return status.connectivity == ConnectivityStatus.online;
      case DeviceFilter.offline:
        return status.connectivity == ConnectivityStatus.offline;
      case DeviceFilter.moving:
        return status.movement == MovementStatus.moving;
      case DeviceFilter.stopped:
        return status.movement == MovementStatus.stopped;
      case DeviceFilter.stale:
        return status.freshness == DataFreshnessStatus.stale;
    }
  }
}
