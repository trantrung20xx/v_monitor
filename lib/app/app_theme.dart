// Chuyển bảng màu tập trung thành ThemeData sáng/tối của Material.
// File chỉ cấu hình hình thức widget; màu nghiệp vụ lấy từ AppThemeColors.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_theme_colors.dart';
import '../core/widgets/app_menu.dart';

/// Giao diện Material 3 dùng màu xanh thống nhất với màn hình chi tiết thiết bị.
class AppTheme {
  static ThemeData get light {
    // Seed light tạo ColorScheme Material; các surface/trạng thái tùy chỉnh vẫn lấy
    // từ chính AppThemeColors.light được gắn dưới dạng ThemeExtension.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppThemeColors.light.primary,
      brightness: Brightness.light,
    );
    return _buildTheme(colorScheme, AppThemeColors.light);
  }

  static ThemeData get dark {
    // Dark dùng bảng token riêng để bảo đảm tương phản, không đảo màu light tự động.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppThemeColors.dark.primaryStrong,
      brightness: Brightness.dark,
    );
    return _buildTheme(colorScheme, AppThemeColors.dark);
  }

  static ThemeData _buildTheme(
    ColorScheme colorScheme,
    AppThemeColors appColors,
  ) {
    // Một hàm dựng dùng chung giữ kích thước, bo góc và typography giống nhau giữa
    // hai mode; chỉ màu thay theo colorScheme/AppThemeColors.
    final brightness = colorScheme.brightness;
    final textTheme = GoogleFonts.interTextTheme(
      brightness == Brightness.light
          ? ThemeData.light().textTheme
          : ThemeData.dark().textTheme,
    );

    // ThemeData dưới đây cấu hình các widget nền tảng. Widget tùy chỉnh đọc thêm
    // `context.appColors` để dùng token nghiệp vụ success/warning/danger.
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      extensions: [appColors],
      textTheme: textTheme,
      scaffoldBackgroundColor: appColors.background,
      cardTheme: CardThemeData(
        elevation: 1,
        margin: EdgeInsets.zero,
        shadowColor: appColors.shadow.withValues(
          alpha: brightness == Brightness.light ? 0.08 : 0.22,
        ),
        surfaceTintColor: AppPalette.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: appColors.border, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: AppPalette.transparent,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(
        color: appColors.divider,
        thickness: 1,
        space: 1,
      ),
      // Popup dùng chung bề mặt, viền và độ nổi với hệ thống card hiện tại.
      // PopupMenuButton tự xử lý focus, bàn phím và vị trí trong viewport.
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: AppPalette.transparent,
        elevation: 4,
        shadowColor: appColors.shadow.withValues(
          alpha: brightness == Brightness.light ? 0.12 : 0.28,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppMenuStyle.borderRadius,
          side: BorderSide(color: appColors.border),
        ),
        menuPadding: AppMenuStyle.popupPadding,
        position: PopupMenuPosition.under,
        iconColor: colorScheme.onSurfaceVariant,
        iconSize: 20,
        textStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        mouseCursor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.disabled)
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click;
        }),
      ),
      // ListTile, button và input dùng cấu hình toàn cục để form/dialog không lặp style.
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: colorScheme.onSurfaceVariant,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
      // NavigationRail cho desktop và NavigationBar cho mobile dùng cùng scheme.
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelSmall?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.onPrimaryContainer);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
      ),
    );
  }
}
