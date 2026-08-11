import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';

void main() {
  testWidgets('app launches successfully', (tester) async {
    final apiClient = ApiClient();
    final websocketClient = WebsocketClient();
    await tester.pumpWidget(VMonitorApp(apiClient: apiClient, websocketClient: websocketClient));
    expect(find.text('v_monitor'), findsWidgets);
    
    // Cleanup
  });
}
