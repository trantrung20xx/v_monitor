import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/websocket_client.dart';
import '../../data/models/device_model.dart';
import '../../data/repositories/device_repository.dart';
import 'dashboard_state.dart';

class DashboardCubit extends Cubit<DashboardState> {
  final DeviceRepository _deviceRepo;
  final WebsocketClient _websocketClient;

  DashboardCubit({
    required DeviceRepository deviceRepo,
    required WebsocketClient websocketClient,
  })  : _deviceRepo = deviceRepo,
        _websocketClient = websocketClient,
        super(const DashboardState()) {
    _websocketClient.addListener(_onWebsocketMessage);
  }

  Future<void> loadDashboard() async {
    emit(state.copyWith(isLoading: true));
    try {
      final devices = await _deviceRepo.getDevices();
      _updateDevices(devices);
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void _onWebsocketMessage(Map<String, dynamic> data) {
    if (data['type'] == 'DEVICE_UPDATE') {
      final device = DeviceModel.fromJson(data['device']);
      final updatedDevices = List<DeviceModel>.from(state.devices);
      final index = updatedDevices.indexWhere((d) => d.id == device.id);
      if (index >= 0) {
        updatedDevices[index] = device;
      } else {
        updatedDevices.add(device);
      }
      _updateDevices(updatedDevices);
    }
  }

  void _updateDevices(List<DeviceModel> devices) {
    int online = 0, offline = 0;
    for (final dev in devices) {
      if (dev.isOnline) {
        online++;
      } else {
        offline++;
      }
    }

    emit(state.copyWith(
      isLoading: false,
      devices: devices,
      totalDevices: devices.length,
      onlineCount: online,
      offlineCount: offline,
      movingCount: 0,
      idleCount: 0,
    ));
  }

  @override
  Future<void> close() {
    _websocketClient.removeListener(_onWebsocketMessage);
    return super.close();
  }
}
