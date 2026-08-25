// Tùy chọn cá nhân đã lưu: theme, ngôn ngữ, múi giờ, thông báo, loại bản đồ và đơn vị tốc độ.
// Các getter chuyển chuỗi API thành enum Flutter với giá trị dự phòng an toàn.
import 'package:flutter/material.dart';

import '../../core/config/map_tile_providers.dart';

// Đơn vị tốc độ trình bày; dữ liệu domain/backend luôn giữ m/s.
enum SpeedUnit { kmh, mps }

class UserSettingsModel {
  // Cài đặt cá nhân của tài khoản; preferences chứa tùy chọn mở rộng như map_type/speed_unit.
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
    // Sao chép preferences thành Map mới để model không giữ tham chiếu mutable từ response Dio.
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
    // copyWith tạo snapshot optimistic/đã xác nhận mới cho SettingsState.
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
