// Quản lý một kết nối realtime có AUTH, heartbeat và reconnect tăng dần.
// Control frame được giữ nội bộ; chỉ bản tin nghiệp vụ được phát cho repository.
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

  // URI/factory cố định theo instance; ba Duration điều khiển reconnect và heartbeat.
  final Uri _connectionUri;
  final WebSocketChannelFactory _channelFactory;
  final Duration reconnectDelay;
  final Duration maxReconnectDelay;
  final Duration heartbeatInterval;

  // Nhóm trường dưới tạo máy trạng thái kết nối: channel/subscription hiện tại,
  // hai timer, cờ vòng đời và số lần reconnect liên tiếp.
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

  // Broadcast stream cho phép nhiều repository lọc cùng một kết nối realtime.
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  Uri get connectionUri => _connectionUri;

  void setAccessToken(String? token) {
    final normalized = token?.trim();
    // Chỉ lưu token chuẩn trong bộ nhớ; connect sẽ đọc giá trị mới nhất để gửi AUTH.
    _accessToken = normalized == null || normalized.isEmpty ? null : normalized;
  }

  void setUnauthorizedHandler(WebSocketUnauthorizedHandler? handler) {
    _unauthorizedHandler = handler;
  }

  void connect() {
    // Ba guard ngăn mở socket sau dispose, mở song song hoặc tạo kết nối thứ hai.
    // Guard trả sớm giúp nhiều Cubit cùng gọi connect vẫn chỉ có một socket dùng chung.
    if (_disposed || _isConnecting || _channel != null) return;

    // Một yêu cầu connect mới hủy trạng thái ngắt chủ động và timer reconnect cũ.
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    try {
      // Cờ được đặt trước factory để cả exception đồng bộ cũng được finally dọn đúng.
      _isConnecting = true;
      final channel = _channelFactory(_connectionUri);
      // Gán channel trước listen để callback đồng bộ có thể đối chiếu đúng source.
      _channel = channel;
      _channelSubscription = channel.stream.listen(
        // `source` đi kèm callback để sự kiện đến muộn của socket cũ bị nhận diện.
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
      // Heartbeat bắt đầu cho chính instance channel vừa tạo.
      _startHeartbeat(channel);
    } catch (error) {
      // Factory/listen lỗi được xử lý như một lần đóng kết nối để dùng chung backoff.
      _channel = null;
      _handleConnectionClosed(error: error);
    } finally {
      // Cho phép lần connect tiếp theo sau khi toàn bộ bước khởi tạo đã kết thúc.
      _isConnecting = false;
    }
  }

  void _handleMessage(dynamic message, {WebSocketChannel? source}) {
    final channel = source ?? _channel;
    // Bỏ frame nếu client đã dispose, stream đã đóng hoặc frame đến từ socket cũ.
    // Kiểm tra identity quan trọng hơn so sánh URL vì socket cũ và mới dùng cùng endpoint.
    if (_disposed ||
        channel == null ||
        !identical(_channel, channel) ||
        _messageController.isClosed) {
      return;
    }

    try {
      // WebSocketChannel có thể trả String hoặc byte/object; toString cung cấp đầu vào JSON chung.
      final decoded = jsonDecode(message.toString());
      // Chỉ JSON object mới có trường type và hợp đồng event nghiệp vụ.
      if (decoded is Map<String, dynamic>) {
        // Chỉ đặt lại backoff sau khi đã nhận được một bản tin JSON hợp lệ.
        // Việc mở được TCP nhưng bị proxy đóng ngay không được coi là kết nối ổn định.
        _reconnectAttempt = 0;

        // PONG và AUTH_OK là bản tin điều khiển của chính kết nối. Không phát
        // các bản tin này vào luồng nghiệp vụ và không ghi log mỗi nhịp tim.
        // DEVICE_UPDATE, DEVICE_EVENT và SYSTEM_SETTINGS_UPDATED vẫn được giữ nguyên.
        final type = decoded['type'];
        // Trả sớm để heartbeat không làm repository rebuild hoặc làm đầy log debug.
        if (type == 'PONG' || type == 'AUTH_OK') return;

        // Chỉ log ở debug; release không in payload telemetry liên tục.
        if (kDebugMode) debugPrint('WS received: $message');
        // Broadcast event đã parse cho các repository đang lắng nghe.
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
    // Callback không truyền channel chỉ được dùng cho lỗi xảy ra trước khi gán socket.
    if (channel != null && !identical(_channel, channel)) return;

    // Dọn toàn bộ tài nguyên của phiên hiện tại trước khi quyết định reconnect.
    _stopHeartbeat();
    _channelSubscription?.cancel();
    _channelSubscription = null;
    _channel = null;

    // Dispose hoặc disconnect chủ động không được lên lịch mở lại socket.
    if (_disposed || _manualDisconnect) return;

    // Mã 4401/4403 cho biết khóa đăng nhập đã bị thu hồi hoặc tài khoản không
    // còn quyền. Kết nối không được thử lại cho tới khi đăng nhập thành công.
    if (closeCode == 4401 || closeCode == 4403) {
      // Đặt manualDisconnect để mọi callback/timer còn lại đều bị chặn.
      _manualDisconnect = true;
      final callback = _unauthorizedHandler;
      // AuthCubit xử lý đăng xuất ngoài stack callback của stream.
      if (callback != null) unawaited(callback());
      return;
    }

    if (error != null && kDebugMode) {
      debugPrint('WS error: $error. Reconnecting...');
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    // Mỗi thời điểm chỉ có một timer. Backoff tăng gấp đôi và dừng tăng tại trần
    // để mất mạng lâu không tạo vòng lặp kết nối dày.
    if (_disposed ||
        _manualDisconnect ||
        (_reconnectTimer?.isActive ?? false)) {
      return;
    }

    // Exponent bị chặn để phép nhân không tăng vô hạn khi mạng mất lâu.
    final exponent = _reconnectAttempt > 10 ? 10 : _reconnectAttempt;
    final calculatedDelay = Duration(
      milliseconds: reconnectDelay.inMilliseconds * (1 << exponent),
    );
    final delay = calculatedDelay > maxReconnectDelay
        ? maxReconnectDelay
        : calculatedDelay;
    // Tăng attempt sau khi tính delay để lần đầu dùng đúng reconnectDelay tối thiểu.
    _reconnectAttempt++;

    // Timer một lần xóa tham chiếu trước connect để lần lỗi mới có thể đặt timer tiếp.
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      connect();
    });
  }

  void _startHeartbeat(WebSocketChannel connectedChannel) {
    // Timer gắn với đúng channel đã kết nối; khi socket mới thay thế, timer cũ bị
    // loại qua phép kiểm tra identical.
    // Khoảng không dương tắt heartbeat, hữu ích cho test hoặc môi trường đặc biệt.
    if (heartbeatInterval <= Duration.zero) return;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      final channel = _channel;
      // Nhịp của timer cũ không được gửi vào channel mới sau reconnect.
      if (_disposed ||
          _manualDisconnect ||
          channel == null ||
          !identical(channel, connectedChannel)) {
        return;
      }

      try {
        // sent_at phục vụ chẩn đoán độ trễ; backend chỉ cần type để phản hồi PONG.
        channel.sink.add(
          jsonEncode({
            'type': 'PING',
            'sent_at': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      } catch (error) {
        // Lỗi ghi sink đi qua cùng luồng dọn và reconnect như onDone/onError.
        _handleConnectionClosed(channel: connectedChannel, error: error);
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void disconnect() {
    // Ngắt chủ động hủy timer trước khi đóng sink để onDone không lên lịch reconnect.
    _manualDisconnect = true;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();

    // Chụp tham chiếu trước khi xóa field để callback đến muộn nhận diện đây là socket cũ.
    final subscription = _channelSubscription;
    final channel = _channel;
    _channelSubscription = null;
    _channel = null;

    subscription?.cancel();
    channel?.sink.close();
  }

  void dispose() {
    // Dispose là điểm kết thúc vĩnh viễn: đóng kết nối và stream nghiệp vụ.
    // Đặt cờ trước disconnect để không có nhánh nào lên lịch reconnect trong lúc dọn.
    _disposed = true;
    disconnect();
    // StreamController chỉ được đóng một lần dù dispose bị gọi lặp từ cây dependency.
    if (!_messageController.isClosed) {
      _messageController.close();
    }
  }
}
