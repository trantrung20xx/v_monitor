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

  static const String _wsPath = String.fromEnvironment(
    'WS_PATH',
    defaultValue: '/api/v1/ws',
  );

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

  static const int _httpRetryDelayMilliseconds = int.fromEnvironment(
    'HTTP_RETRY_DELAY_MS',
    defaultValue: 400,
  );

  static const int _websocketReconnectMinSeconds = int.fromEnvironment(
    'WS_RECONNECT_MIN_SECONDS',
    defaultValue: 2,
  );

  static const int _websocketReconnectMaxSeconds = int.fromEnvironment(
    'WS_RECONNECT_MAX_SECONDS',
    defaultValue: 30,
  );

  static const int _websocketHeartbeatSeconds = int.fromEnvironment(
    'WS_HEARTBEAT_SECONDS',
    defaultValue: 25,
  );

  static String get apiBaseUrl => _normalizeAbsoluteUrl(
    _apiBaseUrl,
    'API_BASE_URL',
    allowedSchemes: const {'http', 'https'},
  );

  static String get wsBaseUrl {
    final configured = _wsBaseUrl.trim();
    if (configured.isNotEmpty) {
      return _normalizeAbsoluteUrl(
        configured,
        'WS_BASE_URL',
        allowedSchemes: const {'ws', 'wss'},
      );
    }

    final origin = Uri.parse(apiOrigin);
    final websocketScheme = origin.scheme == 'https' ? 'wss' : 'ws';
    return _withoutTrailingSlash(
      origin.replace(scheme: websocketScheme).toString(),
    );
  }

  static String get wsPath => _normalizePath(_wsPath, 'WS_PATH');

  static int get connectTimeoutSeconds {
    if (_connectTimeoutSeconds < 1) {
      throw StateError('CONNECT_TIMEOUT_SECONDS phải lớn hơn 0');
    }
    return _connectTimeoutSeconds;
  }

  static int get httpGetRetryCount {
    if (_httpGetRetryCount < 0 || _httpGetRetryCount > 5) {
      throw StateError('HTTP_GET_RETRY_COUNT phải nằm trong khoảng từ 0 đến 5');
    }
    return _httpGetRetryCount;
  }

  static Duration get httpRetryDelay {
    if (_httpRetryDelayMilliseconds < 0) {
      throw StateError('HTTP_RETRY_DELAY_MS không được nhỏ hơn 0');
    }
    return Duration(milliseconds: _httpRetryDelayMilliseconds);
  }

  static Duration get websocketReconnectMinDelay {
    _validateWebsocketDurations();
    return Duration(seconds: _websocketReconnectMinSeconds);
  }

  static Duration get websocketReconnectMaxDelay {
    _validateWebsocketDurations();
    return Duration(seconds: _websocketReconnectMaxSeconds);
  }

  static Duration get websocketHeartbeatInterval {
    if (_websocketHeartbeatSeconds < 1) {
      throw StateError('WS_HEARTBEAT_SECONDS phải lớn hơn 0');
    }
    return Duration(seconds: _websocketHeartbeatSeconds);
  }

  static Uri get apiBaseUri => Uri.parse(apiBaseUrl);

  static String get apiOrigin {
    final uri = apiBaseUri;
    return _withoutTrailingSlash(
      uri.replace(path: '', query: null, fragment: null).toString(),
    );
  }

  static String get apiPathPrefix {
    final path = apiBaseUri.path;
    if (path.isEmpty || path == '/') return '';
    return _withoutTrailingSlash(path);
  }

  static Uri get websocketUri {
    final base = Uri.parse(wsBaseUrl);
    return base.replace(
      path: _joinPaths(base.path, wsPath),
      query: null,
      fragment: null,
    );
  }

  static String get websocketUrl => websocketUri.toString();

  static String _normalizeAbsoluteUrl(
    String rawValue,
    String envName, {
    required Set<String> allowedSchemes,
  }) {
    final value = _withoutTrailingSlash(rawValue.trim());
    if (value.isEmpty) {
      throw StateError('$envName không được để trống');
    }

    final uri = Uri.tryParse(value);
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
    final value = rawValue.trim();
    if (value.isEmpty) {
      throw StateError('$envName không được để trống');
    }
    final normalized = value.startsWith('/') ? value : '/$value';
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
    final left = _withoutTrailingSlash(basePath.trim());
    final right = _normalizePath(path, 'WS_PATH');
    if (left.isEmpty || left == '/') return right;
    return '$left$right';
  }

  static String _withoutTrailingSlash(String value) {
    var result = value;
    while (result.length > 1 && result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static void _validateWebsocketDurations() {
    if (_websocketReconnectMinSeconds < 1 ||
        _websocketReconnectMaxSeconds < _websocketReconnectMinSeconds) {
      throw StateError(
        'WS_RECONNECT_MIN_SECONDS phải lớn hơn 0 và không được lớn hơn '
        'WS_RECONNECT_MAX_SECONDS',
      );
    }
  }
}
