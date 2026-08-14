import 'dart:async';

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
}

class _FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  final _incoming = StreamController<dynamic>();
  final _sink = _FakeWebSocketSink();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();

  List<String> get sentMessages => _sink.sentMessages;

  void closeFromServer() {
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
