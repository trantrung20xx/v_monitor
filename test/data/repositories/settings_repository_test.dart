// Xác nhận repository phát đúng settings từ REST/WebSocket và xóa runtime khi đăng xuất.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';
import 'package:v_monitor/data/models/user_settings_model.dart';
import 'package:v_monitor/data/repositories/settings_repository.dart';

void main() {
  test(
    'repository uses Settings API contracts and parses persisted values',
    () async {
      final api = _FakeApiClient();
      final websocket = _FakeWebsocketClient();
      final repository = SettingsRepository(api, websocket);
      addTearDown(repository.dispose);
      addTearDown(websocket.dispose);

      final personal = await repository.loadUserSettings();
      final system = await repository.loadSystemSettings();
      final updatedPersonal = await repository.updateUserSettings({
        'preferences': {'journey_node_label_mode': 'date_time_only'},
      });
      await repository.updateSystemSettings({'offline_timeout_seconds': 600});

      expect(personal.theme, 'dark');
      expect(personal.preferences['existing_key'], 'keep');
      expect(
        personal.journeyNodeLabelMode,
        JourneyNodeLabelMode.dateTimeAndAddress,
      );
      expect(
        updatedPersonal.journeyNodeLabelMode,
        JourneyNodeLabelMode.dateTimeOnly,
      );
      expect(system.movementThresholdMps, 0.5);
      expect(api.calls, [
        'GET /auth/settings',
        'GET /system/settings',
        'PATCH /auth/settings',
        'PATCH /system/settings',
      ]);
    },
  );

  test(
    'SYSTEM_SETTINGS_UPDATED applies immediately and leaves old events alone',
    () async {
      final api = _FakeApiClient();
      final websocket = _FakeWebsocketClient();
      final repository = SettingsRepository(api, websocket);
      addTearDown(repository.dispose);
      addTearDown(websocket.dispose);
      final received = <double>[];
      final subscription = repository.systemSettingsChanges.listen(
        (value) => received.add(value.movementThresholdMps),
      );
      addTearDown(subscription.cancel);

      websocket.add({
        'type': 'DEVICE_UPDATE',
        'device': {'id': 'device-1'},
      });
      websocket.add({
        'type': 'SYSTEM_SETTINGS_UPDATED',
        'settings': {
          'offline_timeout_seconds': 600,
          'movement_threshold_mps': 1.2,
          'default_gap_threshold_seconds': 420,
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(received, [1.2]);
      expect(repository.systemSettings.offlineTimeoutSeconds, 600);
      expect(repository.systemSettings.defaultGapThresholdSeconds, 420);
    },
  );
}

class _FakeApiClient extends ApiClient {
  final calls = <String>[];

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add('GET $path');
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: path == '/auth/settings'
          ? const {
              'theme': 'dark',
              'language': 'vi',
              'timezone': 'Asia/Ho_Chi_Minh',
              'notifications_enabled': true,
              'preferences': {
                'map_type': 'street',
                'speed_unit': 'kmh',
                'existing_key': 'keep',
              },
            }
          : const {
              'offline_timeout_seconds': 300,
              'movement_threshold_mps': 0.5,
              'default_gap_threshold_seconds': 300,
            },
    );
  }

  @override
  Future<Response> patch(String path, {dynamic data}) async {
    calls.add('PATCH $path');
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: path == '/auth/settings'
          ? const {
              'theme': 'dark',
              'language': 'vi',
              'timezone': 'Asia/Ho_Chi_Minh',
              'notifications_enabled': true,
              'preferences': {
                'map_type': 'satellite',
                'speed_unit': 'kmh',
                'journey_node_label_mode': 'date_time_only',
                'existing_key': 'keep',
              },
            }
          : const {
              'offline_timeout_seconds': 600,
              'movement_threshold_mps': 0.5,
              'default_gap_threshold_seconds': 300,
            },
    );
  }
}

class _FakeWebsocketClient extends WebsocketClient {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  void add(Map<String, dynamic> message) => _controller.add(message);

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }
}
