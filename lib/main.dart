import 'package:flutter/material.dart';
import 'app/app.dart';
import 'core/network/api_client.dart';
import 'core/network/websocket_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Network Clients
  final apiClient = ApiClient();
  final websocketClient = WebsocketClient();
  
  // Connect to realtime backend
  websocketClient.connect();

  runApp(VMonitorApp(
    apiClient: apiClient,
    websocketClient: websocketClient,
  ));
}
