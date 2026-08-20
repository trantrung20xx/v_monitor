import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/device_event_model.dart';
import '../../data/models/device_model.dart';
import '../../data/models/location_model.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../data/repositories/tracking_repository.dart';

enum OverviewTimeRange {
  today('Hôm nay'),
  yesterday('Hôm qua'),
  last24h('24h qua'),
  last7d('7 ngày'),
  custom('Tùy chọn');

  const OverviewTimeRange(this.label);
  final String label;
}

class DeviceDetailState extends Equatable {
  const DeviceDetailState({
    this.isLoading = true,
    this.isRangeLoading = false,
    this.timeRange = OverviewTimeRange.today,
    this.rangeFrom,
    this.rangeTo,
    this.error,
    this.device,
    this.events = const [],
    this.locations = const [],
    this.address,
  });

  final bool isLoading;
  final bool isRangeLoading;
  final OverviewTimeRange timeRange;
  final DateTime? rangeFrom;
  final DateTime? rangeTo;
  final String? error;
  final DeviceModel? device;
  final List<DeviceEventModel> events;
  final List<LocationModel> locations;
  final String? address;

  DeviceDetailState copyWith({
    bool? isLoading,
    bool? isRangeLoading,
    OverviewTimeRange? timeRange,
    DateTime? rangeFrom,
    DateTime? rangeTo,
    String? error,
    DeviceModel? device,
    List<DeviceEventModel>? events,
    List<LocationModel>? locations,
    String? address,
    bool clearAddress = false,
  }) {
    return DeviceDetailState(
      isLoading: isLoading ?? this.isLoading,
      isRangeLoading: isRangeLoading ?? this.isRangeLoading,
      timeRange: timeRange ?? this.timeRange,
      rangeFrom: rangeFrom ?? this.rangeFrom,
      rangeTo: rangeTo ?? this.rangeTo,
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
    isRangeLoading,
    timeRange,
    rangeFrom,
    rangeTo,
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

  (DateTime, DateTime) _calculateRange(
    OverviewTimeRange range, {
    DateTime? customFrom,
    DateTime? customTo,
  }) {
    final now = DateTime.now();
    switch (range) {
      case OverviewTimeRange.today:
        final from = DateTime(now.year, now.month, now.day, 0, 0, 0);
        return (from, now);
      case OverviewTimeRange.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        final from = DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
          0,
          0,
          0,
        );
        final to = DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
          23,
          59,
          59,
        );
        return (from, to);
      case OverviewTimeRange.last24h:
        return (now.subtract(const Duration(hours: 24)), now);
      case OverviewTimeRange.last7d:
        return (now.subtract(const Duration(days: 7)), now);
      case OverviewTimeRange.custom:
        final from =
            customFrom ?? DateTime(now.year, now.month, now.day, 0, 0, 0);
        final to = customTo ?? now;
        return (from, to);
    }
  }

  Future<List<LocationModel>> _fetchLocationsForRange(
    DateTime from,
    DateTime to,
  ) async {
    try {
      final response = await trackingRepo.getLocationHistoryRange(
        deviceId,
        from: from,
        to: to,
      );
      if (response != null) {
        return response.samples;
      }
    } catch (_) {
      // Fallback nếu endpoint range không khả dụng
    }

    try {
      final history = await trackingRepo.getLocationHistory(deviceId);
      return history.where((loc) {
        return !loc.measuredAt.isBefore(from) && !loc.measuredAt.isAfter(to);
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final (from, to) = _calculateRange(
        state.timeRange,
        customFrom: state.rangeFrom,
        customTo: state.rangeTo,
      );

      final results = await Future.wait([
        deviceRepo.getDevice(deviceId),
        trackingRepo.getEvents(deviceId),
        _fetchLocationsForRange(from, to),
      ]);

      final device = results[0] as DeviceModel?;

      emit(
        state.copyWith(
          isLoading: false,
          device: device,
          events: results[1] as List<DeviceEventModel>,
          locations: results[2] as List<LocationModel>,
          rangeFrom: from,
          rangeTo: to,
          clearAddress: device?.latitude == null || device?.longitude == null,
        ),
      );

      if (device != null) {
        _resolveAddress(device.latitude, device.longitude);
      }
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> setTimeRange(
    OverviewTimeRange range, {
    DateTime? customFrom,
    DateTime? customTo,
  }) async {
    final (from, to) = _calculateRange(
      range,
      customFrom: customFrom,
      customTo: customTo,
    );
    emit(
      state.copyWith(
        timeRange: range,
        rangeFrom: from,
        rangeTo: to,
        isRangeLoading: true,
      ),
    );
    try {
      final locations = await _fetchLocationsForRange(from, to);
      emit(
        state.copyWith(
          locations: locations,
          isRangeLoading: false,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isRangeLoading: false));
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
    final hasNewPosition =
        previousKey != nextKey ||
        state.device?.latestMeasuredAt != updatedDevice.latestMeasuredAt;

    List<LocationModel> updatedLocations = state.locations;
    if ((state.timeRange == OverviewTimeRange.today ||
            state.timeRange == OverviewTimeRange.last24h) &&
        updatedDevice.latitude != null &&
        updatedDevice.longitude != null &&
        hasNewPosition) {
      final newLoc = LocationModel(
        id: 'live-${DateTime.now().millisecondsSinceEpoch}',
        deviceId: updatedDevice.id,
        latitude: updatedDevice.latitude!,
        longitude: updatedDevice.longitude!,
        measuredAt:
            updatedDevice.latestMeasuredAt ??
            updatedDevice.lastSeenAt ??
            DateTime.now(),
        altitudeM: updatedDevice.currentAltitudeM,
        speedMps: updatedDevice.currentSpeedMps,
        headingDeg: updatedDevice.currentHeadingDeg,
      );
      updatedLocations = [newLoc, ...state.locations];
    }

    emit(
      state.copyWith(
        device: updatedDevice,
        locations: updatedLocations,
        clearAddress: nextKey == null,
      ),
    );

    if (previousKey != nextKey) {
      _resolveAddress(updatedDevice.latitude, updatedDevice.longitude);
    }
  }

  void _onDeviceEventReceived(DeviceEventModel newEvent) {
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
