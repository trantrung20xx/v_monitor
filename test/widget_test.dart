import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/app/app.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';

void main() {
  testWidgets('app launches successfully', (tester) async {
    final apiClient = ApiClient();
    final websocketClient = WebsocketClient();
    
    await tester.pumpWidget(VMonitorApp(apiClient: apiClient, websocketClient: websocketClient));
    
    // We expect the text to be either in AppBar or somewhere else, 
    // but just checking if the app boots up properly without exceptions.
    expect(find.byType(VMonitorApp), findsOneWidget);
    
    // Wait for animations and initial API calls to complete
    await tester.pumpAndSettle(const Duration(seconds: 1));
    
    // Cleanup
    websocketClient.dispose();
  });
}
