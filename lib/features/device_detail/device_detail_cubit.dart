import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/device_model.dart';
import '../../data/models/location_model.dart';
import '../../data/models/device_event_model.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/tracking_repository.dart';

/// State for DeviceDetailPage.
class DeviceDetailState extends Equatable {
  const DeviceDetailState({
    this.isLoading = true,
    this.error,
    this.device,
    this.events = const [],
    this.locations = const [],
  });

  final bool isLoading;
  final String? error;
  final DeviceModel? device;
  final List<DeviceEventModel> events;
  final List<LocationModel> locations;

  DeviceDetailState copyWith({
    bool? isLoading,
    String? error,
    DeviceModel? device,
    List<DeviceEventModel>? events,
    List<LocationModel>? locations,
  }) {
    return DeviceDetailState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      device: device ?? this.device,
      events: events ?? this.events,
      locations: locations ?? this.locations,
    );
  }

  @override
  List<Object?> get props => [isLoading, error, device, events, locations];
}

/// Cubit for device detail — loads device info, events, and recent locations.
class DeviceDetailCubit extends Cubit<DeviceDetailState> {
  DeviceDetailCubit({
    required this.deviceId,
    required DeviceRepository deviceRepo,
    required TrackingRepository trackingRepo,
  })  : _deviceRepo = deviceRepo,
        _trackingRepo = trackingRepo,
        super(const DeviceDetailState()) {
    load();
  }

  final String deviceId;
  final DeviceRepository _deviceRepo;
  final TrackingRepository _trackingRepo;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    try {
      final results = await Future.wait([
        _deviceRepo.getDevice(deviceId),
        _trackingRepo.getEvents(deviceId),
        _trackingRepo.getLocationHistory(deviceId),
      ]);

      emit(state.copyWith(
        isLoading: false,
        device: results[0] as DeviceModel?,
        events: results[1] as List<DeviceEventModel>,
        locations: results[2] as List<LocationModel>,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }
  
  void _onDevicesChanged(List<DeviceModel> devices) async {
    try {
      final updatedDevice = devices.firstWhere((d) => d.id == deviceId);
      final locs = await _trackingRepo.getLocationHistory(deviceId);
      emit(state.copyWith(device: updatedDevice, locations: locs));
    } catch (_) {
      // Ignored
    }
  }
  
  @override
  Future<void> close() {
    return super.close();
  }
}
