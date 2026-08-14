class AppConfig {
  AppConfig._();

  static const String environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );

  static const String _wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://127.0.0.1:8000',
  );

  static const String _wsPath = String.fromEnvironment(
    'WS_PATH',
    defaultValue: '/api/v1/ws',
  );

  static const int _connectTimeoutSeconds = int.fromEnvironment(
    'CONNECT_TIMEOUT_SECONDS',
    defaultValue: 10,
  );

  static const bool enableDevicePreview = bool.fromEnvironment(
    'ENABLE_DEVICE_PREVIEW',
    defaultValue: false,
  );

  static String get apiBaseUrl => _normalizeAbsoluteUrl(
    _apiBaseUrl,
    'API_BASE_URL',
    allowedSchemes: const {'http', 'https'},
  );

  static String get wsBaseUrl => _normalizeAbsoluteUrl(
    _wsBaseUrl,
    'WS_BASE_URL',
    allowedSchemes: const {'ws', 'wss'},
  );

  static String get wsPath => _normalizePath(_wsPath, 'WS_PATH');

  static int get connectTimeoutSeconds {
    if (_connectTimeoutSeconds < 1) {
      throw StateError('CONNECT_TIMEOUT_SECONDS must be greater than 0');
    }
    return _connectTimeoutSeconds;
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
      throw StateError('$envName must not be empty');
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        !allowedSchemes.contains(uri.scheme)) {
      throw StateError(
        '$envName must be an absolute URL using $allowedSchemes',
      );
    }
    return value;
  }

  static String _normalizePath(String rawValue, String envName) {
    final value = rawValue.trim();
    if (value.isEmpty) {
      throw StateError('$envName must not be empty');
    }
    return value.startsWith('/') ? value : '/$value';
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
}
