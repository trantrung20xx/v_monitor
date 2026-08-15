import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/device_model.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../domain/entities/device_query_filter.dart';
import '../../domain/entities/device_status_resolver.dart';
import 'dashboard_state.dart';

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({required this.deviceRepo, required this.geocodingRepo})
    : super(const DashboardState()) {
    _deviceUpdatesSub = deviceRepo.deviceUpdates.listen(_onDeviceUpdated);
  }

  final DeviceRepository deviceRepo;
  final GeocodingRepository geocodingRepo;
  final Map<String, String> _addressCache = {};
  final Map<String, String> _deviceAddressKeys = {};
  StreamSubscription<DeviceModel>? _deviceUpdatesSub;

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

  void setStatusFilter(DeviceFilter filter) {
    emit(state.copyWith(statusFilter: filter));
  }

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

  void _updateDevices(List<DeviceModel> devices) {
    int online = 0,
        offline = 0,
        moving = 0,
        stopped = 0,
        inactive = 0,
        stale = 0,
        attention = 0;

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
      } else {
        offline++;
      }

      if (status.freshness == DataFreshnessStatus.stale) {
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

    emit(
      state.copyWith(
        isLoading: false,
        devices: devices,
        totalDevices: devices.length,
        onlineCount: online,
        offlineCount: offline,
        movingCount: moving,
        stoppedCount: stopped,
        inactiveCount: inactive,
        staleCount: stale,
        attentionCount: attention,
      ),
    );
  }

  Future<void> _resolveAddressForDashboard(
    String deviceId,
    double lat,
    double lng,
  ) async {
    final cacheKey = '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    final cached = _addressCache[cacheKey];
    if (_deviceAddressKeys[deviceId] == cacheKey &&
        cached != null &&
        state.deviceAddresses[deviceId] == cached) {
      return;
    }

    _deviceAddressKeys[deviceId] = cacheKey;

    if (cached != null) {
      final newAddresses = Map<String, String>.from(state.deviceAddresses);
      newAddresses[deviceId] = cached;
      emit(state.copyWith(deviceAddresses: newAddresses));
      return;
    }

    if (state.deviceAddresses.containsKey(deviceId)) {
      final newAddresses = Map<String, String>.from(state.deviceAddresses)
        ..remove(deviceId);
      emit(state.copyWith(deviceAddresses: newAddresses));
    }

    final address = await geocodingRepo.reverseAddress(lat, lng);
    final normalizedAddress = address?.trim();
    if (normalizedAddress == null || normalizedAddress.isEmpty) {
      return;
    }

    _addressCache[cacheKey] = normalizedAddress;
    if (_deviceAddressKeys[deviceId] != cacheKey || isClosed) {
      return;
    }

    final newAddresses = Map<String, String>.from(state.deviceAddresses);
    newAddresses[deviceId] = normalizedAddress;
    emit(state.copyWith(deviceAddresses: newAddresses));
  }

  @override
  Future<void> close() {
    _deviceUpdatesSub?.cancel();
    return super.close();
  }
}
