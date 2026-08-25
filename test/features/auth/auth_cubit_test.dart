// Xác nhận vòng đời token, khôi phục phiên, thu hồi 401, quyền ADMIN và đổi mật khẩu.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/core/auth/auth_token_store.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';
import 'package:v_monitor/data/models/user_model.dart';
import 'package:v_monitor/features/auth/auth_cubit.dart';
import 'package:v_monitor/features/auth/auth_state.dart';

void main() {
  test('admin access requires completed authentication and ADMIN role', () {
    const admin = UserModel(
      id: 'admin-1',
      username: 'admin',
      fullName: 'Quản trị viên',
      role: 'ADMIN',
      isActive: true,
    );
    const viewer = UserModel(
      id: 'user-1',
      username: 'viewer',
      fullName: 'Người xem nội bộ',
      role: 'USER',
      isActive: true,
    );

    expect(const AuthState(user: admin).hasAdminAccess, isFalse);
    expect(
      const AuthState(
        status: AuthStatus.authenticated,
        user: viewer,
      ).hasAdminAccess,
      isFalse,
    );
    expect(
      const AuthState(
        status: AuthStatus.authenticated,
        user: admin,
      ).hasAdminAccess,
      isTrue,
    );
  });

  test('initialize opens the app with a valid stored credential', () async {
    final apiClient = _FakeApiClient();
    final websocketClient = _FakeWebsocketClient();
    final tokenStore = _MemoryTokenStore('saved-credential');
    final cubit = AuthCubit(apiClient, websocketClient, tokenStore);
    addTearDown(cubit.close);

    await cubit.initialize();

    expect(cubit.state.status, AuthStatus.authenticated);
    expect(cubit.state.user?.username, 'viewer');
    expect(apiClient.accessToken, 'saved-credential');
    expect(websocketClient.accessToken, 'saved-credential');
    expect(websocketClient.connectCount, 1);
  });

  test('refresh current user replaces profile with backend data', () async {
    final apiClient = _FakeApiClient();
    final cubit = AuthCubit(
      apiClient,
      _FakeWebsocketClient(),
      _MemoryTokenStore('saved-credential'),
    );
    addTearDown(cubit.close);
    await cubit.initialize();

    apiClient.meUser = const {
      'id': 'user-1',
      'username': 'viewer',
      'full_name': 'Tên vừa cập nhật',
      'email': 'new-email@example.test',
      'role': 'USER',
      'is_active': true,
    };
    final error = await cubit.refreshCurrentUser();

    expect(error, isNull);
    expect(cubit.state.user?.fullName, 'Tên vừa cập nhật');
    expect(cubit.state.user?.email, 'new-email@example.test');
    expect(apiClient.meCount, 2);
  });

  test(
    'initialize keeps the credential when the server is unavailable',
    () async {
      final apiClient = _FakeApiClient()
        ..getError = DioException(
          requestOptions: RequestOptions(path: '/auth/me'),
          type: DioExceptionType.connectionError,
        );
      final websocketClient = _FakeWebsocketClient();
      final tokenStore = _MemoryTokenStore('saved-credential');
      final cubit = AuthCubit(apiClient, websocketClient, tokenStore);
      addTearDown(cubit.close);

      await cubit.initialize();

      expect(cubit.state.status, AuthStatus.serverUnavailable);
      expect(tokenStore.token, 'saved-credential');
      expect(tokenStore.clearCount, 0);
    },
  );

  test('login stores the credential and connects realtime updates', () async {
    final apiClient = _FakeApiClient();
    final websocketClient = _FakeWebsocketClient();
    final tokenStore = _MemoryTokenStore();
    final cubit = AuthCubit(apiClient, websocketClient, tokenStore);
    addTearDown(cubit.close);

    await cubit.initialize();
    await cubit.login('viewer', 'Correct-Password-2026!');

    expect(cubit.state.status, AuthStatus.authenticated);
    expect(tokenStore.token, 'new-persistent-credential');
    expect(websocketClient.connectCount, 1);
  });

  test(
    'reopening the app restores login without sending the password',
    () async {
      final tokenStore = _MemoryTokenStore();
      final firstApiClient = _FakeApiClient();
      final firstWebsocketClient = _FakeWebsocketClient();
      final firstCubit = AuthCubit(
        firstApiClient,
        firstWebsocketClient,
        tokenStore,
      );

      await firstCubit.initialize();
      await firstCubit.login('viewer', 'Correct-Password-2026!');
      await firstCubit.close();

      final reopenedApiClient = _FakeApiClient();
      final reopenedWebsocketClient = _FakeWebsocketClient();
      final reopenedCubit = AuthCubit(
        reopenedApiClient,
        reopenedWebsocketClient,
        tokenStore,
      );
      addTearDown(reopenedCubit.close);
      await reopenedCubit.initialize();

      expect(reopenedCubit.state.status, AuthStatus.authenticated);
      expect(reopenedApiClient.loginCount, 0);
      expect(reopenedApiClient.meCount, 1);
      expect(reopenedWebsocketClient.connectCount, 1);
    },
  );

  test('HTTP revocation clears the stored credential and logs out', () async {
    final apiClient = _FakeApiClient();
    final websocketClient = _FakeWebsocketClient();
    final tokenStore = _MemoryTokenStore('saved-credential');
    final cubit = AuthCubit(apiClient, websocketClient, tokenStore);
    addTearDown(cubit.close);

    await cubit.initialize();
    await apiClient.triggerUnauthorized();

    expect(cubit.state.status, AuthStatus.unauthenticated);
    expect(tokenStore.token, isNull);
    expect(websocketClient.disconnectCount, greaterThan(0));
  });

  test(
    'changing password clears the credential on the current machine',
    () async {
      final apiClient = _FakeApiClient();
      final websocketClient = _FakeWebsocketClient();
      final tokenStore = _MemoryTokenStore('saved-credential');
      final cubit = AuthCubit(apiClient, websocketClient, tokenStore);
      addTearDown(cubit.close);

      await cubit.initialize();
      final error = await cubit.changePassword(
        currentPassword: 'Old-Password-2026!',
        newPassword: 'New-Password-2026!',
      );

      expect(error, isNull);
      expect(cubit.state.status, AuthStatus.unauthenticated);
      expect(cubit.state.message, contains('Mật khẩu đã thay đổi'));
      expect(tokenStore.token, isNull);
    },
  );
}

