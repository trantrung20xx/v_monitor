import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app.dart';
import 'package:v_monitor/core/auth/auth_token_store.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';

void main() {
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
  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final data = path == '/auth/me'
        ? const {
            'id': 'user-1',
            'username': 'viewer',
            'full_name': 'Người xem nội bộ',
            'role': 'USER',
            'is_active': true,
          }
        : const [];
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
