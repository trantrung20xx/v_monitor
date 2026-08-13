import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class MapLauncherService {
  static Future<void> openGoogleMaps(double latitude, double longitude) async {
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$latitude,$longitude');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  static Future<void> openAppleMaps(double latitude, double longitude) async {
    final url = Uri.parse('http://maps.apple.com/?ll=$latitude,$longitude');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  static Future<void> openDefaultMap(double latitude, double longitude) async {
    if (!kIsWeb && Platform.isIOS) {
      await openAppleMaps(latitude, longitude);
    } else {
      await openGoogleMaps(latitude, longitude);
    }
  }
}
