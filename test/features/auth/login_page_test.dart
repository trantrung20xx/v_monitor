// Xác nhận màn hình đăng nhập lưu credential và mở luồng giám sát sau xác thực thành công.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app.dart';
import 'package:v_monitor/core/auth/auth_token_store.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';

void main() {
  testWidgets('first login stores the credential and opens monitoring', (
    tester,
  ) async {
    final tokenStore = _MemoryTokenStore();
    final websocketClient = _FakeWebsocketClient();

    await tester.pumpWidget(
      VMonitorApp(
        apiClient: _FakeApiClient(),
        websocketClient: websocketClient,
        authTokenStore: tokenStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('login-username')), 'viewer');
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'Correct-Password-2026!',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(tokenStore.token, 'persistent-credential');
    expect(websocketClient.connectCount, 1);
    expect(find.byKey(const Key('app-brand-logo')), findsOneWidget);
    expect(find.text('Đăng nhập hệ thống'), findsNothing);

    websocketClient.dispose();
  });
}

class _FakeApiClient extends ApiClient {
  static const _user = {
    'id': 'user-1',
    'username': 'viewer',
    'full_name': 'Người xem nội bộ',
    'role': 'USER',
    'is_active': true,
  };

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: path == '/auth/me' ? _user : const [],
    );
  }

  @override
  Future<Response> post(String path, {dynamic data}) async {
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: const {
        'access_token': 'persistent-credential',
        'token_type': 'bearer',
        'user': _user,
      },
    );
  }
}

class _MemoryTokenStore implements AuthTokenStore {
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> clearToken() async => token = null;
}

class _FakeWebsocketClient extends WebsocketClient {
  int connectCount = 0;

  @override
  void connect() => connectCount++;

  @override
  void disconnect() {}
}
