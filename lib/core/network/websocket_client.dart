import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';

typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);
typedef WebSocketUnauthorizedHandler = Future<void> Function();

class WebsocketClient {
  WebsocketClient({
    Uri? connectionUri,
    WebSocketChannelFactory? channelFactory,
    Duration? reconnectDelay,
    Duration? maxReconnectDelay,
    Duration? heartbeatInterval,
  }) : _connectionUri = connectionUri ?? AppConfig.websocketUri,
       _channelFactory = channelFactory ?? WebSocketChannel.connect,
       reconnectDelay = reconnectDelay ?? AppConfig.websocketReconnectMinDelay,
       maxReconnectDelay =
           maxReconnectDelay ?? AppConfig.websocketReconnectMaxDelay,
       heartbeatInterval =
           heartbeatInterval ?? AppConfig.websocketHeartbeatInterval;

  final Uri _connectionUri;
  final WebSocketChannelFactory _channelFactory;
  final Duration reconnectDelay;
  final Duration maxReconnectDelay;
  final Duration heartbeatInterval;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _disposed = false;
  bool _manualDisconnect = false;
  bool _isConnecting = false;
  int _reconnectAttempt = 0;
  String? _accessToken;
  WebSocketUnauthorizedHandler? _unauthorizedHandler;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  Uri get connectionUri => _connectionUri;

  void setAccessToken(String? token) {
    final normalized = token?.trim();
    _accessToken = normalized == null || normalized.isEmpty ? null : normalized;
  }

  void setUnauthorizedHandler(WebSocketUnauthorizedHandler? handler) {
    _unauthorizedHandler = handler;
  }

  void connect() {
    if (_disposed || _isConnecting || _channel != null) return;

    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    try {
      _isConnecting = true;
      final channel = _channelFactory(_connectionUri);
      _channel = channel;
      _channelSubscription = channel.stream.listen(
        (message) => _handleMessage(message, source: channel),
        onDone: () => _handleConnectionClosed(
          channel: channel,
          closeCode: channel.closeCode,
        ),
        onError: (error) =>
            _handleConnectionClosed(channel: channel, error: error),
        cancelOnError: true,
      );
      final token = _accessToken;
      if (token != null) {
        // Bản tin AUTH được gửi ngay sau khi mở socket để khóa đăng nhập không
        // xuất hiện trong URL, access log hoặc lịch sử của reverse proxy.
        channel.sink.add(jsonEncode({'type': 'AUTH', 'access_token': token}));
      }
      _startHeartbeat(channel);
    } catch (error) {
      _channel = null;
      _handleConnectionClosed(error: error);
    } finally {
      _isConnecting = false;
    }
  }

  void _handleMessage(dynamic message, {WebSocketChannel? source}) {
    final channel = source ?? _channel;
    if (_disposed ||
        channel == null ||
        !identical(_channel, channel) ||
        _messageController.isClosed) {
      return;
    }

    try {
      final decoded = jsonDecode(message.toString());
      if (decoded is Map<String, dynamic>) {
        // Chỉ đặt lại backoff sau khi đã nhận được một bản tin JSON hợp lệ.
        // Việc mở được TCP nhưng bị proxy đóng ngay không được coi là kết nối ổn định.
        _reconnectAttempt = 0;

        // PONG và AUTH_OK là bản tin điều khiển của chính kết nối. Không phát
        // các bản tin này vào luồng nghiệp vụ và không ghi log mỗi nhịp tim.
        // DEVICE_UPDATE, DEVICE_EVENT và SYSTEM_SETTINGS_UPDATED vẫn được giữ nguyên.
        final type = decoded['type'];
        if (type == 'PONG' || type == 'AUTH_OK') return;

        if (kDebugMode) debugPrint('WS received: $message');
        _messageController.add(decoded);
      } else if (kDebugMode) {
        debugPrint('WS ignored non-object message: $message');
      }
    } catch (error) {
      if (kDebugMode) debugPrint('WS JSON parse error: $error');
    }
  }

  void _handleConnectionClosed({
    WebSocketChannel? channel,
    Object? error,
    int? closeCode,
  }) {
    // Callback của socket cũ có thể đến sau khi socket mới đã được tạo. Không
    // cho callback cũ xóa nhầm kết nối hiện tại hoặc tạo thêm bộ hẹn giờ reconnect.
    if (channel != null && !identical(_channel, channel)) return;

    _stopHeartbeat();
    _channelSubscription?.cancel();
    _channelSubscription = null;
    _channel = null;

    if (_disposed || _manualDisconnect) return;

    // Mã 4401/4403 cho biết khóa đăng nhập đã bị thu hồi hoặc tài khoản không
    // còn quyền. Kết nối không được thử lại cho tới khi đăng nhập thành công.
    if (closeCode == 4401 || closeCode == 4403) {
      _manualDisconnect = true;
      final callback = _unauthorizedHandler;
      if (callback != null) unawaited(callback());
      return;
    }

    if (error != null && kDebugMode) {
      debugPrint('WS error: $error. Reconnecting...');
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed ||
        _manualDisconnect ||
        (_reconnectTimer?.isActive ?? false)) {
      return;
    }

    final exponent = _reconnectAttempt > 10 ? 10 : _reconnectAttempt;
    final calculatedDelay = Duration(
      milliseconds: reconnectDelay.inMilliseconds * (1 << exponent),
    );
    final delay = calculatedDelay > maxReconnectDelay
        ? maxReconnectDelay
        : calculatedDelay;
    _reconnectAttempt++;

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      connect();
    });
  }

  void _startHeartbeat(WebSocketChannel connectedChannel) {
    if (heartbeatInterval <= Duration.zero) return;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      final channel = _channel;
      if (_disposed ||
          _manualDisconnect ||
          channel == null ||
          !identical(channel, connectedChannel)) {
        return;
      }

      try {
        channel.sink.add(
          jsonEncode({
            'type': 'PING',
            'sent_at': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      } catch (error) {
        _handleConnectionClosed(channel: connectedChannel, error: error);
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();

    final subscription = _channelSubscription;
    final channel = _channel;
    _channelSubscription = null;
    _channel = null;

    subscription?.cancel();
    channel?.sink.close();
  }

  void dispose() {
    _disposed = true;
    disconnect();
    if (!_messageController.isClosed) {
      _messageController.close();
    }
  }
}
