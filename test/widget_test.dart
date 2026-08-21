import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:v_monitor/app/app.dart';
import 'package:v_monitor/app/app_router.dart';
import 'package:v_monitor/core/auth/auth_token_store.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';

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

  testWidgets('app launches successfully', (tester) async {
    final apiClient = _FakeApiClient();
    final websocketClient = _FakeWebsocketClient();

    await tester.pumpWidget(
      VMonitorApp(
        apiClient: apiClient,
        websocketClient: websocketClient,
        authTokenStore: _MemoryTokenStore('saved-credential'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(VMonitorApp), findsOneWidget);
    expect(find.byKey(const Key('app-brand-logo')), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/branding/v_monitor_logo.png')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.hub_rounded), findsNothing);

    websocketClient.dispose();
  });

  testWidgets('desktop account menu opens the separate settings page', (
    tester,
  ) async {
    AppRouter.router.go('/');
    final websocketClient = _FakeWebsocketClient();
    await tester.pumpWidget(
      VMonitorApp(
        apiClient: _FakeApiClient(),
        websocketClient: websocketClient,
        authTokenStore: _MemoryTokenStore('saved-credential'),
      ),
    );
    await tester.pumpAndSettle();

    // Desktop chỉ mở Cài đặt từ menu tài khoản; thanh điều hướng không lặp lại mục này.
    expect(find.text('Cài đặt'), findsNothing);
    await tester.tap(find.text('Tài khoản'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account-menu-settings')), findsOneWidget);
    expect(find.text('Đổi mật khẩu'), findsNothing);
    expect(find.text('Đăng xuất'), findsOneWidget);

    await tester.tap(find.byKey(const Key('account-menu-settings')));
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsWidgets);
    expect(find.text('Cài đặt'), findsOneWidget);
    expect(find.byKey(const Key('settings-section-account')), findsOneWidget);
    expect(find.byKey(const Key('settings-section-about')), findsOneWidget);
    expect(find.byKey(const Key('open-change-password')), findsNothing);

    await tester.tap(find.byKey(const Key('settings-section-account')));
    await tester.pumpAndSettle();

    expect(find.text('Tài khoản & bảo mật'), findsWidgets);
    expect(find.byKey(const Key('open-change-password')), findsOneWidget);

    await tester.tap(find.byTooltip('Quay lại Cài đặt'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-section-account')), findsOneWidget);
    expect(find.byKey(const Key('open-change-password')), findsNothing);

    await tester.tap(find.byKey(const Key('settings-section-about')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('software-app-icon')), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
    expect(find.text('com.example.v_monitor'), findsOneWidget);

    websocketClient.dispose();
  });

  testWidgets('mobile account sheet opens settings and supports logout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppRouter.router.go('/');

    final websocketClient = _FakeWebsocketClient();
    final tokenStore = _MemoryTokenStore('saved-credential');
    await tester.pumpWidget(
      VMonitorApp(
        apiClient: _FakeApiClient(),
        websocketClient: websocketClient,
        authTokenStore: tokenStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cài đặt'), findsNothing);
    expect(find.text('Tài khoản'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mobile-account-destination')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mobile-account-settings')), findsOneWidget);
    expect(find.byKey(const Key('mobile-account-logout')), findsOneWidget);
    expect(find.text('Người xem nội bộ'), findsOneWidget);
    expect(find.text('Người xem'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );

    await tester.tap(find.byKey(const Key('mobile-account-settings')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-section-account')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-section-account')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-change-password')), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('mobile-account-destination')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobile-account-logout')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-username')), findsOneWidget);
    expect(tokenStore.token, isNull);
    expect(tester.takeException(), isNull);

    websocketClient.dispose();
  });

  testWidgets('USER admin settings URL redirects before page construction', (
    tester,
  ) async {
    AppRouter.router.go('/');
    final apiClient = _FakeApiClient();
    final websocketClient = _FakeWebsocketClient();
    await tester.pumpWidget(
      VMonitorApp(
        apiClient: apiClient,
        websocketClient: websocketClient,
        authTokenStore: _MemoryTokenStore('saved-credential'),
      ),
    );
    await tester.pumpAndSettle();

    AppRouter.router.go('/settings/users');
    await tester.pumpAndSettle();

    expect(
      AppRouter.router.routeInformationProvider.value.uri.path,
      '/settings',
    );
    expect(find.byKey(const Key('settings-section-account')), findsOneWidget);
    expect(find.byKey(const Key('create-user-button')), findsNothing);
    expect(apiClient.authMeCount, 1);
    expect(tester.takeException(), isNull);

    websocketClient.dispose();
  });

  testWidgets('ADMIN can open the protected user settings URL', (tester) async {
    AppRouter.router.go('/');
    final apiClient = _FakeApiClient(role: 'ADMIN');
    final websocketClient = _FakeWebsocketClient();
    await tester.pumpWidget(
      VMonitorApp(
        apiClient: apiClient,
        websocketClient: websocketClient,
        authTokenStore: _MemoryTokenStore('saved-credential'),
      ),
    );
    await tester.pumpAndSettle();

    AppRouter.router.go('/settings/users');
    await tester.pumpAndSettle();

    expect(
      AppRouter.router.routeInformationProvider.value.uri.path,
      '/settings/users',
    );
    expect(find.byKey(const Key('create-user-button')), findsOneWidget);
    expect(apiClient.authMeCount, 1);
    expect(tester.takeException(), isNull);

    websocketClient.dispose();
  });

  testWidgets('app shows login when no credential has been saved', (
    tester,
  ) async {
    final websocketClient = _FakeWebsocketClient();
    await tester.pumpWidget(
      VMonitorApp(
        apiClient: _FakeApiClient(),
        websocketClient: websocketClient,
        authTokenStore: _MemoryTokenStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Đăng nhập hệ thống'), findsOneWidget);
    expect(find.byKey(const Key('login-username')), findsOneWidget);
    expect(find.byKey(const Key('login-password')), findsOneWidget);

    websocketClient.dispose();
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.role = 'USER'});

  final String role;
  int authMeCount = 0;

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/auth/me') authMeCount++;
    final data = switch (path) {
      '/auth/me' => {
        'id': 'user-1',
        'username': role == 'ADMIN' ? 'admin' : 'viewer',
        'full_name': role == 'ADMIN' ? 'Quản trị viên' : 'Người xem nội bộ',
        'role': role,
        'is_active': true,
      },
      '/auth/settings' => const {
        'theme': 'system',
        'language': 'vi',
        'timezone': 'Asia/Ho_Chi_Minh',
        'preferences': {'map_type': 'street', 'speed_unit': 'kmh'},
      },
      '/system/settings' => const {
        'offline_timeout_seconds': 300,
        'movement_threshold_mps': 0.5,
        'default_gap_threshold_seconds': 300,
      },
      _ => const [],
    };
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: data,
    );
  }
}

class _MemoryTokenStore implements AuthTokenStore {
  _MemoryTokenStore([this.token]);

  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> clearToken() async => token = null;
}

class _FakeWebsocketClient extends WebsocketClient {
  @override
  void connect() {}

  @override
  void disconnect() {}
}
