import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/core/config/app_config.dart';

void main() {
  test('loads the selected build-time environment', () {
    final expected = _expectedConfig(AppConfig.environment);

    expect(AppConfig.apiBaseUrl, expected.apiBaseUrl);
    expect(AppConfig.wsBaseUrl, expected.wsBaseUrl);
    expect(AppConfig.wsPath, expected.wsPath);
    expect(AppConfig.websocketUrl, expected.websocketUrl);
    expect(AppConfig.connectTimeoutSeconds, expected.timeoutSeconds);
    expect(AppConfig.httpGetRetryCount, inInclusiveRange(0, 5));
    expect(AppConfig.httpRetryDelay, greaterThanOrEqualTo(Duration.zero));
    expect(
      AppConfig.websocketReconnectMaxDelay,
      greaterThanOrEqualTo(AppConfig.websocketReconnectMinDelay),
    );
    expect(AppConfig.websocketHeartbeatInterval, greaterThan(Duration.zero));
  });
}

_ExpectedConfig _expectedConfig(String environment) {
  switch (environment) {
    case 'cloudflare':
      return const _ExpectedConfig(
        apiBaseUrl: 'https://example.trycloudflare.com/api/v1',
        wsBaseUrl: 'wss://example.trycloudflare.com',
        wsPath: '/api/v1/ws',
        timeoutSeconds: 15,
      );
    case 'production':
      return const _ExpectedConfig(
        apiBaseUrl: 'https://api.example.com/api/v1',
        wsBaseUrl: 'wss://api.example.com',
        wsPath: '/api/v1/ws',
        timeoutSeconds: 15,
      );
    case 'development':
    default:
      return const _ExpectedConfig(
        apiBaseUrl: 'http://127.0.0.1:8000/api/v1',
        wsBaseUrl: 'ws://127.0.0.1:8000',
        wsPath: '/api/v1/ws',
        timeoutSeconds: 10,
      );
  }
}

class _ExpectedConfig {
  const _ExpectedConfig({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.wsPath,
    required this.timeoutSeconds,
  });

  final String apiBaseUrl;
  final String wsBaseUrl;
  final String wsPath;
  final int timeoutSeconds;

  String get websocketUrl => '$wsBaseUrl$wsPath';
}
