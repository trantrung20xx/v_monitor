import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/core/auth/auth_token_store.dart';
import 'package:v_monitor/core/config/map_tile_providers.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';
import 'package:v_monitor/core/theme/app_theme_colors.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/data/models/mqtt_device_sighting_model.dart';
import 'package:v_monitor/data/models/system_settings_model.dart';
import 'package:v_monitor/data/models/user_model.dart';
import 'package:v_monitor/data/models/user_settings_model.dart';
import 'package:v_monitor/data/repositories/settings_repository.dart';
import 'package:v_monitor/features/auth/auth_cubit.dart';
import 'package:v_monitor/features/auth/auth_state.dart';
import 'package:v_monitor/features/settings/settings_cubit.dart';
import 'package:v_monitor/features/settings/settings_page.dart';
import 'package:v_monitor/features/settings/settings_state.dart';

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'V Monitor',
      packageName: 'com.example.v_monitor',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('USER overview shows personal destinations but not admin', (
    tester,
  ) async {
    final harness = await _pumpSettings(
      tester,
      role: 'USER',
      size: const Size(390, 844),
    );

    expect(find.text('Tùy chỉnh V Monitor'), findsNothing);
    expect(
      find.text('Các chức năng được chia theo từng nhóm để dễ tìm và quản lý.'),
      findsNothing,
    );
    expect(find.byKey(const Key('settings-section-personal')), findsOneWidget);
    expect(find.byKey(const Key('settings-section-account')), findsOneWidget);
    expect(find.byKey(const Key('settings-section-about')), findsOneWidget);
    expect(find.text('Quản trị'), findsNothing);
    expect(find.byKey(const Key('settings-section-tracking')), findsNothing);
    expect(find.byKey(const Key('settings-section-devices')), findsNothing);
    expect(find.byKey(const Key('settings-section-users')), findsNothing);
    expect(harness.repository.loadUsersCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ADMIN overview shows all destinations without loading users', (
    tester,
  ) async {
    final harness = await _pumpSettings(
      tester,
      role: 'ADMIN',
      size: const Size(1280, 900),
    );

    expect(find.byKey(const Key('settings-section-personal')), findsOneWidget);
    expect(find.byKey(const Key('settings-section-account')), findsOneWidget);
    expect(find.byKey(const Key('settings-section-about')), findsOneWidget);
    expect(find.text('Quản trị'), findsOneWidget);
    expect(find.byKey(const Key('settings-section-tracking')), findsOneWidget);
    expect(find.byKey(const Key('settings-section-devices')), findsOneWidget);
    expect(find.byKey(const Key('settings-section-users')), findsOneWidget);
    expect(find.byKey(const Key('managed-user-user-2')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('settings-section-personal'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('settings-section-tracking')))
            .dy,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('settings-section-tracking'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('settings-section-about'))).dy,
      ),
    );
    expect(harness.repository.loadUsersCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('USER fallback never renders an admin settings section', (
    tester,
  ) async {
    final harness = await _pumpSettings(
      tester,
      role: 'USER',
      size: const Size(390, 844),
      section: SettingsSection.users,
    );

    expect(find.byKey(const Key('settings-section-account')), findsOneWidget);
    expect(find.byKey(const Key('managed-user-user-2')), findsNothing);
    expect(harness.repository.loadUsersCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing section falls back to overview without runtime error', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      role: 'USER',
      size: const Size(390, 844),
      section: null,
    );

    expect(find.text('Tùy chỉnh V Monitor'), findsNothing);
    expect(find.byKey(const Key('settings-section-personal')), findsOneWidget);
    expect(find.byKey(const Key('settings-section-about')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('software information shows branding and package metadata', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      role: 'USER',
      size: const Size(390, 844),
      section: SettingsSection.about,
    );

    expect(
      find.byKey(const Key('software-information-content')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('software-brand-panel')), findsOneWidget);
    expect(find.byKey(const Key('software-release-panel')), findsOneWidget);
    expect(find.byKey(const Key('software-app-icon')), findsOneWidget);
    expect(find.byKey(const Key('software-name-tile')), findsOneWidget);
    expect(find.byKey(const Key('software-version-tile')), findsOneWidget);
    expect(find.byKey(const Key('software-build-tile')), findsOneWidget);
    expect(find.byKey(const Key('software-package-tile')), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/branding/v_monitor_logo.png')),
      findsOneWidget,
    );
    expect(find.text('V Monitor'), findsWidgets);
    expect(find.text('Phần mềm giám sát thiết bị nội bộ'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('com.example.v_monitor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'theme selection changes MaterialApp and persists in repository',
    (tester) async {
      final harness = await _pumpSettings(
        tester,
        role: 'USER',
        size: const Size(900, 800),
        section: SettingsSection.personal,
      );

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      await tester.tap(find.byKey(const Key('theme-setting')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sáng').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );

      await tester.tap(find.byKey(const Key('theme-setting')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tối').last);
      await tester.pumpAndSettle();

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(harness.repository.userSettings.theme, 'dark');
      await tester.tap(find.byKey(const Key('theme-setting')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theo hệ thống').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      expect(harness.repository.userUpdateCount, 3);
    },
  );

  testWidgets(
    'personal setting list updates map and speed with a responsive menu',
    (tester) async {
      final harness = await _pumpSettings(
        tester,
        role: 'USER',
        size: const Size(390, 844),
        section: SettingsSection.personal,
      );

      expect(find.byTooltip('Chọn Giao diện'), findsOneWidget);
      expect(find.byTooltip('Chọn Loại bản đồ'), findsOneWidget);
      expect(find.byTooltip('Chọn Đơn vị tốc độ'), findsOneWidget);
      expect(
        find.byKey(const Key('personal-settings-content')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('personal-settings-summary')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('personal-settings-grid')), findsOneWidget);
      expect(find.byKey(const Key('personal-save-status')), findsOneWidget);
      expect(find.text('Đã đồng bộ'), findsOneWidget);
      expect(find.text('Theo hệ thống'), findsOneWidget);
      expect(find.text('Tự động theo thiết bị'), findsOneWidget);

      harness.repository.pendingUserUpdate = Completer<void>();
      await tester.tap(find.byKey(const Key('map-type-setting')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.text('Vệ tinh').last);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Đang lưu thay đổi'), findsOneWidget);
      expect(
        tester
            .widget<PopupMenuButton<AppMapType>>(
              find.descendant(
                of: find.byKey(const Key('map-type-setting')),
                matching: find.byType(PopupMenuButton<AppMapType>),
              ),
            )
            .enabled,
        isFalse,
      );
      harness.repository.pendingUserUpdate!.complete();
      await tester.pumpAndSettle();

      expect(harness.repository.userSettings.mapType, AppMapType.satellite);
      expect(find.text('Đã đồng bộ'), findsOneWidget);
      expect(find.text('Vệ tinh'), findsOneWidget);
      expect(find.text('Ảnh thực địa kèm nhãn'), findsOneWidget);

      await tester.tap(find.byKey(const Key('speed-unit-setting')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.text('m/s').last);
      await tester.pumpAndSettle();

      expect(harness.repository.userSettings.speedUnit, SpeedUnit.mps);
      expect(find.text('m/s'), findsOneWidget);
      expect(find.text('Mét mỗi giây'), findsOneWidget);
      expect(harness.repository.userUpdateCount, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('member cannot render the current-account edit action', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      role: 'USER',
      size: const Size(390, 844),
      section: SettingsSection.account,
    );

    expect(find.byKey(const Key('edit-current-account')), findsNothing);
    expect(find.byKey(const Key('account-profile-summary')), findsOneWidget);
    expect(find.byKey(const Key('account-username-detail')), findsOneWidget);
    expect(find.byKey(const Key('account-email-detail')), findsOneWidget);
    expect(find.byKey(const Key('account-role-detail')), findsOneWidget);
    expect(find.byKey(const Key('account-security-panel')), findsOneWidget);
    expect(find.text('Thông tin tài khoản'), findsOneWidget);
    expect(find.text('Bảo mật & phiên đăng nhập'), findsOneWidget);
    expect(find.text('Thành viên'), findsWidgets);
    expect(find.byKey(const Key('open-change-password')), findsOneWidget);
    expect(find.byKey(const Key('logout-from-settings')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin edits own profile without role or status controls', (
    tester,
  ) async {
    final harness = await _pumpSettings(
      tester,
      role: 'ADMIN',
      size: const Size(390, 844),
      section: SettingsSection.account,
    );

    final editButton = find.byKey(const Key('edit-current-account'));
    expect(editButton, findsOneWidget);
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    expect(find.text('Sửa thông tin tài khoản'), findsOneWidget);
    expect(find.byKey(const Key('user-role-field')), findsNothing);
    expect(find.byType(Switch), findsNothing);
    await tester.enterText(
      find.byKey(const Key('user-full-name-field')),
      'Quản trị hệ thống',
    );
    await tester.enterText(
      find.byKey(const Key('user-email-field')),
      'admin.moi@example.test',
    );
    await tester.tap(find.byKey(const Key('save-user-button')));
    await tester.pumpAndSettle();

    expect(harness.repository.lastUpdatedUserId, 'user-1');
    expect(harness.repository.lastUserUpdate, {
      'full_name': 'Quản trị hệ thống',
      'email': 'admin.moi@example.test',
    });
    expect(harness.repository.loadUsersCount, 0);
    expect(harness.authCubit.refreshCurrentUserCount, 1);
    expect(find.byKey(const Key('open-change-password')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tracking validates, prevents duplicate save, and reports API error',
    (tester) async {
      final harness = await _pumpSettings(
        tester,
        role: 'ADMIN',
        size: const Size(1280, 900),
        section: SettingsSection.tracking,
      );
      final saveButton = find.byKey(const Key('save-system-settings'));

      expect(find.byKey(const Key('offline-setting-panel')), findsOneWidget);
      expect(find.byKey(const Key('movement-setting-panel')), findsOneWidget);
      expect(
        find.byKey(const Key('journey-gap-setting-panel')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('tracking-save-panel')), findsOneWidget);
      expect(find.text('Áp dụng ngay sau khi lưu'), findsOneWidget);
      expect(find.text('Cấu hình đã đồng bộ'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('offline-timeout-field')),
        '29',
      );
      await tester.tap(saveButton);
      await tester.pump();
      expect(find.text('Từ 30 đến 86400.'), findsOneWidget);
      expect(find.text('Có thay đổi chưa lưu'), findsOneWidget);
      expect(harness.repository.systemUpdateCount, 0);

      await tester.enterText(
        find.byKey(const Key('offline-timeout-field')),
        '600',
      );
      harness.repository.pendingSystemUpdate = Completer<void>();
      await tester.tap(saveButton);
      await tester.tap(saveButton);
      await tester.pump();
      expect(harness.repository.systemUpdateCount, 1);
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      expect(find.text('Đang áp dụng cấu hình...'), findsOneWidget);

      harness.repository.pendingSystemUpdate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Đã lưu cấu hình theo dõi thiết bị.'), findsOneWidget);
      expect(find.text('Cấu hình đã đồng bộ'), findsOneWidget);
      expect(harness.repository.systemSettings.offlineTimeoutSeconds, 600);

      harness.repository.systemUpdateError = DioException(
        requestOptions: RequestOptions(path: '/system/settings'),
        response: Response(
          requestOptions: RequestOptions(path: '/system/settings'),
          statusCode: 500,
        ),
      );
      await tester.enterText(
        find.byKey(const Key('movement-threshold-field')),
        '0.8',
      );
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(find.text('Không thể lưu cấu hình theo dõi.'), findsOneWidget);
      expect(find.text('Có thay đổi chưa lưu'), findsOneWidget);
      expect(harness.repository.systemUpdateCount, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('admin can edit, lock, change role, and reset password', (
    tester,
  ) async {
    final harness = await _pumpSettings(
      tester,
      role: 'ADMIN',
      size: const Size(1280, 900),
      section: SettingsSection.users,
    );
    final actions = find.byKey(const Key('user-actions-user-2'));

    await tester.ensureVisible(actions);
    await tester.pumpAndSettle();
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sửa tài khoản'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Chọn vai trò'), findsOneWidget);
    await tester.tap(find.text('Thành viên').last);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tap(find.text('Quản trị viên').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('user-role-field')),
        matching: find.text('Quản trị viên'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(Switch).last);
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-user-button')));
    await tester.pumpAndSettle();

    expect(harness.repository.lastUpdatedUserId, 'user-2');
    expect(harness.repository.lastUserUpdate?['role'], 'ADMIN');
    expect(harness.repository.lastUserUpdate?['is_active'], isFalse);

    await tester.ensureVisible(actions);
    await tester.pumpAndSettle();
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đặt lại mật khẩu'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reset-password-field')),
      'matkhau8',
    );
    await tester.enterText(
      find.byKey(const Key('reset-password-confirmation')),
      'matkhau8',
    );
    await tester.tap(find.byKey(const Key('reset-password-button')));
    await tester.pumpAndSettle();

    expect(harness.repository.lastResetUserId, 'user-2');
    expect(harness.repository.lastResetPassword, 'matkhau8');
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact user actions keep create and reload behavior', (
    tester,
  ) async {
    final harness = await _pumpSettings(
      tester,
      role: 'ADMIN',
      size: const Size(390, 844),
      section: SettingsSection.users,
    );

    expect(
      find.text(
        'Tài khoản do quản trị viên tạo; người dùng không thể tự đăng ký.',
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('reload-users-button')), findsOneWidget);
    expect(find.byKey(const Key('create-user-button')), findsOneWidget);
    expect(find.byKey(const Key('user-filter-button')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('user-filter-button')),
        matching: find.text('Bộ lọc'),
      ),
      findsNothing,
    );
    expect(find.text('Thêm tài khoản'), findsNothing);

    await tester.tap(find.byKey(const Key('create-user-button')));
    await tester.pumpAndSettle();
    expect(find.text('Thêm tài khoản'), findsOneWidget);
    expect(find.byKey(const Key('user-full-name-field')), findsOneWidget);
    expect(find.byKey(const Key('user-role-field')), findsOneWidget);
    expect(find.byTooltip('Chọn vai trò'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();

    expect(harness.repository.loadUsersCount, 1);
    await tester.tap(find.byKey(const Key('reload-users-button')));
    await tester.pumpAndSettle();
    expect(harness.repository.loadUsersCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop user toolbar keeps both filters in one control', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      role: 'ADMIN',
      size: const Size(1280, 900),
      section: SettingsSection.users,
    );

    final filterButton = find.byKey(const Key('user-filter-button'));
    expect(filterButton, findsOneWidget);
    expect(
      find.descendant(of: filterButton, matching: find.text('Bộ lọc')),
      findsOneWidget,
    );
    expect(find.text('Vai trò'), findsNothing);
    expect(find.text('Quyền đăng nhập'), findsNothing);

    await tester.tap(filterButton);
    await tester.pumpAndSettle();
    expect(find.text('Vai trò'), findsOneWidget);
    expect(find.text('Quyền đăng nhập'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('user management searches and combines role and login filters', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      role: 'ADMIN',
      size: const Size(390, 844),
      section: SettingsSection.users,
    );

    final member = find.byKey(const Key('managed-user-user-2'));
    final admin = find.byKey(const Key('managed-user-user-3'));
    Future<void> openFilters() async {
      await tester.tap(find.byKey(const Key('user-filter-button')));
      await tester.pumpAndSettle();
    }

    expect(member, findsOneWidget);
    expect(admin, findsOneWidget);
    expect(find.byKey(const Key('user-filter-button')), findsOneWidget);
    expect(find.byKey(const Key('user-active-filter-count')), findsNothing);
    expect(find.byKey(const Key('user-login-status-user-2')), findsOneWidget);
    expect(find.byKey(const Key('user-login-status-user-3')), findsOneWidget);
    expect(find.byTooltip('Được phép đăng nhập'), findsOneWidget);
    expect(find.byTooltip('Không được phép đăng nhập'), findsOneWidget);
    expect(find.text('Được phép đăng nhập'), findsNothing);
    expect(find.text('Không được phép đăng nhập'), findsNothing);
    expect(find.text('Vai trò'), findsNothing);
    expect(find.text('Quyền đăng nhập'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('user-login-status-user-2')),
        matching: find.byIcon(Icons.lock_open_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('user-login-status-user-3')),
        matching: find.byIcon(Icons.lock_rounded),
      ),
      findsOneWidget,
    );

    await openFilters();
    expect(find.text('Vai trò'), findsOneWidget);
    expect(find.text('Mọi vai trò (2)'), findsOneWidget);
    expect(find.text('Thành viên (1)'), findsOneWidget);
    expect(find.text('Quản trị viên (1)'), findsOneWidget);
    expect(find.text('Quyền đăng nhập'), findsOneWidget);
    expect(find.text('Mọi quyền đăng nhập (2)'), findsOneWidget);
    expect(find.text('Được phép (1)'), findsOneWidget);
    expect(find.text('Đã chặn (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('user-filter-all')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('user-search-field')),
      'nhan vien',
    );
    await tester.pump();
    expect(member, findsOneWidget);
    expect(admin, findsNothing);

    await tester.tap(find.byKey(const Key('clear-user-search')));
    await tester.pump();
    await openFilters();
    await tester.tap(find.byKey(const Key('user-filter-admin')));
    await tester.pumpAndSettle();
    expect(member, findsNothing);
    expect(admin, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('user-active-filter-count')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    await openFilters();
    await tester.tap(find.byKey(const Key('user-filter-member')));
    await tester.pumpAndSettle();
    expect(member, findsOneWidget);
    expect(admin, findsNothing);

    await openFilters();
    await tester.tap(find.byKey(const Key('user-filter-all')));
    await tester.pumpAndSettle();
    await openFilters();
    await tester.tap(find.byKey(const Key('user-login-filter-blocked')));
    await tester.pumpAndSettle();
    expect(member, findsNothing);
    expect(admin, findsOneWidget);

    await openFilters();
    await tester.tap(find.byKey(const Key('user-login-filter-allowed')));
    await tester.pumpAndSettle();
    expect(member, findsOneWidget);
    expect(admin, findsNothing);

    await openFilters();
    await tester.tap(find.byKey(const Key('user-filter-admin')));
    await tester.pumpAndSettle();
    expect(member, findsNothing);
    expect(admin, findsNothing);
    expect(find.byKey(const Key('user-filter-empty')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('user-active-filter-count')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    await openFilters();
    await tester.tap(find.byKey(const Key('user-filter-reset')));
    await tester.pumpAndSettle();
    expect(member, findsOneWidget);
    expect(admin, findsOneWidget);
    expect(find.byKey(const Key('user-active-filter-count')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('user-search-field')),
      'không tồn tại',
    );
    await tester.pump();
    expect(find.byKey(const Key('user-filter-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ADMIN device management uses exclusive registered and MQTT tabs',
    (tester) async {
      final harness = await _pumpSettings(
        tester,
        role: 'ADMIN',
        size: const Size(1280, 900),
        section: SettingsSection.devices,
      );

      expect(
        find.byKey(const Key('device-management-content')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('device-management-tabs')), findsOneWidget);
      expect(find.byKey(const Key('registered-devices-tab')), findsOneWidget);
      expect(find.byKey(const Key('pending-devices-tab')), findsOneWidget);
      expect(find.byKey(const Key('device-view-mode-menu')), findsOneWidget);
      expect(
        find.byKey(const Key('pending-devices-tab-badge')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('registered-devices-pane')), findsOneWidget);
      expect(find.byKey(const Key('pending-devices-pane')), findsNothing);
      expect(find.byKey(const Key('registered-device-CAR-01')), findsOneWidget);
      expect(find.byKey(const Key('mqtt-sighting-UAV-100')), findsNothing);
      expect(find.text('Trực tuyến'), findsOneWidget);
      expect(
        find.byTooltip('Được phép nhận dữ liệu · Nhấn để tạm ngừng'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('pending-devices-tab-badge')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const Key('pending-devices-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending-devices-tab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('registered-devices-pane')), findsNothing);
      expect(find.byKey(const Key('pending-devices-pane')), findsOneWidget);
      expect(find.byKey(const Key('registered-device-CAR-01')), findsNothing);
      expect(find.byKey(const Key('mqtt-sighting-UAV-100')), findsOneWidget);
      expect(find.text('Chờ xác nhận'), findsWidgets);
      expect(find.text('KÊNH NHẬN DỮ LIỆU GẦN NHẤT'), findsNothing);
      expect(harness.repository.loadManagedDevicesCount, 1);
      expect(harness.repository.loadMqttSightingsCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ADMIN can register a discovered MQTT device', (tester) async {
    final harness = await _pumpSettings(
      tester,
      role: 'ADMIN',
      size: const Size(1280, 900),
      section: SettingsSection.devices,
    );

    await tester.tap(find.byKey(const Key('pending-devices-tab')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('register-device-UAV-100')),
    );
    await tester.tap(find.byKey(const Key('register-device-UAV-100')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('device-code-field')))
          .controller
          ?.text,
      'UAV-100',
    );

    await tester.tap(find.byKey(const Key('save-device-button')));
    await tester.pumpAndSettle();

    expect(harness.repository.lastDeviceCreate?['device_code'], 'UAV-100');
    expect(find.byKey(const Key('mqtt-sighting-UAV-100')), findsNothing);
    expect(find.byKey(const Key('mqtt-sighting-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('registered-devices-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('registered-device-UAV-100')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'device list switches between compact and detailed presentation',
    (tester) async {
      await _pumpSettings(
        tester,
        role: 'ADMIN',
        size: const Size(1280, 900),
        section: SettingsSection.devices,
      );

      final registeredTile = find.byKey(const Key('registered-device-CAR-01'));
      final compactHeight = tester.getSize(registeredTile).height;
      expect(find.text('Xe'), findsNothing);

      await tester.tap(find.byKey(const Key('device-view-mode-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-view-mode-detailed')));
      await tester.pumpAndSettle();

      expect(find.text('Xe'), findsOneWidget);
      expect(tester.getSize(registeredTile).height, greaterThan(compactHeight));
      expect(
        find.descendant(
          of: registeredTile,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('pending-devices-tab')));
      await tester.pumpAndSettle();
      expect(find.text('KÊNH NHẬN DỮ LIỆU GẦN NHẤT'), findsOneWidget);
      expect(find.text('v_monitor/telemetry/UAV-100'), findsOneWidget);
      expect(find.byKey(const Key('register-device-UAV-100')), findsOneWidget);

      await tester.tap(find.byKey(const Key('device-view-mode-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-view-mode-compact')));
      await tester.pumpAndSettle();

      expect(find.text('KÊNH NHẬN DỮ LIỆU GẦN NHẤT'), findsNothing);
      expect(find.text('v_monitor/telemetry/UAV-100'), findsNothing);
      expect(find.byKey(const Key('register-device-UAV-100')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact device row keeps status with identity and uses theme colors',
    (tester) async {
      for (final theme in const ['light', 'dark']) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await _pumpSettings(
          tester,
          role: 'ADMIN',
          size: const Size(1600, 900),
          section: SettingsSection.devices,
          theme: theme,
          configureRepository: (repository) {
            repository._devices[0] = DeviceModel(
              id: 'device-uav-100',
              deviceCode: 'UAV-100',
              name: 'UAV-100',
              type: 'UAV_CONTROLLER',
              status: 'OFFLINE',
              isEnabled: true,
              isOnline: false,
              lastSeenAt: DateTime.now().subtract(const Duration(minutes: 10)),
            );
          },
        );

        final tile = find.byKey(const Key('registered-device-UAV-100'));
        final identity = find.byKey(const Key('device-identity-UAV-100'));
        final connectivity = find.byKey(
          const Key('device-connectivity-UAV-100'),
        );
        final permission = find.byKey(
          const Key('device-permission-control-UAV-100'),
        );
        final switchFinder = find.byKey(const Key('device-enabled-UAV-100'));

        expect(find.text('UAV-100'), findsOneWidget);
        expect(
          find.descendant(of: identity, matching: connectivity),
          findsOneWidget,
        );
        expect(
          tester.getCenter(connectivity).dx,
          lessThan(tester.getCenter(permission).dx),
        );
        expect(tester.getSize(tile).height, lessThanOrEqualTo(76));

        final context = tester.element(tile);
        final permissionContainer = tester.widget<Container>(permission);
        final permissionDecoration =
            permissionContainer.decoration! as BoxDecoration;
        final dataSwitch = tester.widget<Switch>(switchFinder);
        expect(permissionDecoration.color, context.appColors.surfaceMuted);
        expect(dataSwitch.activeTrackColor, context.appColors.successStrong);
        expect(dataSwitch.inactiveTrackColor, context.appColors.border);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('device management keeps long data readable at every breakpoint', (
    tester,
  ) async {
    const longCode = 'DEVICE-CONTROLLER-WAREHOUSE-NORTH-ENTRANCE-0001';
    const longName =
        'Thiết bị điều phối vận hành khu vực kho hàng phía Bắc và cổng kiểm soát trung tâm';
    const longTopic =
        'v_monitor/telemetry/factory/north-warehouse/entrance/controller-0001';

    for (final size in const [
      Size(320, 700),
      Size(390, 844),
      Size(600, 900),
      Size(800, 900),
      Size(1024, 768),
      Size(1366, 768),
      Size(1600, 900),
      Size(1920, 1080),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _pumpSettings(
        tester,
        role: 'ADMIN',
        size: size,
        section: SettingsSection.devices,
        configureRepository: (repository) {
          repository._devices[0] = DeviceModel(
            id: 'device-long',
            deviceCode: longCode,
            name: longName,
            type: 'UAV_CONTROLLER',
            status: 'OFFLINE',
            serialNumber: 'SERIAL-WAREHOUSE-NORTH-0001',
            isEnabled: false,
            isOnline: false,
            lastSeenAt: DateTime.now().subtract(const Duration(minutes: 8)),
          );
          repository._sightings[0] = MqttDeviceSightingModel(
            deviceCode: 'UNREGISTERED-CONTROLLER-NORTH-ENTRANCE-0002',
            firstSeenAt: DateTime.now().subtract(const Duration(hours: 3)),
            lastSeenAt: DateTime.now().subtract(const Duration(seconds: 15)),
            messageCount: 1287,
            lastTopic: longTopic,
          );
        },
      );

      final maximumControlsHeight = size.width < 600
          ? 135.0
          : size.width < 800
          ? 125.0
          : 120.0;
      expect(
        tester
            .getSize(find.byKey(const Key('device-management-controls')))
            .height,
        lessThanOrEqualTo(maximumControlsHeight),
        reason: 'Controls must stay compact at ${size.width}x${size.height}',
      );
      expect(
        tester.getSize(find.byKey(const Key('device-search-field'))).height,
        40,
      );
      expect(
        tester
            .getSize(find.byKey(const Key('device-permission-filter')))
            .height,
        40,
      );
      expect(
        tester.getSize(find.byKey(const Key('device-view-mode-menu'))).height,
        44,
      );
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byKey(const Key('device-management-tabs')),
                matching: find.byType(TabBar),
              ),
            )
            .height,
        44,
      );

      final nameFinder = find.descendant(
        of: find.byKey(Key('registered-device-$longCode')),
        matching: find.text(longName),
      );
      expect(nameFinder, findsOneWidget);
      expect(tester.widget<Text>(nameFinder).maxLines, isNull);
      expect(
        tester.widget<Text>(nameFinder).overflow,
        isNot(TextOverflow.ellipsis),
      );

      await tester.ensureVisible(find.byKey(const Key('pending-devices-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pending-devices-tab')));
      await tester.pumpAndSettle();

      final topicFinder = find.text(longTopic);
      expect(find.byKey(Key('registered-device-$longCode')), findsNothing);
      expect(topicFinder, findsNothing);

      await tester.tap(find.byKey(const Key('device-view-mode-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-view-mode-detailed')));
      await tester.pumpAndSettle();

      expect(topicFinder, findsOneWidget);
      expect(tester.widget<Text>(topicFinder).maxLines, isNull);
      expect(
        tester.widget<Text>(topicFinder).overflow,
        isNot(TextOverflow.ellipsis),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'Long device data must fit ${size.width}x${size.height}',
      );
    }
  });

  testWidgets(
    'device management search and permission filters stay independent',
    (tester) async {
      await _pumpSettings(
        tester,
        role: 'ADMIN',
        size: const Size(1280, 900),
        section: SettingsSection.devices,
      );

      expect(find.text('Tất cả (1)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('device-permission-filter')));
      await tester.pumpAndSettle();
      expect(find.text('Đang bật nhận dữ liệu (1)'), findsOneWidget);
      expect(find.text('Tạm ngừng nhận dữ liệu (0)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('device-filter-disabled')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('registered-device-empty')), findsOneWidget);
      expect(find.byKey(const Key('mqtt-sighting-UAV-100')), findsNothing);

      await tester.tap(find.byKey(const Key('pending-devices-tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mqtt-sighting-UAV-100')), findsOneWidget);
      expect(find.byKey(const Key('device-permission-filter')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('device-search-field')),
        'UAV-100',
      );
      await tester.pump();
      expect(find.byKey(const Key('mqtt-sighting-UAV-100')), findsOneWidget);

      await tester.tap(find.byKey(const Key('registered-devices-tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('registered-device-empty')), findsOneWidget);
      expect(find.byKey(const Key('mqtt-sighting-UAV-100')), findsNothing);
      expect(find.byKey(const Key('device-permission-filter')), findsOneWidget);

      await tester.tap(find.byKey(const Key('device-permission-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-filter-all')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('clear-device-search')));
      await tester.pump();
      expect(find.byKey(const Key('registered-device-CAR-01')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('device management keeps refresh and add callbacks', (
    tester,
  ) async {
    final harness = await _pumpSettings(
      tester,
      role: 'ADMIN',
      size: const Size(1280, 900),
      section: SettingsSection.devices,
    );

    expect(find.text('Quản lý thiết bị'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('device-management-controls')))
          .height,
      lessThanOrEqualTo(120),
    );
    expect(
      tester.getSize(find.byKey(const Key('device-compact-metrics'))).height,
      lessThanOrEqualTo(36),
    );
    expect(
      tester.getSize(find.byKey(const Key('device-search-field'))).height,
      40,
    );
    expect(
      tester.getSize(find.byKey(const Key('device-permission-filter'))).height,
      40,
    );

    await tester.tap(find.byTooltip('Tải lại cài đặt'));
    await tester.pumpAndSettle();
    expect(harness.repository.loadManagedDevicesCount, 2);
    expect(harness.repository.loadMqttSightingsCount, 2);

    await tester.tap(find.byKey(const Key('add-device-button')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const Key('device-code-field')), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('device-code-field')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('device management refreshes registered status in background', (
    tester,
  ) async {
    final harness = await _pumpSettings(
      tester,
      role: 'ADMIN',
      size: const Size(1280, 900),
      section: SettingsSection.devices,
    );

    expect(find.text('Trực tuyến'), findsOneWidget);
    harness.repository._devices[0] = DeviceModel(
      id: 'device-1',
      deviceCode: 'CAR-01',
      name: 'Xe tuần tra 01',
      type: 'VEHICLE',
      status: 'OFFLINE',
      isEnabled: true,
      isOnline: false,
      lastSeenAt: DateTime.now().subtract(const Duration(minutes: 6)),
    );

    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();

    expect(find.text('Trực tuyến'), findsNothing);
    expect(find.text('Ngoại tuyến'), findsOneWidget);
    expect(harness.repository.loadManagedDevicesCount, 2);
    expect(harness.repository.loadMqttSightingsCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device card applies the shared offline timeout', (tester) async {
    await _pumpSettings(
      tester,
      role: 'ADMIN',
      size: const Size(1280, 900),
      section: SettingsSection.devices,
      configureRepository: (repository) {
        repository._devices[0] = DeviceModel(
          id: 'device-1',
          deviceCode: 'CAR-01',
          name: 'Xe tuần tra 01',
          type: 'VEHICLE',
          status: 'ONLINE',
          isEnabled: true,
          isOnline: true,
          lastSeenAt: DateTime.now().subtract(const Duration(minutes: 10)),
        );
      },
    );

    expect(find.text('Ngoại tuyến'), findsOneWidget);
    expect(find.text('Trực tuyến'), findsNothing);
    expect(find.text('Đang bật'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device editor dialog fits a compact viewport', (tester) async {
    await _pumpSettings(
      tester,
      role: 'ADMIN',
      size: const Size(320, 700),
      section: SettingsSection.devices,
    );

    await tester.drag(find.byType(ListView).last, const Offset(0, -520));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-device-CAR-01')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const Key('device-code-field')), findsOneWidget);
    expect(find.byKey(const Key('device-name-field')), findsOneWidget);
    expect(find.byKey(const Key('save-device-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ADMIN can edit and temporarily pause device data', (
    tester,
  ) async {
    final harness = await _pumpSettings(
      tester,
      role: 'ADMIN',
      size: const Size(1280, 900),
      section: SettingsSection.devices,
    );

    await tester.ensureVisible(find.byKey(const Key('edit-device-CAR-01')));
    await tester.tap(find.byKey(const Key('edit-device-CAR-01')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('device-name-field')),
      'Xe tuần tra trung tâm',
    );
    await tester.tap(find.byKey(const Key('save-device-button')));
    await tester.pumpAndSettle();
    expect(harness.repository.lastUpdatedDeviceId, 'device-1');
    expect(
      harness.repository.lastDeviceUpdate?['name'],
      'Xe tuần tra trung tâm',
    );

    await tester.ensureVisible(find.byKey(const Key('device-enabled-CAR-01')));
    await tester.tap(find.byKey(const Key('device-enabled-CAR-01')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tạm ngừng'));
    await tester.pumpAndSettle();
    expect(harness.repository.lastDeviceUpdate?['is_enabled'], isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('subpages do not render redundant introduction blocks', (
    tester,
  ) async {
    const cases = <SettingsSection, String>{
      SettingsSection.personal:
          'Tùy chỉnh cách ứng dụng hiển thị trên tài khoản này.',
      SettingsSection.account:
          'Xem thông tin và quản lý an toàn cho tài khoản đang đăng nhập.',
      SettingsSection.about:
          'Xem thông tin nhận diện và phiên bản phần mềm đang sử dụng.',
      SettingsSection.tracking:
          'Thiết lập các ngưỡng dùng chung cho hoạt động giám sát thiết bị.',
      SettingsSection.devices:
          'Đăng ký, chỉnh sửa và kiểm soát quyền nhận dữ liệu thiết bị.',
      SettingsSection.users:
          'Quản lý tài khoản nội bộ và phạm vi quyền truy cập.',
    };

    for (final entry in cases.entries) {
      await _pumpSettings(
        tester,
        role: 'ADMIN',
        size: const Size(390, 844),
        section: entry.key,
      );
      expect(find.text(entry.value), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('redesigned settings layouts support dark theme', (tester) async {
    for (final section in const [
      SettingsSection.personal,
      SettingsSection.account,
      SettingsSection.about,
      SettingsSection.tracking,
      SettingsSection.devices,
    ]) {
      await _pumpSettings(
        tester,
        role: 'ADMIN',
        size: const Size(390, 844),
        section: section,
        theme: 'dark',
      );
      expect(
        Theme.of(tester.element(find.byType(SettingsPage))).brightness,
        Brightness.dark,
      );
      if (section == SettingsSection.devices) {
        await tester.ensureVisible(
          find.byKey(const Key('pending-devices-tab')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pending-devices-tab')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pending-devices-pane')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'personal and software layouts adapt to narrow and wide screens',
    (tester) async {
      for (final size in const [
        Size(320, 700),
        Size(390, 844),
        Size(840, 900),
        Size(1440, 900),
      ]) {
        for (final section in const [
          SettingsSection.personal,
          SettingsSection.about,
        ]) {
          await _pumpSettings(
            tester,
            role: 'USER',
            size: size,
            section: section,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$section must fit ${size.width}x${size.height}',
          );
        }
      }
    },
  );

  testWidgets('settings layout has no overflow on mobile and desktop', (
    tester,
  ) async {
    for (final size in const [Size(360, 740), Size(1440, 900)]) {
      for (final section in SettingsSection.values) {
        await _pumpSettings(
          tester,
          role: 'ADMIN',
          size: size,
          section: section,
        );
        expect(find.text(_expectedTitle(section)), findsWidgets);
        if (section == SettingsSection.devices) {
          await tester.ensureVisible(
            find.byKey(const Key('pending-devices-tab')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('pending-devices-tab')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('pending-devices-pane')), findsOneWidget);
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '$section must fit ${size.width}x${size.height}',
        );
      }
    }
  });
}

String _expectedTitle(SettingsSection section) => switch (section) {
  SettingsSection.overview => 'Cài đặt',
  SettingsSection.personal => 'Giao diện & hiển thị',
  SettingsSection.account => 'Tài khoản & bảo mật',
  SettingsSection.about => 'Thông tin phần mềm',
  SettingsSection.tracking => 'Theo dõi thiết bị',
  SettingsSection.devices => 'Quản lý thiết bị',
  SettingsSection.users => 'Quản lý người dùng',
};

class _SettingsHarness {
  const _SettingsHarness({required this.repository, required this.authCubit});

  final _FakeSettingsRepository repository;
  final _StaticAuthCubit authCubit;
}

Future<_SettingsHarness> _pumpSettings(
  WidgetTester tester, {
  required String role,
  required Size size,
  SettingsSection? section = SettingsSection.overview,
  String theme = 'system',
  void Function(_FakeSettingsRepository repository)? configureRepository,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final repository = _FakeSettingsRepository();
  configureRepository?.call(repository);
  repository._userSettings = UserSettingsModel(theme: theme);
  final settingsCubit = SettingsCubit(repository);
  final authCubit = _StaticAuthCubit(
    UserModel(
      id: 'user-1',
      username: role == 'ADMIN' ? 'admin' : 'viewer',
      fullName: role == 'ADMIN' ? 'Quản trị viên' : 'Người xem nội bộ',
      email: '${role.toLowerCase()}@example.test',
      role: role,
      isActive: true,
    ),
  );
  addTearDown(settingsCubit.close);
  addTearDown(authCubit.close);
  addTearDown(repository.dispose);
  addTearDown(repository.websocket.dispose);

  await tester.pumpWidget(
    RepositoryProvider<SettingsRepository>.value(
      value: repository,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthCubit>.value(value: authCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
        ],
        child: BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, state) => MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: state.userSettings.themeMode,
            home: SettingsPage(section: section),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _SettingsHarness(repository: repository, authCubit: authCubit);
}

class _StaticAuthCubit extends AuthCubit {
  _StaticAuthCubit(UserModel user)
    : super(ApiClient(), WebsocketClient(), _EmptyTokenStore()) {
    emit(AuthState(status: AuthStatus.authenticated, user: user));
  }

  int refreshCurrentUserCount = 0;

  @override
  Future<String?> refreshCurrentUser() async {
    refreshCurrentUserCount++;
    return null;
  }

  @override
  Future<void> logout() async {
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }
}

class _EmptyTokenStore implements AuthTokenStore {
  @override
  Future<void> clearToken() async {}

  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> writeToken(String token) async {}
}

class _FakeSettingsRepository extends SettingsRepository {
  factory _FakeSettingsRepository() {
    final websocket = WebsocketClient();
    return _FakeSettingsRepository._(websocket);
  }

  _FakeSettingsRepository._(this.websocket) : super(ApiClient(), websocket);

  final WebsocketClient websocket;
  final _userController = StreamController<UserSettingsModel>.broadcast();
  final _systemController = StreamController<SystemSettingsModel>.broadcast();
  UserSettingsModel _userSettings = const UserSettingsModel();
  SystemSettingsModel _systemSettings = const SystemSettingsModel();
  final List<UserModel> _users = [
    const UserModel(
      id: 'user-2',
      username: 'operator',
      fullName: 'Nhân viên vận hành',
      email: 'operator@example.test',
      role: 'USER',
      isActive: true,
    ),
    const UserModel(
      id: 'user-3',
      username: 'security-admin',
      fullName: 'Quản trị bảo mật',
      email: 'security@example.test',
      role: 'ADMIN',
      isActive: false,
    ),
  ];
  final List<DeviceModel> _devices = [
    DeviceModel(
      id: 'device-1',
      deviceCode: 'CAR-01',
      name: 'Xe tuần tra 01',
      type: 'VEHICLE',
      status: 'ONLINE',
      isEnabled: true,
      isOnline: true,
      lastSeenAt: DateTime.now().subtract(const Duration(minutes: 1)),
    ),
  ];
  final List<MqttDeviceSightingModel> _sightings = [
    MqttDeviceSightingModel(
      deviceCode: 'UAV-100',
      firstSeenAt: DateTime.now().subtract(const Duration(minutes: 5)),
      lastSeenAt: DateTime.now().subtract(const Duration(seconds: 10)),
      messageCount: 3,
      lastTopic: 'v_monitor/telemetry/UAV-100',
    ),
  ];

  int userUpdateCount = 0;
  int systemUpdateCount = 0;
  int loadUsersCount = 0;
  int loadManagedDevicesCount = 0;
  int loadMqttSightingsCount = 0;
  Completer<void>? pendingUserUpdate;
  Completer<void>? pendingSystemUpdate;
  Object? systemUpdateError;
  String? lastUpdatedUserId;
  Map<String, dynamic>? lastUserUpdate;
  Map<String, dynamic>? lastDeviceCreate;
  String? lastUpdatedDeviceId;
  Map<String, dynamic>? lastDeviceUpdate;
  String? lastResetUserId;
  String? lastResetPassword;

  @override
  UserSettingsModel get userSettings => _userSettings;

  @override
  SystemSettingsModel get systemSettings => _systemSettings;

  @override
  Stream<UserSettingsModel> get userSettingsChanges => _userController.stream;

  @override
  Stream<SystemSettingsModel> get systemSettingsChanges =>
      _systemController.stream;

  @override
  Future<UserSettingsModel> loadUserSettings() async {
    _userController.add(_userSettings);
    return _userSettings;
  }

  @override
  Future<SystemSettingsModel> loadSystemSettings() async {
    _systemController.add(_systemSettings);
    return _systemSettings;
  }

  @override
  Future<UserSettingsModel> updateUserSettings(
    Map<String, dynamic> changes,
  ) async {
    userUpdateCount++;
    final pending = pendingUserUpdate;
    if (pending != null) {
      await pending.future;
      pendingUserUpdate = null;
    }
    final preferences = changes['preferences'];
    _userSettings = _userSettings.copyWith(
      theme: changes['theme']?.toString(),
      preferences: preferences is Map
          ? {
              ..._userSettings.preferences,
              ...Map<String, dynamic>.from(preferences),
            }
          : _userSettings.preferences,
    );
    _userController.add(_userSettings);
    return _userSettings;
  }

  @override
  Future<SystemSettingsModel> updateSystemSettings(
    Map<String, dynamic> changes,
  ) async {
    systemUpdateCount++;
    final pending = pendingSystemUpdate;
    if (pending != null) {
      await pending.future;
      pendingSystemUpdate = null;
    }
    final error = systemUpdateError;
    if (error != null) throw error;
    _systemSettings = SystemSettingsModel.fromJson(changes);
    _systemController.add(_systemSettings);
    return _systemSettings;
  }

  @override
  Future<List<UserModel>> loadUsers() async {
    loadUsersCount++;
    return List.unmodifiable(_users);
  }

  @override
  Future<UserModel> createUser(Map<String, dynamic> data) async {
    final user = UserModel(
      id: 'created-user',
      username: data['username'].toString(),
      fullName: data['full_name'].toString(),
      email: data['email']?.toString(),
      role: data['role'].toString(),
      isActive: data['is_active'] == true,
    );
    _users.add(user);
    return user;
  }

  @override
  Future<UserModel> updateUser(String userId, Map<String, dynamic> data) async {
    lastUpdatedUserId = userId;
    lastUserUpdate = data;
    final index = _users.indexWhere((user) => user.id == userId);
    final old = index >= 0
        ? _users[index]
        : UserModel(
            id: userId,
            username: 'admin',
            fullName: 'Quản trị viên',
            email: 'admin@example.test',
            role: 'ADMIN',
            isActive: true,
          );
    final updated = UserModel(
      id: old.id,
      username: old.username,
      fullName: data['full_name']?.toString() ?? old.fullName,
      email: data['email']?.toString(),
      role: data['role']?.toString() ?? old.role,
      isActive: data['is_active'] as bool? ?? old.isActive,
    );
    if (index >= 0) _users[index] = updated;
    return updated;
  }

  @override
  Future<void> resetUserPassword(String userId, String newPassword) async {
    lastResetUserId = userId;
    lastResetPassword = newPassword;
  }

  @override
  Future<List<DeviceModel>> loadManagedDevices() async {
    loadManagedDevicesCount++;
    return List.unmodifiable(_devices);
  }

  @override
  Future<List<MqttDeviceSightingModel>> loadMqttDeviceSightings() async {
    loadMqttSightingsCount++;
    return List.unmodifiable(_sightings);
  }

  @override
  Future<DeviceModel> createDevice(Map<String, dynamic> data) async {
    lastDeviceCreate = data;
    final device = DeviceModel(
      id: 'created-device',
      deviceCode: data['device_code'].toString(),
      name: data['name'].toString(),
      type: data['device_type'].toString(),
      status: 'UNKNOWN',
      isEnabled: data['is_enabled'] != false,
    );
    _devices.add(device);
    _sightings.removeWhere(
      (sighting) => sighting.deviceCode == device.deviceCode,
    );
    return device;
  }

  @override
  Future<DeviceModel> updateDevice(
    String deviceId,
    Map<String, dynamic> data,
  ) async {
    lastUpdatedDeviceId = deviceId;
    lastDeviceUpdate = data;
    final index = _devices.indexWhere((device) => device.id == deviceId);
    final old = _devices[index];
    final updated = DeviceModel(
      id: old.id,
      deviceCode: data['device_code']?.toString() ?? old.deviceCode,
      name: data['name']?.toString() ?? old.name,
      type: data['device_type']?.toString() ?? old.type,
      status: old.status,
      isEnabled: data['is_enabled'] as bool? ?? old.isEnabled,
      serialNumber: data.containsKey('serial_number')
          ? data['serial_number']?.toString()
          : old.serialNumber,
      manufacturer: data.containsKey('manufacturer')
          ? data['manufacturer']?.toString()
          : old.manufacturer,
      model: data.containsKey('model') ? data['model']?.toString() : old.model,
      firmwareVersion: data.containsKey('firmware_version')
          ? data['firmware_version']?.toString()
          : old.firmwareVersion,
      isOnline: old.isOnline,
      lastSeenAt: old.lastSeenAt,
    );
    _devices[index] = updated;
    return updated;
  }

  @override
  Future<void> dispose() async {
    await _userController.close();
    await _systemController.close();
    await super.dispose();
  }
}
