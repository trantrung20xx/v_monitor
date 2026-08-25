// Điểm khởi động Flutter: tạo một HTTP client và một WebSocket client dùng chung,
// sau đó truyền vào cây ứng dụng để mọi repository dùng cùng kết nối và token.
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/network/api_client.dart';
import 'core/network/websocket_client.dart';

void main() {
  // Hàm được runtime Flutter gọi đúng một lần để dựng dependency gốc của ứng dụng.
  // Khởi tạo binding trước khi plugin lưu token/package info cần gọi kênh nền tảng.
  WidgetsFlutterBinding.ensureInitialized();

  // Hai client là singleton theo vòng đời ứng dụng để toàn bộ repository dùng cùng
  // base URL, Bearer token, kết nối WebSocket và cơ chế retry/reconnect.
  final apiClient = ApiClient();
  final websocketClient = WebsocketClient();

  runApp(VMonitorApp(apiClient: apiClient, websocketClient: websocketClient));
}
