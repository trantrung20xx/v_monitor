// Xác nhận DEVICE_DELETED loại đúng thiết bị khỏi dashboard/bản đồ và bỏ qua frame lỗi.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';
import 'package:v_monitor/data/repositories/device_repository.dart';
import 'package:v_monitor/data/repositories/geocoding_repository.dart';
import 'package:v_monitor/data/repositories/settings_repository.dart';
import 'package:v_monitor/features/dashboard/dashboard_cubit.dart';

void main() {
  test(
    'committed device deletion is removed from the live dashboard',
    () async {
      final api = _DeviceListApiClient();
      final deviceWebsocket = _FakeWebsocketClient();
      final settingsWebsocket = _FakeWebsocketClient();
      final deviceRepository = DeviceRepository(api, deviceWebsocket);
      final settingsRepository = SettingsRepository(
        ApiClient(),
        settingsWebsocket,
      );
      final cubit = DashboardCubit(
        deviceRepo: deviceRepository,
        geocodingRepo: GeocodingRepository(ApiClient()),
        settingsRepo: settingsRepository,
      );
      addTearDown(cubit.close);
      addTearDown(settingsRepository.dispose);
      addTearDown(deviceWebsocket.dispose);
      addTearDown(settingsWebsocket.dispose);

      await cubit.loadDashboard();
      expect(cubit.state.totalDevices, 2);

      deviceWebsocket.add({'type': 'DEVICE_DELETED', 'device_id': ''});
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.totalDevices, 2);

      deviceWebsocket.add({
        'type': 'DEVICE_DELETED',
        'device_id': 'device-1',
        'device_code': 'CAR-01',
      });
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.totalDevices, 1);
      expect(cubit.state.devices.single.id, 'device-2');
    },
  );
}

class _DeviceListApiClient extends ApiClient {
  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: const [
        {
          'id': 'device-1',
          'device_code': 'CAR-01',
          'name': 'Xe 01',
          'device_type': 'VEHICLE',
          'status': 'OFFLINE',
          'is_enabled': true,
        },
        {
          'id': 'device-2',
          'device_code': 'CAR-02',
          'name': 'Xe 02',
          'device_type': 'VEHICLE',
          'status': 'OFFLINE',
          'is_enabled': true,
        },
      ],
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
