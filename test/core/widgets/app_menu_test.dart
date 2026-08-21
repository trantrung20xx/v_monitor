import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/core/widgets/app_menu.dart';

void main() {
  testWidgets(
    'menu primitives preserve interaction states without narrow-screen overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var enabledTapCount = 0;
      var disabledTapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppMenuHeader(
                    displayName:
                        'Quản trị viên có họ tên rất dài để kiểm tra thu gọn',
                    roleLabel: 'Quản trị viên',
                  ),
                  AppMenuItem(
                    key: const Key('enabled-menu-item'),
                    icon: Icons.settings_rounded,
                    label: 'Cài đặt',
                    trailing: const Icon(Icons.chevron_right_rounded),
                    tooltip: 'Mở cài đặt',
                    onTap: () => enabledTapCount++,
                  ),
                  AppMenuItem(
                    key: const Key('disabled-menu-item'),
                    icon: Icons.edit_off_rounded,
                    label: 'Tác vụ bị vô hiệu hóa',
                    enabled: false,
                    onTap: () => disabledTapCount++,
                  ),
                  const AppMenuItem(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Lựa chọn đang dùng',
                    selected: true,
                  ),
                  const AppMenuItem(
                    icon: Icons.logout_rounded,
                    label: 'Đăng xuất',
                    isDestructive: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final enabledItem = find.byKey(const Key('enabled-menu-item'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(enabledItem));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await mouse.removePointer();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(enabledTapCount, 1);

      await tester.tap(enabledItem);
      await tester.tap(find.byKey(const Key('disabled-menu-item')));
      await tester.pump();

      expect(enabledTapCount, 2);
      expect(disabledTapCount, 0);
      expect(find.byTooltip('Mở cài đặt'), findsOneWidget);
      final longName = tester.widget<Text>(
        find.text('Quản trị viên có họ tên rất dài để kiểm tra thu gọn'),
      );
      expect(longName.maxLines, 1);
      expect(longName.overflow, TextOverflow.ellipsis);
      final logoutText = tester.widget<Text>(find.text('Đăng xuất'));
      expect(logoutText.style?.color, AppTheme.light.colorScheme.error);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('menu primitives and dropdown surface render in dark theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var selectedValue = 'item-0';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppMenuHeader(
                  displayName: 'Nguyễn Văn A',
                  roleLabel: 'Người xem',
                ),
                const AppMenuItem(
                  icon: Icons.settings_rounded,
                  label: 'Cài đặt',
                ),
                DropdownButton<String>(
                  key: const Key('styled-dropdown'),
                  value: selectedValue,
                  borderRadius: AppMenuStyle.borderRadius,
                  dropdownColor: AppMenuStyle.surfaceColor(context),
                  menuMaxHeight: AppMenuStyle.dropdownMaxHeight(context),
                  items: List.generate(
                    12,
                    (index) => DropdownMenuItem(
                      value: 'item-$index',
                      child: Text('Mục $index'),
                    ),
                  ),
                  onChanged: (value) {
                    if (value != null) selectedValue = value;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final dropdownContext = tester.element(
      find.byKey(const Key('styled-dropdown')),
    );
    expect(
      AppMenuStyle.surfaceColor(dropdownContext),
      AppTheme.dark.colorScheme.surfaceContainerLow,
    );
    await tester.tap(find.byKey(const Key('styled-dropdown')));
    await tester.pumpAndSettle();

    expect(find.text('Mục 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
