import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/core/theme/app_theme_colors.dart';

void main() {
  test('light and dark palettes keep readable primary text contrast', () {
    expect(
      AppThemeColors.light.background,
      isNot(AppThemeColors.dark.background),
    );
    expect(AppThemeColors.light.surface, isNot(AppThemeColors.dark.surface));
    expect(AppThemeColors.light.border, isNot(AppThemeColors.dark.border));
    expect(AppThemeColors.light.primary, isNot(AppThemeColors.dark.primary));

    expect(
      _contrastRatio(
        AppThemeColors.light.textPrimary,
        AppThemeColors.light.surface,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(
        AppThemeColors.dark.textPrimary,
        AppThemeColors.dark.surface,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('BuildContext resolves the active light and dark palettes', (
    tester,
  ) async {
    AppThemeColors? resolved;

    Future<void> pumpWith(ThemeMode mode) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: const [AppThemeColors.light],
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [AppThemeColors.dark],
          ),
          themeMode: mode,
          home: Builder(
            builder: (context) {
              resolved = context.appColors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpWith(ThemeMode.light);
    expect(resolved?.background, AppThemeColors.light.background);
    expect(resolved?.textPrimary, AppThemeColors.light.textPrimary);

    await pumpWith(ThemeMode.dark);
    expect(resolved?.background, AppThemeColors.dark.background);
    expect(resolved?.textPrimary, AppThemeColors.dark.textPrimary);
  });
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
