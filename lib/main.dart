import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/network/api_client.dart';
import 'core/network/websocket_client.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final apiClient = ApiClient();
  final websocketClient = WebsocketClient();

  runApp(VMonitorApp(apiClient: apiClient, websocketClient: websocketClient));
}
