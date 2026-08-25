// Bộ lọc thiết bị thuần: kết hợp từ khóa với trạng thái đã resolve để dashboard,
// bản đồ và quản lý thiết bị dùng cùng quy tắc tìm kiếm.
import '../../data/models/device_model.dart';
import 'device_status_resolver.dart';

// Các lựa chọn UI tương ứng trực tiếp với từng trục trong ResolvedDeviceStatus.
enum DeviceFilter { all, online, offline, moving, stopped, stale }

class DeviceQueryFilter {
  // Lớp thuần không có state; constructor private ngăn tạo instance không cần thiết.
  const DeviceQueryFilter._();

  static List<DeviceModel> filter(
    List<DeviceModel> devices, {
    String query = '',
    DeviceFilter statusFilter = DeviceFilter.all,
  }) {
    // Từ khóa và trạng thái được kết hợp bằng AND; danh sách nguồn không bị sửa.
    final normalizedQuery = query.trim().toLowerCase();

    return devices.where((device) {
      if (!_matchesSearch(device, normalizedQuery)) return false;
      return _matchesStatus(device, statusFilter);
    }).toList();
  }

  static bool _matchesSearch(DeviceModel device, String query) {
    // Tìm trên tên, mã và loại thiết bị đã parse từ backend.
    if (query.isEmpty) return true;
    return device.name.toLowerCase().contains(query) ||
        device.deviceCode.toLowerCase().contains(query) ||
        device.deviceType.toLowerCase().contains(query);
  }

  static bool _matchesStatus(DeviceModel device, DeviceFilter filter) {
    // Luôn dùng resolver chung để kết quả filter khớp badge/màu hiển thị.
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
