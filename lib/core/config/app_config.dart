// Nguồn cấu hình kết nối của Flutter tại thời điểm build. Các getter chuẩn hóa
// API/WS URL và kiểm tra timeout để lỗi cấu hình dừng sớm thay vì hỏng âm thầm khi chạy.
class AppConfig {
  AppConfig._();

  /// Tên môi trường chỉ dùng để nhận diện bản dựng trong log và kiểm thử.
  /// Giá trị được truyền bằng `--dart-define-from-file`; ứng dụng không đọc
  /// tệp cấu hình trực tiếp khi đang chạy nên hoạt động giống nhau trên web,
  /// Android, iOS, Windows, macOS và Linux.
  static const String environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  /// URL gốc của REST API, bao gồm cả tiền tố phiên bản `/api/v1`.
  /// Đây là giá trị duy nhất bắt buộc phải đổi khi chuyển từ máy cục bộ sang
  /// Cloudflare Tunnel hoặc máy chủ của doanh nghiệp.
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );

  /// Chỉ cấu hình khi WebSocket chạy trên host khác REST API. Khi để trống,
  /// host và cổng được lấy từ API_BASE_URL; http/https tự đổi thành ws/wss.
  static const String _wsBaseUrl = String.fromEnvironment('WS_BASE_URL');

  /// Đường dẫn endpoint WebSocket trên host đã xác định; không chứa domain.
  static const String _wsPath = String.fromEnvironment(
    'WS_PATH',
    defaultValue: '/api/v1/ws',
  );

  /// Thời gian tối đa chờ mở kết nối HTTP trước khi Dio báo timeout.
  static const int _connectTimeoutSeconds = int.fromEnvironment(
    'CONNECT_TIMEOUT_SECONDS',
    defaultValue: 10,
  );

  /// Chỉ GET mới được thử lại tự động vì đây là thao tác không làm thay đổi
  /// dữ liệu. POST và PATCH không được thử lại để tránh tạo bản ghi hai lần.
  static const int _httpGetRetryCount = int.fromEnvironment(
    'HTTP_GET_RETRY_COUNT',
    defaultValue: 2,
  );

  /// Khoảng chờ cơ sở giữa các lần thử GET; mỗi lần lỗi tiếp theo sẽ tăng gấp đôi.
  static const int _httpRetryDelayMilliseconds = int.fromEnvironment(
    'HTTP_RETRY_DELAY_MS',
    defaultValue: 400,
  );

  /// Khoảng chờ nhỏ nhất trước lần kết nối lại WebSocket đầu tiên.
  static const int _websocketReconnectMinSeconds = int.fromEnvironment(
    'WS_RECONNECT_MIN_SECONDS',
    defaultValue: 2,
  );

  /// Trần khoảng chờ reconnect để ứng dụng không im lặng quá lâu sau khi mạng phục hồi.
  static const int _websocketReconnectMaxSeconds = int.fromEnvironment(
    'WS_RECONNECT_MAX_SECONDS',
    defaultValue: 30,
  );

  /// Chu kỳ gửi PING nhằm giữ kết nối qua proxy và phát hiện phiên xác thực bị thu hồi.
  static const int _websocketHeartbeatSeconds = int.fromEnvironment(
    'WS_HEARTBEAT_SECONDS',
    defaultValue: 25,
  );

  /// URL REST đã bỏ dấu `/` cuối và xác minh chỉ dùng HTTP/HTTPS.
  static String get apiBaseUrl => _normalizeAbsoluteUrl(
    _apiBaseUrl,
    'API_BASE_URL',
    allowedSchemes: const {'http', 'https'},
  );

  /// URL gốc WebSocket; tự suy ra từ API khi WS_BASE_URL không được khai báo.
  static String get wsBaseUrl {
    // Ưu tiên WS_BASE_URL riêng; nếu không có thì lấy origin REST để Cloudflare hoặc
    // domain production chỉ cần đổi một biến API_BASE_URL.
    final configured = _wsBaseUrl.trim();
    // WS_BASE_URL khác rỗng tách riêng hạ tầng realtime khỏi REST khi cần.
    if (configured.isNotEmpty) {
      return _normalizeAbsoluteUrl(
        configured,
        'WS_BASE_URL',
        allowedSchemes: const {'ws', 'wss'},
      );
    }

    final origin = Uri.parse(apiOrigin);
    // HTTPS bắt buộc đi với WSS để trình duyệt không chặn mixed content;
    // HTTP phát triển cục bộ tương ứng với WS.
    final websocketScheme = origin.scheme == 'https' ? 'wss' : 'ws';
    return _withoutTrailingSlash(
      origin.replace(scheme: websocketScheme).toString(),
    );
  }

  /// Đường dẫn WebSocket đã chuẩn hóa luôn bắt đầu bằng `/`.
  static String get wsPath => _normalizePath(_wsPath, 'WS_PATH');

  /// Timeout kết nối HTTP dạng giây sau khi kiểm tra giá trị dương.
  static int get connectTimeoutSeconds {
    // Kiểm tra tại getter để dart-define sai dừng ngay khi client được khởi tạo.
    if (_connectTimeoutSeconds < 1) {
      throw StateError('CONNECT_TIMEOUT_SECONDS phải lớn hơn 0');
    }
    return _connectTimeoutSeconds;
  }

  /// Số lần thử thêm sau request GET đầu tiên; giới hạn tối đa để tránh giữ request quá lâu.
  static int get httpGetRetryCount {
    // 0 tắt retry; trần 5 ngăn một request giữ giao diện quá lâu khi server lỗi.
    if (_httpGetRetryCount < 0 || _httpGetRetryCount > 5) {
      throw StateError('HTTP_GET_RETRY_COUNT phải nằm trong khoảng từ 0 đến 5');
    }
    return _httpGetRetryCount;
  }

  /// Chuyển độ trễ millisecond từ cấu hình sang Duration cho ApiClient.
  static Duration get httpRetryDelay {
    // 0 cho phép retry ngay; số âm không có ý nghĩa thời gian và bị từ chối.
    if (_httpRetryDelayMilliseconds < 0) {
      throw StateError('HTTP_RETRY_DELAY_MS không được nhỏ hơn 0');
    }
    return Duration(milliseconds: _httpRetryDelayMilliseconds);
  }

  /// Biên dưới backoff reconnect ở dạng Duration.
  static Duration get websocketReconnectMinDelay {
    _validateWebsocketDurations();
    return Duration(seconds: _websocketReconnectMinSeconds);
  }

  /// Biên trên backoff reconnect ở dạng Duration.
  static Duration get websocketReconnectMaxDelay {
    _validateWebsocketDurations();
    return Duration(seconds: _websocketReconnectMaxSeconds);
  }

  /// Chu kỳ heartbeat đã xác minh luôn lớn hơn 0.
  static Duration get websocketHeartbeatInterval {
    if (_websocketHeartbeatSeconds < 1) {
      throw StateError('WS_HEARTBEAT_SECONDS phải lớn hơn 0');
    }
    return Duration(seconds: _websocketHeartbeatSeconds);
  }

  /// Dạng Uri dùng để tách origin và path mà không nối chuỗi thủ công.
  static Uri get apiBaseUri => Uri.parse(apiBaseUrl);

  /// Scheme + host + port của backend, không gồm `/api/v1`.
  static String get apiOrigin {
    // Xóa path/query/fragment nhưng giữ scheme, host và port để suy ra kênh realtime.
    final uri = apiBaseUri;
    return _withoutTrailingSlash(
      uri.replace(path: '', query: null, fragment: null).toString(),
    );
  }

  /// Phần path phiên bản API, thường là `/api/v1`.
  static String get apiPathPrefix {
    final path = apiBaseUri.path;
    // Origin không có path hoặc chỉ `/` nghĩa backend không dùng prefix phiên bản.
    if (path.isEmpty || path == '/') return '';
    return _withoutTrailingSlash(path);
  }

  /// URI WebSocket hoàn chỉnh sau khi ghép host và WS_PATH.
  static Uri get websocketUri {
    // Uri.replace ghép path an toàn, tránh lỗi hai dấu `/` hoặc nối chuỗi sai scheme.
    final base = Uri.parse(wsBaseUrl);
    return base.replace(
      path: _joinPaths(base.path, wsPath),
      query: null,
      fragment: null,
    );
  }

  /// Dạng chuỗi của websocketUri dành cho thư viện cần String.
  static String get websocketUrl => websocketUri.toString();

  static String _normalizeAbsoluteUrl(
    String rawValue,
    String envName, {
    required Set<String> allowedSchemes,
  }) {
    // Không nhận query/fragment vì đây là base URL dùng ghép nhiều endpoint khác nhau.
    // Trim trước rồi bỏ `/` cuối để mọi repository ghép path theo cùng quy ước.
    final value = _withoutTrailingSlash(rawValue.trim());
    // Giá trị rỗng được báo bằng đúng tên biến build để dễ sửa cấu hình.
    if (value.isEmpty) {
      throw StateError('$envName không được để trống');
    }

    final uri = Uri.tryParse(value);
    // Base URL phải có scheme/host, đúng giao thức được phép và không mang trạng
    // thái request như query hoặc fragment.
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        !allowedSchemes.contains(uri.scheme) ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError(
        '$envName phải là URL tuyệt đối sử dụng một trong các giao thức '
        '$allowedSchemes',
      );
    }
    return value;
  }

  static String _normalizePath(String rawValue, String envName) {
    // Path tương đối phải có dấu `/` đầu và không được chứa host/query/fragment.
    final value = rawValue.trim();
    // Path rỗng không thể xác định endpoint WebSocket.
    if (value.isEmpty) {
      throw StateError('$envName không được để trống');
    }
    // Người cấu hình có thể nhập `api/v1/ws`; dấu `/` đầu được bổ sung tự động.
    final normalized = value.startsWith('/') ? value : '/$value';
    // Parse lại sau chuẩn hóa để phát hiện URL tuyệt đối hoặc query bị nhập nhầm.
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.hasScheme ||
        uri.host.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('$envName chỉ được chứa đường dẫn URL');
    }
    return normalized;
  }

  static String _joinPaths(String basePath, String path) {
    // Chuẩn hóa hai phía trước khi nối để giữ đúng prefix khi WS host có base path.
    final left = _withoutTrailingSlash(basePath.trim());
    final right = _normalizePath(path, 'WS_PATH');
    // Host không có base path dùng trực tiếp WS_PATH; không tạo hai dấu `/`.
    if (left.isEmpty || left == '/') return right;
    return '$left$right';
  }

  static String _withoutTrailingSlash(String value) {
    // Xóa mọi dấu `/` cuối nhưng giữ nguyên root `/`.
    var result = value;
    // Dùng vòng lặp để xử lý cả cấu hình có nhiều dấu `/` cuối, không chỉ một dấu.
    while (result.length > 1 && result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static void _validateWebsocketDurations() {
    // Min phải dương và không vượt max để công thức backoff luôn có miền hợp lệ.
    if (_websocketReconnectMinSeconds < 1 ||
        _websocketReconnectMaxSeconds < _websocketReconnectMinSeconds) {
      throw StateError(
        'WS_RECONNECT_MIN_SECONDS phải lớn hơn 0 và không được lớn hơn '
        'WS_RECONNECT_MAX_SECONDS',
      );
    }
  }
}
