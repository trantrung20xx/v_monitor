import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geocoding/geocoding.dart';
import '../../data/models/device_model.dart';
import '../../data/repositories/device_repository.dart';
import '../../domain/entities/device_status_resolver.dart';
import 'dashboard_state.dart';

/// Cubit quản lý trạng thái của màn hình Dashboard.
class DashboardCubit extends Cubit<DashboardState> {
  final DeviceRepository deviceRepo;
  StreamSubscription<DeviceModel>? _deviceUpdatesSub;
  final Map<String, String> _addressCache = {};

  DashboardCubit({
    required this.deviceRepo,
  }) : super(const DashboardState()) {
    _deviceUpdatesSub = deviceRepo.deviceUpdates.listen(_onDeviceUpdated);
  }

  /// Tải danh sách thiết bị ban đầu từ REST API.
  Future<void> loadDashboard() async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final devices = await deviceRepo.getDevices();
      _updateDevices(devices);
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void setSearchQuery(String query) {
    emit(state.copyWith(searchQuery: query));
  }

  /// Xử lý thiết bị cập nhật từ WebSocket Stream
  void _onDeviceUpdated(DeviceModel device) {
    final updatedDevices = List<DeviceModel>.from(state.devices);
    final index = updatedDevices.indexWhere((d) => d.id == device.id);
    if (index >= 0) {
      updatedDevices[index] = device;
    } else {
      updatedDevices.add(device);
    }
    _updateDevices(updatedDevices);
  }

  /// Cập nhật lại danh sách thiết bị và tính toán các chỉ số thống kê
  void _updateDevices(List<DeviceModel> devices) {
    int online = 0, offline = 0, moving = 0, stopped = 0, inactive = 0, stale = 0;

    for (final dev in devices) {
      if (dev.latitude != null && dev.longitude != null) {
        _resolveAddressForDashboard(dev.id, dev.latitude!, dev.longitude!);
      }
      final status = DeviceStatusResolver.resolve(
        isOnline: dev.isOnline,
        lastSeenAt: dev.lastSeenAt,
        currentSpeedMps: dev.currentSpeedMps,
        baseStatus: dev.status,
      );

      if (status.connectivity == ConnectivityStatus.online) {
        online++;
      } else if (status.connectivity == ConnectivityStatus.offline) {
        offline++;
      } else if (status.connectivity == ConnectivityStatus.stale) {
        stale++;
      }

      if (status.movement == MovementStatus.moving) {
        moving++;
      } else if (status.movement == MovementStatus.stopped) {
        stopped++;
      }

      if (status.activity == ActivityStatus.inactive) {
        inactive++;
      }
    }

    emit(state.copyWith(
      isLoading: false,
      devices: devices,
      totalDevices: devices.length,
      onlineCount: online,
      offlineCount: offline,
      movingCount: moving,
      stoppedCount: stopped,
      inactiveCount: inactive,
      staleCount: stale,
    ));
  }

  Future<void> _resolveAddressForDashboard(String deviceId, double lat, double lng) async {
    final cacheKey = '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';
    
    if (state.deviceAddresses[deviceId] == _addressCache[cacheKey] && _addressCache.containsKey(cacheKey)) {
      return;
    }

    if (_addressCache.containsKey(cacheKey)) {
      final newAddresses = Map<String, String>.from(state.deviceAddresses);
      newAddresses[deviceId] = _addressCache[cacheKey]!;
      emit(state.copyWith(deviceAddresses: newAddresses));
      return;
    }

    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          if (p.street != null && p.street!.isNotEmpty) p.street!,
          if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
          if (p.subAdministrativeArea != null && p.subAdministrativeArea!.isNotEmpty) p.subAdministrativeArea!,
          if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) p.administrativeArea!,
        ];
        final address = parts.toSet().join(', ');
        _addressCache[cacheKey] = address;
        
        final newAddresses = Map<String, String>.from(state.deviceAddresses);
        newAddresses[deviceId] = address;
        emit(state.copyWith(deviceAddresses: newAddresses));
      }
    } catch (e) {
      // Ignore geocoding errors silently
    }
  }

  @override
  Future<void> close() {
    _deviceUpdatesSub?.cancel();
    return super.close();
  }
}
