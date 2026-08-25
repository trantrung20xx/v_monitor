// Mở tọa độ bằng ứng dụng bản đồ ngoài hoặc sao chép vị trí. Tọa độ luôn được
// kiểm tra trước để không tạo URL sai hay gửi NaN/Infinity sang hệ điều hành.
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/device_model.dart';

class MapLauncherService {
  /// Kiểm tra biên tọa độ trước khi tạo URL hoặc thao tác clipboard.
  static bool isValidCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    return true;
  }

  static Future<bool> openGoogleMaps(
    double? latitude,
    double? longitude,
  ) async {
    // URL web chính thức hoạt động đa nền tảng và được mở bằng ứng dụng ngoài nếu có.
    if (!isValidCoordinate(latitude, longitude)) return false;
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      return false;
    }
  }

  static Future<bool> openAppleMaps(
    double? latitude,
    double? longitude, {
    String? label,
  }) async {
    // Apple Maps chỉ được mở khi hệ điều hành báo xử lý được URI; label được encode
    // để ký tự tiếng Việt không làm sai query.
    if (!isValidCoordinate(latitude, longitude)) return false;

    final query = Uri.encodeComponent(
      label?.isNotEmpty == true ? label! : '$latitude,$longitude',
    );
    final url = Uri.parse(
      'http://maps.apple.com/?ll=$latitude,$longitude&q=$query',
    );

    try {
      if (await canLaunchUrl(url)) {
        return await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> copyLocationToClipboard(
    DeviceModel device,
    double? lat,
    double? lng,
  ) async {
    // Clipboard dùng URL Google Maps phổ thông để người nhận mở được trên nhiều nền tảng.
    if (!isValidCoordinate(lat, lng)) {
      throw Exception("Invalid coordinates");
    }

    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    await Clipboard.setData(ClipboardData(text: url));
  }
}
