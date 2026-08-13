import 'package:flutter/material.dart';
import 'app/app.dart';
import 'core/network/api_client.dart';
import 'core/network/websocket_client.dart';

import 'package:flutter/foundation.dart';
import 'package:device_preview/device_preview.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Network Clients
  final apiClient = ApiClient();
  final websocketClient = WebsocketClient();
  
  // Connect to realtime backend
  websocketClient.connect();

  runApp(
    DevicePreview(
      enabled: !kReleaseMode,
      builder: (context) => VMonitorApp(
        apiClient: apiClient,
        websocketClient: websocketClient,
      ),
    ),
  );
}
