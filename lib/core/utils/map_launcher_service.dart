import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../../data/models/device_model.dart';

class MapLauncherService {
  /// Validate GPS coordinates
  static bool isValidCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    return true;
  }

  static Future<bool> openGoogleMaps(double? latitude, double? longitude) async {
    if (!isValidCoordinate(latitude, longitude)) return false;
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$latitude,$longitude');
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
  if (!isValidCoordinate(latitude, longitude)) return false;

  final query = Uri.encodeComponent(label?.isNotEmpty == true ? label! : '$latitude,$longitude');
  final url = Uri.parse('http://maps.apple.com/?ll=$latitude,$longitude&q=$query');

  try {
    if (await canLaunchUrl(url)) {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    }
    return false;
  } catch (e) {
    return false;
  }
}

  static Future<void> copyLocationToClipboard(DeviceModel device, double? lat, double? lng) async {
    if (!isValidCoordinate(lat, lng)) {
      throw Exception("Invalid coordinates");
    }
    
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    await Clipboard.setData(ClipboardData(text: url));
  }
}
