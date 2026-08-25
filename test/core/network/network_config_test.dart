// Xác nhận HTTP/WebSocket dùng cấu hình chung, credential, retry, heartbeat và reconnect đúng hợp đồng.
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/core/config/app_config.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('ApiClient uses AppConfig API base URL', () {
    final client = ApiClient();

    expect(client.baseUrl, AppConfig.apiBaseUrl);
  });

  test(
    'ApiClient attaches the stored credential and reports HTTP 401',
    () async {
      final adapter = _RecordingHttpClientAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://example.test'))
        ..httpClientAdapter = adapter;
      final client = ApiClient(dio: dio);
      var unauthorizedCount = 0;
      client
        ..setAccessToken('persistent-credential')
        ..setUnauthorizedHandler(() async => unauthorizedCount++);

      await client.get('/devices');
      expect(
        adapter.lastOptions?.headers['Authorization'],
        'Bearer persistent-credential',
      );

      adapter.statusCode = 401;
      await expectLater(client.get('/devices'), throwsA(isA<DioException>()));
      await Future<void>.delayed(Duration.zero);
      expect(unauthorizedCount, 1);
    },
  );

  test('ApiClient retries transient GET failures only', () async {
    final adapter = _FlakyHttpClientAdapter(failureCount: 2);
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'))
      ..httpClientAdapter = adapter;
    final client = ApiClient(
      dio: dio,
      getRetryCount: 2,
      retryDelay: Duration.zero,
    );

    final response = await client.get('/devices');

    expect(response.statusCode, 200);
    expect(adapter.requestCount, 3);

    adapter
      ..requestCount = 0
      ..remainingFailures = 1;
    await expectLater(
      client.post('/devices', data: const {}),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requestCount, 1);
  });

  test('WebsocketClient uses AppConfig WebSocket URL', () {
    final client = WebsocketClient();

    expect(client.connectionUri, AppConfig.websocketUri);

    client.dispose();
  });

  test(
    'WebsocketClient retries closed sockets and stops after dispose',
    () async {
      var attempts = 0;
      final client = WebsocketClient(
        connectionUri: Uri.parse('ws://example.test/ws'),
        reconnectDelay: const Duration(milliseconds: 10),
        heartbeatInterval: Duration.zero,
        channelFactory: (_) {
          attempts++;
          final channel = _FakeWebSocketChannel();
          scheduleMicrotask(channel.closeFromServer);
          return channel;
        },
      );

      client.connect();
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(attempts, greaterThan(1));

      client.dispose();
      final attemptsAfterDispose = attempts;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(attempts, attemptsAfterDispose);
    },
  );

  test('WebsocketClient sends heartbeat ping', () async {
    late _FakeWebSocketChannel channel;
    final client = WebsocketClient(
      connectionUri: Uri.parse('ws://example.test/ws'),
      reconnectDelay: const Duration(milliseconds: 10),
      heartbeatInterval: const Duration(milliseconds: 10),
      channelFactory: (_) {
        channel = _FakeWebSocketChannel();
        return channel;
      },
    );

    client.connect();
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(
      channel.sentMessages.any((message) => message.contains('"PING"')),
      isTrue,
    );

    client.dispose();
    channel.closeFromServer();
  });

  test(
    'WebsocketClient keeps control frames out of business messages',
    () async {
      late _FakeWebSocketChannel channel;
      final client = WebsocketClient(
        connectionUri: Uri.parse('ws://example.test/ws'),
        reconnectDelay: const Duration(milliseconds: 10),
        heartbeatInterval: Duration.zero,
        channelFactory: (_) {
          channel = _FakeWebSocketChannel();
          return channel;
        },
      );
      final messages = <Map<String, dynamic>>[];
      final subscription = client.messages.listen(messages.add);

      client.connect();
      channel
        ..receiveFromServer('{"type":"AUTH_OK"}')
        ..receiveFromServer('{"type":"PONG"}')
        ..receiveFromServer(
          '{"type":"DEVICE_UPDATE","device":{"id":"UAV-100"}}',
        );
      await Future<void>.delayed(Duration.zero);

      expect(messages, [
        {
          'type': 'DEVICE_UPDATE',
          'device': {'id': 'UAV-100'},
        },
      ]);

      await subscription.cancel();
      client.dispose();
      channel.closeFromServer();
    },
  );

  for (final closeCode in [4401, 4403]) {
    test(
      'WebsocketClient sends credential and stops after close $closeCode',
      () async {
        late _FakeWebSocketChannel channel;
        late Uri openedUri;
        var attempts = 0;
        var unauthorizedCount = 0;
        final client = WebsocketClient(
          connectionUri: Uri.parse('ws://example.test/ws'),
          reconnectDelay: const Duration(milliseconds: 10),
          heartbeatInterval: Duration.zero,
          channelFactory: (uri) {
            attempts++;
            openedUri = uri;
            channel = _FakeWebSocketChannel();
            return channel;
          },
        );
        client
          ..setAccessToken('persistent-credential')
          ..setUnauthorizedHandler(() async => unauthorizedCount++)
          ..connect();

        expect(openedUri.queryParameters['access_token'], isNull);
        expect(
          channel.sentMessages.any(
            (message) =>
                message.contains('"type":"AUTH"') &&
                message.contains('persistent-credential'),
          ),
          isTrue,
        );
        channel.closeFromServer(closeCode);
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(unauthorizedCount, 1);
        expect(attempts, 1);
        client.dispose();
      },
    );
  }
}

class _RecordingHttpClientAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;
  int statusCode = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString('{}', statusCode);
  }

  @override
  void close({bool force = false}) {}
}

class _FlakyHttpClientAdapter implements HttpClientAdapter {
  _FlakyHttpClientAdapter({required int failureCount})
    : remainingFailures = failureCount;

  int remainingFailures;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    if (remainingFailures > 0) {
      remainingFailures--;
      return ResponseBody.fromString('{}', 503);
    }
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  final _incoming = StreamController<dynamic>();
  final _sink = _FakeWebSocketSink();
  int? _closeCode;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();

  List<String> get sentMessages => _sink.sentMessages;

  void receiveFromServer(String message) {
    _incoming.add(message);
  }

  void closeFromServer([int? closeCode]) {
    _closeCode = closeCode;
    _incoming.close();
  }
}

class _FakeWebSocketSink implements WebSocketSink {
  final List<String> sentMessages = [];
  final _done = Completer<void>();

  @override
  Future<void> get done => _done.future;

  @override
  void add(dynamic event) {
    sentMessages.add(event.toString());
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final event in stream) {
      add(event);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}
