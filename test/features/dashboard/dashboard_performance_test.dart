import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/data/repositories/device_repository.dart';
import 'package:v_monitor/data/repositories/geocoding_repository.dart';
import 'package:v_monitor/data/repositories/settings_repository.dart';
import 'package:v_monitor/features/dashboard/dashboard_cubit.dart';

DeviceModel device(int id, {double speed = 0}) => DeviceModel(
  id: '$id',
  deviceCode: 'GPS-$id',
  name: 'Thiết bị $id',
  type: 'VEHICLE',
  status: 'ACTIVE',
  isOnline: true,
  latitude: 10,
  longitude: 106,
  lastSeenAt: DateTime.now(),
  latestMeasuredAt: DateTime.now(),
  currentSpeedMps: speed,
);

class Devices extends DeviceRepository {
  Devices() : super(ApiClient(), WebsocketClient());
  final updates = StreamController<DeviceModel>.broadcast();
  final reconnects = StreamController<void>.broadcast();
  List<DeviceModel> snapshot = List.generate(5000, device);
  Completer<List<DeviceModel>>? waiting;
  @override
  Stream<DeviceModel> get deviceUpdates => updates.stream;
  @override
  Stream<void> get resyncRequests => reconnects.stream;
  @override
  Future<List<DeviceModel>> getDevices() async => waiting?.future ?? snapshot;
}

class Addresses extends GeocodingRepository {
  Addresses() : super(ApiClient());
  int calls = 0;
  @override
  Future<String?> reverseAddress(double latitude, double longitude) async {
    calls++;
    return 'Địa chỉ thử nghiệm';
  }
}

class SettingsApi extends ApiClient {
  @override
  Future<Response> patch(String path, {dynamic data}) async => Response(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: data,
  );
}

void main() {
  late Devices devices;
  late Addresses addresses;
  late SettingsRepository settings;
  late DashboardCubit cubit;
  void createCubit() {
    devices = Devices();
    addresses = Addresses();
    settings = SettingsRepository(SettingsApi(), WebsocketClient());
    cubit = DashboardCubit(
      deviceRepo: devices,
      geocodingRepo: addresses,
      settingsRepo: settings,
    );
  }

  Future<void> closeCubit() async {
    await cubit.close();
    await settings.dispose();
    await devices.updates.close();
    await devices.reconnects.close();
  }

  test(
    '25000 updates for 5000 devices emit one batch and resolve only visible addresses',
    () async {
      createCubit();
      await cubit.loadDashboard();
      expect(addresses.calls, 0);
      var emissions = 0;
      final sub = cubit.stream.listen((_) => emissions++);
      for (var pass = 0; pass < 5; pass++) {
        for (var id = 0; id < 5000; id++) {
          devices.updates.add(device(id, speed: pass.toDouble()));
        }
      }
      await Future<void>.delayed(Duration.zero);
      expect(emissions, 0);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(emissions, 1);
      expect(cubit.state.devices.length, 5000);
      expect(cubit.state.movingCount, 5000);
      expect(cubit.state.devices.every((d) => d.currentSpeedMps == 4), isTrue);
      expect(addresses.calls, 0);
      cubit.setDeviceVisible('12', true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(addresses.calls, 1);
      expect(cubit.state.deviceAddresses['12'], 'Địa chỉ thử nghiệm');
      await sub.cancel();
      await closeCubit();
    },
  );

  test('admin cadence is applied at runtime', () async {
    createCubit();
    await cubit.loadDashboard();
    await settings.updateSystemSettings({'dashboard_update_interval_ms': 1000});
    devices.updates.add(device(0, speed: 9));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(cubit.state.devices.first.currentSpeedMps, 0);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(cubit.state.devices.first.currentSpeedMps, 9);
    await closeCubit();
  });

  test(
    'reconnect snapshot preserves live changes received while REST is pending',
    () async {
      createCubit();
      await cubit.loadDashboard();
      devices.waiting = Completer<List<DeviceModel>>();
      devices.reconnects.add(null);
      await Future<void>.delayed(Duration.zero);
      devices.updates.add(device(0, speed: 7));
      await Future<void>.delayed(Duration.zero);
      devices.waiting!.complete([device(0), device(1)]);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.devices.length, 2);
      expect(cubit.state.devices.first.currentSpeedMps, 7);
      expect(cubit.state.movingCount, 1);
      await closeCubit();
    },
  );
}
