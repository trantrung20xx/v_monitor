import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/device_event_model.dart';
import '../../data/models/device_model.dart';
import '../../domain/entities/device_status_resolver.dart';

class DeviceFormatters {
  static final DateFormat _shortDateTime = DateFormat('dd/MM/yyyy HH:mm');
  static final DateFormat _longDateTime = DateFormat('dd/MM/yyyy HH:mm');
  static final DateFormat _longDateTimeSeconds = DateFormat(
    'dd/MM/yyyy HH:mm:ss',
  );

  static String displayName(DeviceModel device) {
    if (device.name.trim().isNotEmpty) return device.name.trim();
    if (device.deviceCode.trim().isNotEmpty) return device.deviceCode.trim();
    return 'Thiết bị không xác định';
  }

  static String deviceTypeLabel(String type) {
    switch (type.toUpperCase()) {
      case 'UAV_CONTROLLER':
        return 'Điều khiển UAV';
      case 'VEHICLE':
        return 'Xe';
      default:
        return 'Thiết bị khác';
    }
  }

  static String statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'ONLINE':
        return 'Trực tuyến';
      case 'OFFLINE':
        return 'Ngoại tuyến';
      case 'ACTIVE':
        return 'Đang hoạt động';
      case 'INACTIVE':
        return 'Không hoạt động';
      case 'MAINTENANCE':
        return 'Bảo trì';
      case 'RETIRED':
        return 'Ngừng sử dụng';
      default:
        return 'Không xác định';
    }
  }

  static IconData statusIcon(ResolvedDeviceStatus status) {
    if (status.connectivity == ConnectivityStatus.offline) {
      return Icons.wifi_off_rounded;
    }
    if (status.freshness == DataFreshnessStatus.stale) {
      return Icons.signal_wifi_statusbar_connected_no_internet_4_rounded;
    }
    if (status.movement == MovementStatus.moving) {
      return Icons.near_me_rounded;
    }
    return Icons.pause_circle_outline_rounded;
  }

  static String speed(DeviceModel device, ResolvedDeviceStatus status) {
    if (status.movement == MovementStatus.stopped) return '0 km/h';
    if (status.movement != MovementStatus.moving ||
        device.currentSpeedMps == null) {
      return '--';
    }
    return '${(device.currentSpeedMps! * 3.6).toStringAsFixed(1)} km/h';
  }

  static String speedValue(DeviceModel device) {
    if (device.currentSpeedMps == null) return '--';
    return (device.currentSpeedMps! * 3.6).toStringAsFixed(1);
  }

  static String speedMps(double? speedMps) {
    if (speedMps == null) return '--';
    final kmh = speedMps * 3.6;
    if (kmh.abs() >= 10 || kmh == 0) {
      return '${kmh.toStringAsFixed(0)} km/h';
    }
    return '${kmh.toStringAsFixed(1)} km/h';
  }

  /// Định dạng mức pin của chính thiết bị. Giá trị null được hiển thị bằng dấu
  /// gạch để phân biệt trạng thái chưa nhận dữ liệu với mức pin thực tế bằng 0%.
  static String batteryPct(int? value) {
    if (value == null) return '--';
    return '$value%';
  }

  static String heading(double? degrees) {
    if (degrees == null) return '--';
    final normalized = degrees % 360;
    final positive = normalized < 0 ? normalized + 360 : normalized;
    final directions = [
      'Bắc',
      'Đông Bắc',
      'Đông',
      'Đông Nam',
      'Nam',
      'Tây Nam',
      'Tây',
      'Tây Bắc',
    ];
    final index = ((positive + 22.5) ~/ 45) % directions.length;
    return '${directions[index]} · ${positive.toStringAsFixed(0)}°';
  }

  static String coordinates(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return '--';
    return '${latitudeText(latitude)}, ${longitudeText(longitude)}';
  }

  static String coordinatePair(double? latitude, double? longitude) {
    return coordinates(latitude, longitude);
  }

  static String latitudeText(double latitude) {
    final direction = latitude >= 0 ? 'N' : 'S';
    return '${latitude.abs().toStringAsFixed(5)}° $direction';
  }

  static String longitudeText(double longitude) {
    final direction = longitude >= 0 ? 'E' : 'W';
    return '${longitude.abs().toStringAsFixed(5)}° $direction';
  }

  static String location(DeviceModel device, String? address) {
    final value = address?.trim();
    if (value != null && value.isNotEmpty) return value;
    return coordinates(device.latitude, device.longitude);
  }

  static String speedKmh(
    double? speedMps, {
    required ResolvedDeviceStatus status,
  }) {
    if (status.connectivity == ConnectivityStatus.offline) return '--';
    if (status.movement == MovementStatus.stopped) return '0 km/h';
    if (status.movement != MovementStatus.moving || speedMps == null) {
      return '--';
    }
    final kmh = speedMps * 3.6;
    if (kmh < 0.5) return '0 km/h';
    if (kmh >= 10 || kmh == kmh.roundToDouble()) {
      return '${kmh.toStringAsFixed(0)} km/h';
    }
    return '${kmh.toStringAsFixed(1)} km/h';
  }

  static String headingText(
    double? degrees, {
    required ResolvedDeviceStatus status,
  }) {
    if (status.connectivity == ConnectivityStatus.offline || degrees == null) {
      return '--';
    }
    return heading(degrees);
  }

  static (String, String) addressLines(
    String? rawAddress, {
    double? latitude,
    double? longitude,
  }) {
    final value = rawAddress?.trim();
    if (value != null && value.isNotEmpty) {
      final parts = value
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.length <= 1) return (value, '');
      if (parts.length == 2) return (parts.first, parts.last);
      final firstLine = parts.take(2).join(', ');
      final secondLine = parts.skip(2).join(', ');
      return (firstLine, secondLine);
    }
    if (latitude != null && longitude != null) {
      return (coordinates(latitude, longitude), '');
    }
    return ('Chưa có dữ liệu vị trí', '');
  }

  static String relativeTime(DateTime? value) {
    if (value == null) return '--';
    final local = value.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.isNegative || diff.inSeconds < 5) return 'Vừa xong';
    if (diff.inSeconds < 60) return '${diff.inSeconds} giây trước';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 30) return '${diff.inDays} ngày trước';
    return _shortDateTime.format(local);
  }

  static String lastSeen(DateTime? value) {
    if (value == null) return '--';
    final local = value.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inSeconds < 45) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return _shortDateTime.format(local);
  }

  static String gpsFreshness(
    ResolvedDeviceStatus status,
    DateTime? lastSeenAt,
  ) {
    final age = lastSeen(lastSeenAt);
    switch (status.freshness) {
      case DataFreshnessStatus.fresh:
        return 'GPS mới · $age';
      case DataFreshnessStatus.stale:
        return 'GPS cũ · $age';
      case DataFreshnessStatus.unknown:
        return 'Chưa có GPS';
    }
  }

  static String dateTime(DateTime? value) {
    if (value == null) return '--';
    return _longDateTime.format(value.toLocal());
  }

  static String dateTimeSeconds(DateTime? value) {
    if (value == null) return '--';
    return _longDateTimeSeconds.format(value.toLocal());
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

  static String eventLabel(DeviceEventModel event) {
    switch (event.eventType) {
      case 'DEVICE_STARTED':
      case 'STARTED':
        return 'Thiết bị khởi động';
      case 'DEVICE_STOPPED':
      case 'STOPPED':
        return 'Thiết bị dừng';
      case 'MOVEMENT_STARTED':
      case 'MOVING':
        return 'Bắt đầu di chuyển';
      case 'MOVEMENT_STOPPED':
      case 'IDLE':
        return 'Dừng di chuyển';
      case 'GPS_LOST':
        return 'Mất GPS';
      case 'GPS_RESTORED':
        return 'GPS khôi phục';
      case 'ONLINE':
        return 'Trực tuyến';
      case 'OFFLINE':
        return 'Ngoại tuyến';
      case 'STATUS_CHANGE':
        return 'Đổi trạng thái';
      case 'ERROR':
        return 'Lỗi thiết bị';
      default:
        return 'Sự kiện (${event.eventType})';
    }
  }
}
