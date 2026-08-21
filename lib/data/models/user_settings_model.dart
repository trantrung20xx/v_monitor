import 'package:flutter/material.dart';

import '../../core/config/map_tile_providers.dart';

enum SpeedUnit { kmh, mps }

class UserSettingsModel {
  const UserSettingsModel({
    this.theme = 'system',
    this.language = 'vi',
    this.timezone = 'Asia/Ho_Chi_Minh',
    this.notificationsEnabled = true,
    this.preferences = const {},
  });

  final String theme;
  final String language;
  final String timezone;
  final bool notificationsEnabled;
  final Map<String, dynamic> preferences;

  ThemeMode get themeMode {
    switch (theme) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  AppMapType get mapType => preferences['map_type'] == 'satellite'
      ? AppMapType.satellite
      : AppMapType.standard;

  SpeedUnit get speedUnit =>
      preferences['speed_unit'] == 'mps' ? SpeedUnit.mps : SpeedUnit.kmh;

  factory UserSettingsModel.fromJson(Map<String, dynamic> json) {
    final rawPreferences = json['preferences'];
    return UserSettingsModel(
      theme: switch (json['theme']) {
        'light' => 'light',
        'dark' => 'dark',
        _ => 'system',
      },
      language: json['language']?.toString() ?? 'vi',
      timezone: json['timezone']?.toString() ?? 'Asia/Ho_Chi_Minh',
      notificationsEnabled: json['notifications_enabled'] != false,
      preferences: rawPreferences is Map
          ? Map<String, dynamic>.from(rawPreferences)
          : const {},
    );
  }

  UserSettingsModel copyWith({
    String? theme,
    String? language,
    String? timezone,
    bool? notificationsEnabled,
    Map<String, dynamic>? preferences,
  }) {
    return UserSettingsModel(
      theme: theme ?? this.theme,
      language: language ?? this.language,
      timezone: timezone ?? this.timezone,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      preferences: preferences ?? this.preferences,
    );
  }
}