class _MemoryTokenStore implements AuthTokenStore {
  _MemoryTokenStore([this.token]);

  String? token;
  int clearCount = 0;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> clearToken() async {
    clearCount++;
    token = null;
  }
}

class _FakeApiClient extends ApiClient {
  String? accessToken;
  UnauthorizedHandler? unauthorizedHandler;
  DioException? getError;
  int loginCount = 0;
  int meCount = 0;
  Map<String, dynamic> meUser = Map<String, dynamic>.from(_user);

  static const _user = {
    'id': 'user-1',
    'username': 'viewer',
    'full_name': 'Người xem nội bộ',
    'role': 'USER',
    'is_active': true,
  };

  @override
  void setAccessToken(String? token) => accessToken = token;

  @override
  void setUnauthorizedHandler(UnauthorizedHandler? handler) {
    unauthorizedHandler = handler;
  }

  Future<void> triggerUnauthorized() async {
    await unauthorizedHandler?.call();
  }

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (getError != null) throw getError!;
    if (path == '/auth/me') meCount++;
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: meUser,
    );
  }

  @override
  Future<Response> post(String path, {dynamic data}) async {
    if (path == '/auth/login') loginCount++;
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: path == '/auth/change-password' ? 204 : 200,
      data: path == '/auth/login'
          ? const {
              'access_token': 'new-persistent-credential',
              'token_type': 'bearer',
              'user': _user,
            }
          : null,
    );
  }
}

class _FakeWebsocketClient extends WebsocketClient {
  String? accessToken;
  WebSocketUnauthorizedHandler? unauthorizedHandler;
  int connectCount = 0;
  int disconnectCount = 0;

  @override
  void setAccessToken(String? token) => accessToken = token;

  @override
  void setUnauthorizedHandler(WebSocketUnauthorizedHandler? handler) {
    unauthorizedHandler = handler;
  }

  @override
  void connect() => connectCount++;

  @override
  void disconnect() => disconnectCount++;
}
