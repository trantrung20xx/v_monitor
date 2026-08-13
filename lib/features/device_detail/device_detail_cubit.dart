import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geocoding/geocoding.dart';

import '../../data/models/device_model.dart';
import '../../data/models/location_model.dart';
import '../../data/models/device_event_model.dart';
import '../../data/models/assignment_model.dart';
import '../../data/models/usage_session_model.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/tracking_repository.dart';

/// Quản lý trạng thái (State) cho màn hình Chi tiết thiết bị.
class DeviceDetailState extends Equatable {
  const DeviceDetailState({
    this.isLoading = true,
    this.error,
    this.device,
    this.events = const [],
    this.locations = const [],
    this.assignments = const [],
    this.usages = const [],
    this.address,
  });

  final bool isLoading;
  final String? error;
  final DeviceModel? device;
  final List<DeviceEventModel> events;
  final List<LocationModel> locations;
  final List<AssignmentModel> assignments;
  final List<UsageSessionModel> usages;
  final String? address;

  DeviceDetailState copyWith({
    bool? isLoading,
    String? error,
    DeviceModel? device,
    List<DeviceEventModel>? events,
    List<LocationModel>? locations,
    List<AssignmentModel>? assignments,
    List<UsageSessionModel>? usages,
    String? address,
  }) {
    return DeviceDetailState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      device: device ?? this.device,
      events: events ?? this.events,
      locations: locations ?? this.locations,
      assignments: assignments ?? this.assignments,
      usages: usages ?? this.usages,
      address: address ?? this.address,
    );
  }

  @override
  List<Object?> get props => [isLoading, error, device, events, locations, assignments, usages, address];
}

/// Cubit phụ trách xử lý logic lấy thông tin chi tiết, sự kiện và lịch sử vị trí của một thiết bị cụ thể.
class DeviceDetailCubit extends Cubit<DeviceDetailState> {
  final String deviceId;
  final DeviceRepository deviceRepo;
  final TrackingRepository trackingRepo;
  
  StreamSubscription<DeviceModel>? _deviceUpdatesSub;

  DeviceDetailCubit({
    required this.deviceId,
    required this.deviceRepo,
    required this.trackingRepo,
  })  : super(const DeviceDetailState()) {
    load();
    _deviceUpdatesSub = deviceRepo.deviceUpdates
        .where((device) => device.id == deviceId)
        .listen(_onDeviceUpdated);
  }

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final results = await Future.wait([
        deviceRepo.getDevice(deviceId),
        trackingRepo.getEvents(deviceId),
        trackingRepo.getLocationHistory(deviceId),
        deviceRepo.getDeviceAssignments(deviceId),
        deviceRepo.getDeviceUsages(deviceId),
      ]);

      final device = results[0] as DeviceModel?;
      
      emit(state.copyWith(
        isLoading: false,
        device: device,
        events: results[1] as List<DeviceEventModel>,
        locations: results[2] as List<LocationModel>,
        assignments: results[3] as List<AssignmentModel>,
        usages: results[4] as List<UsageSessionModel>,
      ));
      
      if (device != null) {
        _resolveAddress(device.latitude, device.longitude);
      }
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }
  
  void _onDeviceUpdated(DeviceModel updatedDevice) {
    emit(state.copyWith(device: updatedDevice));
    
    // Only resolve address if location changed significantly, or just resolve it
    if (state.device?.latitude != updatedDevice.latitude || 
        state.device?.longitude != updatedDevice.longitude) {
      _resolveAddress(updatedDevice.latitude, updatedDevice.longitude);
    }
  }

  Future<void> _resolveAddress(double? lat, double? lng) async {
    if (lat == null || lng == null) return;
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final rawParts = [
          p.street,
          p.subLocality,
          p.locality,
          p.subAdministrativeArea,
          p.administrativeArea,
          p.country,
        ];
        
        final cleanParts = <String>[];
        for (final part in rawParts) {
          if (part != null && part.isNotEmpty && part != 'Unnamed Road') {
            if (cleanParts.isEmpty || cleanParts.last != part) {
              bool skip = false;
              for (int i = 0; i < cleanParts.length; i++) {
                if (cleanParts[i].contains(part) || part.contains(cleanParts[i])) {
                  if (part.length > cleanParts[i].length) {
                    cleanParts[i] = part; 
                  }
                  skip = true;
                  break;
                }
              }
              if (!skip) cleanParts.add(part);
            }
          }
        }
        final address = cleanParts.join(', ');
        emit(state.copyWith(address: address));
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
