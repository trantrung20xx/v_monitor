import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/device_event_model.dart';
import '../../data/models/device_model.dart';
import '../../data/models/location_model.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../data/repositories/tracking_repository.dart';

class DeviceDetailState extends Equatable {
  const DeviceDetailState({
    this.isLoading = true,
    this.error,
    this.device,
    this.events = const [],
    this.locations = const [],
    this.address,
  });

  final bool isLoading;
  final String? error;
  final DeviceModel? device;
  final List<DeviceEventModel> events;
  final List<LocationModel> locations;
  final String? address;

  DeviceDetailState copyWith({
    bool? isLoading,
    String? error,
    DeviceModel? device,
    List<DeviceEventModel>? events,
    List<LocationModel>? locations,
    String? address,
    bool clearAddress = false,
  }) {
    return DeviceDetailState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      device: device ?? this.device,
      events: events ?? this.events,
      locations: locations ?? this.locations,
      address: clearAddress ? null : address ?? this.address,
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    error,
    device,
    events,
    locations,
    address,
  ];
}

class DeviceDetailCubit extends Cubit<DeviceDetailState> {
  DeviceDetailCubit({
    required this.deviceId,
    required this.deviceRepo,
    required this.trackingRepo,
    required this.geocodingRepo,
  }) : super(const DeviceDetailState()) {
    load();
    _deviceUpdatesSub = deviceRepo.deviceUpdates
        .where((device) => device.id == deviceId)
        .listen(_onDeviceUpdated);
    _deviceEventsSub = deviceRepo.deviceEvents
        .where((event) => event.deviceId == deviceId)
        .listen(_onDeviceEventReceived);
  }

  final String deviceId;
  final DeviceRepository deviceRepo;
  final TrackingRepository trackingRepo;
  final GeocodingRepository geocodingRepo;

  final Map<String, String> _addressCache = {};
  String? _activeAddressKey;
  StreamSubscription<DeviceModel>? _deviceUpdatesSub;
  StreamSubscription<DeviceEventModel>? _deviceEventsSub;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final results = await Future.wait([
        deviceRepo.getDevice(deviceId),
        trackingRepo.getEvents(deviceId),
        trackingRepo.getLocationHistory(deviceId),
      ]);

      final device = results[0] as DeviceModel?;

      emit(
        state.copyWith(
          isLoading: false,
          device: device,
          events: results[1] as List<DeviceEventModel>,
          locations: results[2] as List<LocationModel>,
          clearAddress: true,
        ),
      );

      if (device != null) {
        _resolveAddress(device.latitude, device.longitude);
      }
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void _onDeviceUpdated(DeviceModel updatedDevice) {
    final previousKey = _coordinateKey(
      state.device?.latitude,
      state.device?.longitude,
    );
    final nextKey = _coordinateKey(
      updatedDevice.latitude,
      updatedDevice.longitude,
    );

    emit(
      state.copyWith(
        device: updatedDevice,
        clearAddress: previousKey != nextKey,
      ),
    );

    if (previousKey != nextKey) {
      _resolveAddress(updatedDevice.latitude, updatedDevice.longitude);
    }
  }

  void _onDeviceEventReceived(DeviceEventModel newEvent) {
    // Chèn sự kiện mới lên đầu danh sách (mới nhất xếp trước)
    final updatedEvents = [newEvent, ...state.events];
    emit(state.copyWith(events: updatedEvents));
  }

  Future<void> _resolveAddress(double? lat, double? lng) async {
    final cacheKey = _coordinateKey(lat, lng);
    if (cacheKey == null || lat == null || lng == null) {
      _activeAddressKey = null;
      emit(state.copyWith(clearAddress: true));
      return;
    }

    if (_activeAddressKey == cacheKey && state.address?.isNotEmpty == true) {
      return;
    }

    _activeAddressKey = cacheKey;
    final cached = _addressCache[cacheKey];
    if (cached != null) {
      emit(state.copyWith(address: cached));
      return;
    }

    final address = await geocodingRepo.reverseAddress(lat, lng);
    final normalizedAddress = address?.trim();
    if (normalizedAddress == null || normalizedAddress.isEmpty) {
      return;
    }

    _addressCache[cacheKey] = normalizedAddress;
    if (_activeAddressKey != cacheKey || isClosed) {
      return;
    }

    emit(state.copyWith(address: normalizedAddress));
  }

  String? _coordinateKey(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    return '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
  }

  @override
  Future<void> close() {
    _deviceUpdatesSub?.cancel();
    _deviceEventsSub?.cancel();
    return super.close();
  }
}
