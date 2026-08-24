import 'package:flutter/material.dart';

import '../theme/app_theme_colors.dart';

/// Các thông số trình bày dùng chung cho popup menu và danh sách lựa chọn nhỏ.
///
/// Widget Material gốc vẫn đảm nhiệm việc đặt menu trong viewport, điều hướng
/// bằng bàn phím, focus và semantics. Các thông số tại đây chỉ đồng bộ phần
/// bề mặt để không làm thay đổi hành vi tương tác sẵn có.
abstract final class AppMenuStyle {
  static const BorderRadius borderRadius = BorderRadius.all(
    Radius.circular(10),
  );
  static const EdgeInsets popupPadding = EdgeInsets.all(6);

  /// Màu bề mặt lấy từ ColorScheme để giữ độ tương phản ở cả light và dark.
  static Color surfaceColor(BuildContext context) {
    return Theme.of(context).colorScheme.surfaceContainerLow;
  }

  /// Giới hạn chiều cao giúp dropdown tự cuộn trước khi chạm mép viewport.
  static double dropdownMaxHeight(BuildContext context) {
    return (MediaQuery.sizeOf(context).height - 32).clamp(112.0, 320.0);
  }
}

/// Dòng hành động dùng bên trong popup menu hoặc bottom sheet dạng menu.
///
/// Khi [onTap] để trống, widget chỉ dựng nội dung để `PopupMenuItem` quản lý
/// toàn bộ focus, hover và callback. Khi [onTap] có giá trị, `InkWell` cung cấp
/// cùng ngôn ngữ tương tác cho menu trên màn hình cảm ứng.
class AppMenuItem extends StatelessWidget {
  const AppMenuItem({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
    this.enabled = true,
    this.selected = false,
    this.isDestructive = false,
    this.touchTarget = false,
    this.tooltip,
    this.semanticLabel,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool enabled;
  final bool selected;
  final bool isDestructive;
  final bool touchTarget;
  final String? tooltip;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = isDestructive
        ? colors.error
        : selected
        ? colors.primary
        : colors.onSurface;
    final iconColor = isDestructive
        ? colors.error
        : selected
        ? colors.primary
        : colors.onSurfaceVariant;
    final opacity = enabled ? 1.0 : 0.38;

    Widget result = ConstrainedBox(
      constraints: BoxConstraints(minHeight: touchTarget ? 48 : 42),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? colors.primaryContainer.withValues(alpha: 0.45)
              : AppPalette.transparent,
          borderRadius: const BorderRadius.all(Radius.circular(7)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 19, color: iconColor.withValues(alpha: opacity)),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground.withValues(alpha: opacity),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                IconTheme(
                  data: IconThemeData(
                    size: 18,
                    color: iconColor.withValues(alpha: opacity),
                  ),
                  child: trailing!,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (onTap == null) return result;

    result = Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(7)),
          onTap: enabled ? onTap : null,
          hoverColor: isDestructive
              ? colors.errorContainer.withValues(alpha: 0.3)
              : colors.surfaceContainerHighest.withValues(alpha: 0.55),
          focusColor: colors.primaryContainer.withValues(alpha: 0.4),
          child: result,
        ),
      ),
    );

    final tooltipMessage = tooltip?.trim();
    return tooltipMessage == null || tooltipMessage.isEmpty
        ? result
        : Tooltip(message: tooltipMessage, child: result);
  }
}

/// Phần nhận diện tài khoản đặt ở đầu account menu.
class AppMenuHeader extends StatelessWidget {
  const AppMenuHeader({
    super.key,
    required this.displayName,
    required this.roleLabel,
    this.onTap,
    this.touchTarget = false,
  });

  final String displayName;
  final String roleLabel;
  final VoidCallback? onTap;
  final bool touchTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final normalizedName = displayName.trim().isEmpty
        ? 'Tài khoản'
        : displayName.trim();

    Widget result = ConstrainedBox(
      constraints: BoxConstraints(minHeight: touchTarget ? 68 : 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: touchTarget ? 21 : 19,
              backgroundColor: colors.primaryContainer,
              foregroundColor: colors.onPrimaryContainer,
              child: Text(
                _initialsFor(normalizedName),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    normalizedName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    roleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );

    if (onTap == null) return result;

    return Semantics(
      button: true,
      label: 'Mở tài khoản $normalizedName',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(7)),
          hoverColor: colors.surfaceContainerHighest.withValues(alpha: 0.55),
          focusColor: colors.primaryContainer.withValues(alpha: 0.4),
          onTap: onTap,
          child: result,
        ),
      ),
    );
  }
}

String _initialsFor(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return '${parts.first.characters.first}${parts.last.characters.first}'
      .toUpperCase();
}
