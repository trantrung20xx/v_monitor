import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';

void main() {
  testWidgets('app launches successfully', (tester) async {
    final apiClient = _FakeApiClient();
    final websocketClient = WebsocketClient();

    await tester.pumpWidget(
      VMonitorApp(apiClient: apiClient, websocketClient: websocketClient),
    );

    expect(find.byType(VMonitorApp), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 1));

    websocketClient.dispose();
  });
}

class _FakeApiClient extends ApiClient {
  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: const [],
    );
  }
}
