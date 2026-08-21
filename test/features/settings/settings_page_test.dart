import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/core/auth/auth_token_store.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';
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

    expect(find.byKey(const Key('software-app-icon')), findsOneWidget);
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

      await tester.enterText(
        find.byKey(const Key('offline-timeout-field')),
        '29',
      );
      await tester.tap(saveButton);
      await tester.pump();
      expect(find.text('Từ 30 đến 86400.'), findsOneWidget);
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

      harness.repository.pendingSystemUpdate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Đã lưu cấu hình theo dõi thiết bị.'), findsOneWidget);
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
      expect(harness.repository.systemUpdateCount, 2);
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
    await tester.tap(find.text('Thành viên').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quản trị viên').last);
    await tester.pumpAndSettle();
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
    expect(find.text('Thêm tài khoản'), findsNothing);

    await tester.tap(find.byKey(const Key('create-user-button')));
    await tester.pumpAndSettle();
    expect(find.text('Thêm tài khoản'), findsOneWidget);
    expect(find.byKey(const Key('user-full-name-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();

    expect(harness.repository.loadUsersCount, 1);
    await tester.tap(find.byKey(const Key('reload-users-button')));
    await tester.pumpAndSettle();
    expect(harness.repository.loadUsersCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('user management searches without accents and filters roles', (
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
    expect(member, findsOneWidget);
    expect(admin, findsOneWidget);
    expect(find.text('Tất cả (2)'), findsOneWidget);
    expect(find.text('Thành viên (1)'), findsOneWidget);
    expect(find.text('Quản trị viên (1)'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('user-search-field')),
      'nhan vien',
    );
    await tester.pump();
    expect(member, findsOneWidget);
    expect(admin, findsNothing);

    await tester.tap(find.byKey(const Key('clear-user-search')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('user-filter-admin')));
    await tester.tap(find.byKey(const Key('user-filter-admin')));
    await tester.pump();
    expect(member, findsNothing);
    expect(admin, findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('user-filter-member')));
    await tester.tap(find.byKey(const Key('user-filter-member')));
    await tester.pump();
    expect(member, findsOneWidget);
    expect(admin, findsNothing);

    await tester.enterText(
      find.byKey(const Key('user-search-field')),
      'không tồn tại',
    );
    await tester.pump();
    expect(find.byKey(const Key('user-filter-empty')), findsOneWidget);
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
        expect(tester.takeException(), isNull);
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
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final repository = _FakeSettingsRepository();
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
      isActive: true,
    ),
  ];

  int userUpdateCount = 0;
  int systemUpdateCount = 0;
  int loadUsersCount = 0;
  Completer<void>? pendingSystemUpdate;
  Object? systemUpdateError;
  String? lastUpdatedUserId;
  Map<String, dynamic>? lastUserUpdate;
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
  Future<void> dispose() async {
    await _userController.close();
    await _systemController.close();
    await super.dispose();
  }
}
