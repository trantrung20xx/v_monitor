import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';

class WebsocketClient {
  static const String wsUrl = 'ws://localhost:8000/api/v1/ws';
  WebSocketChannel? _channel;
  
  final List<void Function(Map<String, dynamic>)> _listeners = [];

  void connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen(
        (message) {
          if (kDebugMode) print('WS Received: $message');
          try {
            final data = jsonDecode(message);
            for (var listener in _listeners) {
              listener(data);
            }
          } catch (e) {
            if (kDebugMode) print('WS JSON Parse error: $e');
          }
        },
        onDone: () {
          if (kDebugMode) print('WS Connection closed, retrying...');
          _retry();
        },
        onError: (error) {
          if (kDebugMode) print('WS Error: $error');
          _retry();
        }
      );
    } catch (e) {
      if (kDebugMode) print('WS Connect Error: $e');
      _retry();
    }
  }

  void _retry() {
    Future.delayed(const Duration(seconds: 5), () {
      connect();
    });
  }

  void addListener(void Function(Map<String, dynamic>) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(Map<String, dynamic>) listener) {
    _listeners.remove(listener);
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
