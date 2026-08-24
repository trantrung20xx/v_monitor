import 'package:flutter/material.dart';

/// Các màu gốc được chủ đích giữ độc lập với theme.
///
/// Bề mặt và văn bản trong giao diện phải dùng [AppThemeColors]. Các giá trị
/// dưới đây chỉ dành cho màu trong suốt, bóng đổ và màu tương phản nằm trên
/// màu trạng thái hoặc màu nhấn, chẳng hạn biểu tượng của điểm đánh dấu bản đồ.
abstract final class AppPalette {
  static const transparent = Color(0x00000000);
  static const onAccent = Color(0xFFFFFFFF);
  static const shadow = Color(0xFF000000);
  static const mapArrow = Color(0xFF0F172A);

  // Giữ nguyên hợp đồng kiểu dữ liệu màu của bộ phân giải trạng thái, đồng thời
  // gom các màu Material cũ của mô hình trình bày về một nơi duy nhất.
  static const materialBlue = Colors.blue;
  static const materialGreen = Colors.green;
  static const materialOrange = Colors.orange;
  static const materialGrey = Colors.grey;
  static const materialGrey600 = Color(0xFF757575);
  static const materialRedAccent = Colors.redAccent;
}

/// Các màu ngữ nghĩa của ứng dụng thay đổi đồng bộ theo light/dark mode.
///
/// Tách các token này khỏi [ColorScheme] được Material sinh tự động giúp giữ
/// phong cách hiện có, đồng thời tạo một nguồn màu duy nhất có nhận biết theme
/// cho toàn bộ thành phần giao diện tùy chỉnh.
@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.background,
    required this.mapBackground,
    required this.surface,
    required this.surfaceSubtle,
    required this.surfaceMuted,
    required this.surfaceRaised,
    required this.border,
    required this.borderSoft,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.primary,
    required this.primaryStrong,
    required this.primarySoft,
    required this.primaryBorder,
    required this.success,
    required this.successStrong,
    required this.successSoft,
    required this.warning,
    required this.warningStrong,
    required this.warningSoft,
    required this.danger,
    required this.dangerStrong,
    required this.dangerSoft,
    required this.orange,
    required this.orangeSoft,
    required this.teal,
    required this.tealSoft,
    required this.tealBorder,
    required this.purple,
    required this.purpleSoft,
    required this.indigo,
    required this.indigoSoft,
    required this.offline,
    required this.shadow,
  });

  static const light = AppThemeColors(
    background: Color(0xFFF4F6F8),
    mapBackground: Color(0xFFEFF5F8),
    surface: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF8FAFC),
    surfaceMuted: Color(0xFFF1F5F9),
    surfaceRaised: Color(0xFFF7F9FC),
    border: Color(0xFFE2E8F0),
    borderSoft: Color(0xFFE4E9ED),
    divider: Color(0xFFE8ECEF),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    textMuted: Color(0xFF94A3B8),
    textDisabled: Color(0xFFCBD5E1),
    primary: Color(0xFF1677FF),
    primaryStrong: Color(0xFF2563EB),
    primarySoft: Color(0xFFEBF3FF),
    primaryBorder: Color(0xFF93C5FD),
    success: Color(0xFF16A34A),
    successStrong: Color(0xFF15803D),
    successSoft: Color(0xFFECFDF5),
    warning: Color(0xFFD97706),
    warningStrong: Color(0xFFB45309),
    warningSoft: Color(0xFFFFFBEB),
    danger: Color(0xFFDC2626),
    dangerStrong: Color(0xFFB91C1C),
    dangerSoft: Color(0xFFFEF2F2),
    orange: Color(0xFFEA580C),
    orangeSoft: Color(0xFFFFF7ED),
    teal: Color(0xFF0D9488),
    tealSoft: Color(0xFFF0FDFA),
    tealBorder: Color(0xFFCCFBF1),
    purple: Color(0xFF7C3AED),
    purpleSoft: Color(0xFFF5F3FF),
    indigo: Color(0xFF6366F1),
    indigoSoft: Color(0xFFEEF2FF),
    offline: Color(0xFF8B949E),
    shadow: Color(0xFF000000),
  );

  static const dark = AppThemeColors(
    background: Color(0xFF121212),
    mapBackground: Color(0xFF111827),
    surface: Color(0xFF1B1F24),
    surfaceSubtle: Color(0xFF20262D),
    surfaceMuted: Color(0xFF29313A),
    surfaceRaised: Color(0xFF242A32),
    border: Color(0xFF3A4654),
    borderSoft: Color(0xFF313B46),
    divider: Color(0xFF36414D),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFCBD5E1),
    textMuted: Color(0xFF94A3B8),
    textDisabled: Color(0xFF64748B),
    primary: Color(0xFF60A5FA),
    primaryStrong: Color(0xFF3B82F6),
    primarySoft: Color(0xFF173B63),
    primaryBorder: Color(0xFF315F91),
    success: Color(0xFF4ADE80),
    successStrong: Color(0xFF22C55E),
    successSoft: Color(0xFF173B29),
    warning: Color(0xFFFBBF24),
    warningStrong: Color(0xFFF59E0B),
    warningSoft: Color(0xFF463510),
    danger: Color(0xFFF87171),
    dangerStrong: Color(0xFFEF4444),
    dangerSoft: Color(0xFF4A2024),
    orange: Color(0xFFFB923C),
    orangeSoft: Color(0xFF472A17),
    teal: Color(0xFF2DD4BF),
    tealSoft: Color(0xFF123B38),
    tealBorder: Color(0xFF28635E),
    purple: Color(0xFFA78BFA),
    purpleSoft: Color(0xFF382B57),
    indigo: Color(0xFF818CF8),
    indigoSoft: Color(0xFF2C315D),
    offline: Color(0xFF94A3B8),
    shadow: Color(0xFF000000),
  );

  final Color background;
  final Color mapBackground;
  final Color surface;
  final Color surfaceSubtle;
  final Color surfaceMuted;
  final Color surfaceRaised;
  final Color border;
  final Color borderSoft;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;
  final Color primary;
  final Color primaryStrong;
  final Color primarySoft;
  final Color primaryBorder;
  final Color success;
  final Color successStrong;
  final Color successSoft;
  final Color warning;
  final Color warningStrong;
  final Color warningSoft;
  final Color danger;
  final Color dangerStrong;
  final Color dangerSoft;
  final Color orange;
  final Color orangeSoft;
  final Color teal;
  final Color tealSoft;
  final Color tealBorder;
  final Color purple;
  final Color purpleSoft;
  final Color indigo;
  final Color indigoSoft;
  final Color offline;
  final Color shadow;

  @override
  AppThemeColors copyWith({
    Color? background,
    Color? mapBackground,
    Color? surface,
    Color? surfaceSubtle,
    Color? surfaceMuted,
    Color? surfaceRaised,
    Color? border,
    Color? borderSoft,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textDisabled,
    Color? primary,
    Color? primaryStrong,
    Color? primarySoft,
    Color? primaryBorder,
    Color? success,
    Color? successStrong,
    Color? successSoft,
    Color? warning,
    Color? warningStrong,
    Color? warningSoft,
    Color? danger,
    Color? dangerStrong,
    Color? dangerSoft,
    Color? orange,
    Color? orangeSoft,
    Color? teal,
    Color? tealSoft,
    Color? tealBorder,
    Color? purple,
    Color? purpleSoft,
    Color? indigo,
    Color? indigoSoft,
    Color? offline,
    Color? shadow,
  }) {
    return AppThemeColors(
      background: background ?? this.background,
      mapBackground: mapBackground ?? this.mapBackground,
      surface: surface ?? this.surface,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      borderSoft: borderSoft ?? this.borderSoft,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textDisabled: textDisabled ?? this.textDisabled,
      primary: primary ?? this.primary,
      primaryStrong: primaryStrong ?? this.primaryStrong,
      primarySoft: primarySoft ?? this.primarySoft,
      primaryBorder: primaryBorder ?? this.primaryBorder,
      success: success ?? this.success,
      successStrong: successStrong ?? this.successStrong,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningStrong: warningStrong ?? this.warningStrong,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerStrong: dangerStrong ?? this.dangerStrong,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      orange: orange ?? this.orange,
      orangeSoft: orangeSoft ?? this.orangeSoft,
      teal: teal ?? this.teal,
      tealSoft: tealSoft ?? this.tealSoft,
      tealBorder: tealBorder ?? this.tealBorder,
      purple: purple ?? this.purple,
      purpleSoft: purpleSoft ?? this.purpleSoft,
      indigo: indigo ?? this.indigo,
      indigoSoft: indigoSoft ?? this.indigoSoft,
      offline: offline ?? this.offline,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppThemeColors lerp(covariant AppThemeColors? other, double t) {
    if (other == null) return this;
    return AppThemeColors(
      background: Color.lerp(background, other.background, t)!,
      mapBackground: Color.lerp(mapBackground, other.mapBackground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSoft: Color.lerp(borderSoft, other.borderSoft, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryStrong: Color.lerp(primaryStrong, other.primaryStrong, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      primaryBorder: Color.lerp(primaryBorder, other.primaryBorder, t)!,
      success: Color.lerp(success, other.success, t)!,
      successStrong: Color.lerp(successStrong, other.successStrong, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningStrong: Color.lerp(warningStrong, other.warningStrong, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerStrong: Color.lerp(dangerStrong, other.dangerStrong, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      orange: Color.lerp(orange, other.orange, t)!,
      orangeSoft: Color.lerp(orangeSoft, other.orangeSoft, t)!,
      teal: Color.lerp(teal, other.teal, t)!,
      tealSoft: Color.lerp(tealSoft, other.tealSoft, t)!,
      tealBorder: Color.lerp(tealBorder, other.tealBorder, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      purpleSoft: Color.lerp(purpleSoft, other.purpleSoft, t)!,
      indigo: Color.lerp(indigo, other.indigo, t)!,
      indigoSoft: Color.lerp(indigoSoft, other.indigoSoft, t)!,
      offline: Color.lerp(offline, other.offline, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension AppThemeColorsContext on BuildContext {
  AppThemeColors get appColors {
    final theme = Theme.of(this);
    return theme.extension<AppThemeColors>() ??
        (theme.brightness == Brightness.dark
            ? AppThemeColors.dark
            : AppThemeColors.light);
  }
}
