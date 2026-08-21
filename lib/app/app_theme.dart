import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/widgets/app_menu.dart';

/// Giao diện Material 3 dùng màu xanh thống nhất với màn hình chi tiết thiết bị.
class AppTheme {
  static const _seed = Color(0xFF1677FF);

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );
    return _buildTheme(colorScheme, Brightness.light);
  }

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6),
      brightness: Brightness.dark,
    );
    return _buildTheme(colorScheme, Brightness.dark);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme, Brightness brightness) {
    final textTheme = GoogleFonts.interTextTheme(
      brightness == Brightness.light
          ? ThemeData.light().textTheme
          : ThemeData.dark().textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF4F6F8)
          : const Color(0xFF121212),
      cardTheme: CardThemeData(
        elevation: 1,
        margin: EdgeInsets.zero,
        shadowColor: Colors.black.withValues(
          alpha: brightness == Brightness.light ? 0.08 : 0.22,
        ),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          side: BorderSide(
            color: brightness == Brightness.light
                ? const Color(0xFFE2E8F0)
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(
        color: brightness == Brightness.light
            ? const Color(0xFFE2E8F0)
            : colorScheme.outlineVariant.withValues(alpha: 0.4),
        thickness: 1,
        space: 1,
      ),
      // Popup dùng chung bề mặt, viền và độ nổi với hệ thống card hiện tại.
      // PopupMenuButton vẫn tự xử lý focus, bàn phím và vị trí trong viewport.
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: Colors.black.withValues(
          alpha: brightness == Brightness.light ? 0.12 : 0.28,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppMenuStyle.borderRadius,
          side: BorderSide(
            color: brightness == Brightness.light
                ? const Color(0xFFE2E8F0)
                : colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
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
