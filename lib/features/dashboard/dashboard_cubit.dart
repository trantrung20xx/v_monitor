// Gom thay đổi theo ID; chỉ lấy địa chỉ cho các thẻ đang hiển thị.
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/config/app_config.dart';
import '../../data/models/device_model.dart';
import '../../data/models/system_settings_model.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/device_query_filter.dart';
import '../../domain/entities/device_status_resolver.dart';
import 'dashboard_state.dart';

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({
    required this.deviceRepo,
    required this.geocodingRepo,
    required this.settingsRepo,
  }) : super(const DashboardState()) {
    _deviceUpdatesSub = deviceRepo.deviceUpdates.listen(_onDeviceUpdated);
    _deviceDeletionsSub = deviceRepo.deviceDeletions.listen(_onDeviceDeleted);
    _resyncSub = deviceRepo.resyncRequests.listen((_) {
      _needsResync = true;
      unawaited(loadDashboard(background: true));
    });
    _settingsSub = settingsRepo.systemSettingsChanges.listen((_) {
      if (_closing || isClosed) return;
      _flushTimer?.cancel();
      _flushTimer = null;
      _refreshStatuses();
      _scheduleFlush();
    });
    _statusTimer = Timer.periodic(
      Duration(seconds: AppConfig.dashboardStatusRefreshSeconds.clamp(1, 60)),
      (_) {
        if (_closing || isClosed) return;
        if (_needsResync) unawaited(loadDashboard(background: true));
        _refreshStatuses();
        _flushUpdates();
      },
    );
  }

  final DeviceRepository deviceRepo;
  final GeocodingRepository geocodingRepo;
  final SettingsRepository settingsRepo;
  final Map<String, DeviceModel> _devices = {};
  final Map<String, DeviceModel> _pending = {};
  final Map<String, DeviceModel?> _duringLoad = {};
  final Set<String> _deleted = {};
  final Map<String, ResolvedDeviceStatus> _statuses = {};
  final List<int> _counts = List.filled(6, 0);
  final Map<String, int> _visible = {};
  final Map<String, String> _addressKeys = {};
  final Map<String, DateTime> _addressRequestedAt = {};
  final Set<String> _addressInFlight = {};
  final Map<String, String> _pendingAddresses = {};
  StreamSubscription<DeviceModel>? _deviceUpdatesSub;
  StreamSubscription<String>? _deviceDeletionsSub;
  StreamSubscription<SystemSettingsModel>? _settingsSub;
  StreamSubscription<void>? _resyncSub;
  Timer? _flushTimer;
  Timer? _statusTimer;
  Future<void>? _loadFuture;
  bool _closing = false;
  bool _needsResync = false;

  Future<void> loadDashboard({bool background = false}) {
    return _loadFuture ??= _load(
      background,
    ).whenComplete(() => _loadFuture = null);
  }

  Future<void> _load(bool background) async {
    _duringLoad.clear();
    if (!background) emit(state.copyWith(isLoading: true, error: null));
    try {
      final snapshot = await deviceRepo.getDevices();
      if (isClosed) return;
      final merged = {for (final device in snapshot) device.id: device};
      for (final entry in _duringLoad.entries) {
        if (entry.value == null) {
          merged.remove(entry.key);
        } else {
          merged[entry.key] = entry.value!;
        }
      }
      _devices
        ..clear()
        ..addAll(merged);
      _pending.clear();
      _deleted.clear();
      _needsResync = false;
      _addressKeys.removeWhere((id, _) => !_devices.containsKey(id));
      _addressRequestedAt.removeWhere((id, _) => !_devices.containsKey(id));
      _refreshStatuses();
      final addresses = Map<String, String>.from(state.deviceAddresses)
        ..removeWhere((id, _) => !_devices.containsKey(id));
      _emitSnapshot(addresses: addresses);
      _resolveVisibleAddresses();
    } catch (error) {
      _needsResync = true;
      if (!isClosed) {
        emit(state.copyWith(isLoading: false, error: error.toString()));
      }
    } finally {
      _duringLoad.clear();
    }
  }

  void setSearchQuery(String query) => emit(state.copyWith(searchQuery: query));
  void setStatusFilter(DeviceFilter filter) =>
      emit(state.copyWith(statusFilter: filter));

  void _onDeviceUpdated(DeviceModel device) {
    if (isClosed || device.id.isEmpty || _deleted.contains(device.id)) return;
    _pending[device.id] = device;
    if (_loadFuture != null) _duringLoad[device.id] = device;
    _scheduleFlush();
  }

  void _onDeviceDeleted(String id) {
    if (isClosed) return;
    _deleted.add(id);
    _pending.remove(id);
    if (_loadFuture != null) _duringLoad[id] = null;
    final previous = _statuses.remove(id);
    if (previous != null) _count(previous, -1);
    _devices.remove(id);
    _addressKeys.remove(id);
    _addressRequestedAt.remove(id);
    _pendingAddresses.remove(id);
    final addresses = Map<String, String>.from(state.deviceAddresses)
      ..remove(id);
    _emitSnapshot(addresses: addresses);
  }

  void _scheduleFlush() {
    if (_closing || isClosed || (_flushTimer?.isActive ?? false)) return;
    _flushTimer = Timer(
      Duration(
        milliseconds: settingsRepo.systemSettings.dashboardUpdateIntervalMs
            .clamp(250, 1000),
      ),
      _flushUpdates,
    );
  }

  ResolvedDeviceStatus _resolve(DeviceModel device) =>
      DeviceStatusResolver.resolve(
        isOnline: device.isOnline,
        lastSeenAt: device.lastSeenAt,
        latestMeasuredAt: device.latestMeasuredAt,
        currentSpeedMps: device.currentSpeedMps,
        baseStatus: device.status,
        thresholds: DeviceStateThresholds(
          onlineTimeout: Duration(
            seconds: settingsRepo.systemSettings.offlineTimeoutSeconds,
          ),
          movementSpeedThresholdMps:
              settingsRepo.systemSettings.movementThresholdMps,
        ),
      );

  void _count(ResolvedDeviceStatus status, int delta) {
    _counts[status.connectivity == ConnectivityStatus.online ? 0 : 1] += delta;
    if (status.movement == MovementStatus.moving) _counts[2] += delta;
    if (status.movement == MovementStatus.stopped) _counts[3] += delta;
    if (status.activity == ActivityStatus.inactive) _counts[4] += delta;
    if (status.freshness == DataFreshnessStatus.stale) _counts[5] += delta;
  }

  void _refreshStatuses() {
    _counts.fillRange(0, _counts.length, 0);
    _statuses.clear();
    for (final device in _devices.values) {
      final status = _resolve(device);
      _statuses[device.id] = status;
      _count(status, 1);
    }
  }

  void _flushUpdates() {
    if (isClosed) return;
    _flushTimer?.cancel();
    _flushTimer = null;
    for (final device in _pending.values) {
      final old = _statuses[device.id];
      if (old != null) _count(old, -1);
      _devices[device.id] = device;
      final status = _resolve(device);
      _statuses[device.id] = status;
      _count(status, 1);
    }
    _pending.clear();
    final addresses = Map<String, String>.from(state.deviceAddresses);
    for (final entry in _pendingAddresses.entries) {
      if (_devices.containsKey(entry.key)) addresses[entry.key] = entry.value;
    }
    _pendingAddresses.clear();
    _emitSnapshot(addresses: addresses);
    _resolveVisibleAddresses();
  }

  void _emitSnapshot({Map<String, String>? addresses}) {
    if (isClosed) return;
    emit(
      state.copyWith(
        isLoading: false,
        devices: List<DeviceModel>.unmodifiable(_devices.values),
        totalDevices: _devices.length,
        onlineCount: _counts[0],
        offlineCount: _counts[1],
        movingCount: _counts[2],
        stoppedCount: _counts[3],
        inactiveCount: _counts[4],
        staleCount: _counts[5],
        deviceAddresses: addresses ?? state.deviceAddresses,
      ),
    );
  }

  void setDeviceVisible(String id, bool visible) {
    if (isClosed) return;
    final count = (_visible[id] ?? 0) + (visible ? 1 : -1);
    if (count <= 0) {
      _visible.remove(id);
    } else {
      _visible[id] = count;
      final device = _devices[id];
      if (device != null) unawaited(_resolveAddress(device));
    }
  }

  void _resolveVisibleAddresses() {
    for (final id in _visible.keys) {
      final device = _devices[id];
      if (device != null) unawaited(_resolveAddress(device));
    }
  }

  String _coordinateKey(DeviceModel device) =>
      '${device.latitude!.toStringAsFixed(5)},${device.longitude!.toStringAsFixed(5)}';

  Future<void> _resolveAddress(DeviceModel device) async {
    if (device.latitude == null ||
        device.longitude == null ||
        _addressInFlight.contains(device.id)) {
      return;
    }
    final key = _coordinateKey(device);
    if (_addressKeys[device.id] == key &&
        state.deviceAddresses.containsKey(device.id)) {
      return;
    }
    final last = _addressRequestedAt[device.id];
    if (last != null &&
        DateTime.now().difference(last).inSeconds <
            AppConfig.geocodingRefreshSeconds.clamp(1, 3600)) {
      return;
    }
    _addressRequestedAt[device.id] = DateTime.now();
    _addressInFlight.add(device.id);
    try {
      final address = (await geocodingRepo.reverseAddress(
        device.latitude!,
        device.longitude!,
      ))?.trim();
      if (isClosed ||
          address == null ||
          address.isEmpty ||
          !_visible.containsKey(device.id)) {
        return;
      }
      final current = _devices[device.id];
      if (current == null ||
          current.latitude == null ||
          current.longitude == null ||
          _coordinateKey(current) != key) {
        return;
      }
      _addressKeys[device.id] = key;
      _pendingAddresses[device.id] = address;
      _scheduleFlush();
    } finally {
      _addressInFlight.remove(device.id);
    }
  }

  @override
  Future<void> close() async {
    _closing = true;
    _flushTimer?.cancel();
    _statusTimer?.cancel();
    await _deviceUpdatesSub?.cancel();
    await _deviceDeletionsSub?.cancel();
    await _settingsSub?.cancel();
    await _resyncSub?.cancel();
    return super.close();
  }
}
