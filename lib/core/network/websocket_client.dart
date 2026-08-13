import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';

/// Lớp Singleton xử lý kết nối WebSocket đến Backend.
/// Chịu trách nhiệm duy trì kết nối theo thời gian thực và cung cấp Stream cho Repository.
class WebsocketClient {
  /// Địa chỉ kết nối WebSocket. Trong môi trường thực tế, nên đưa biến này vào cấu hình môi trường (.env).
  static const String wsUrl = 'ws://localhost:8000/api/v1/ws';
  WebSocketChannel? _channel;
  
  // StreamController để phát thông điệp.
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// Khởi tạo và thiết lập kết nối WebSocket.
  void connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen(
        (message) {
          if (kDebugMode) print('WS Nhận: $message');
          try {
            // Chuyển đổi dữ liệu chuỗi JSON thành Map
            final data = jsonDecode(message);
            _messageController.add(data);
          } catch (e) {
            if (kDebugMode) print('WS Lỗi parse JSON: $e');
          }
        },
        onDone: () {
          if (kDebugMode) print('WS Kết nối bị đóng, đang thử lại...');
          _retry();
        },
        onError: (error) {
          if (kDebugMode) print('WS Lỗi: $error');
          _retry();
        }
      );
    } catch (e) {
      if (kDebugMode) print('WS Lỗi khởi tạo kết nối: $e');
      _retry();
    }
  }

  /// Cố gắng tự động kết nối lại sau 5 giây nếu kết nối bị đứt.
  void _retry() {
    Future.delayed(const Duration(seconds: 5), () {
      connect();
    });
  }

  /// Đóng kết nối WebSocket một cách chủ động.
  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
  
  /// Dọn dẹp tài nguyên
  void dispose() {
    disconnect();
    _messageController.close();
  }
}
