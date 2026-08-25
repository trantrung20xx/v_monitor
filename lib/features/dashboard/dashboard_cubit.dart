// Tổng hợp danh sách thiết bị cho dashboard: tải REST, nhận cập nhật realtime,
// resolve trạng thái, đếm thống kê và tra địa chỉ theo tọa độ mới nhất.
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

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
    // Repository phát DeviceModel đã parse từ DEVICE_UPDATE; thay đổi system settings
    // yêu cầu tính lại trạng thái từ cùng danh sách dù không có telemetry mới.
    _deviceUpdatesSub = deviceRepo.deviceUpdates.listen(_onDeviceUpdated);
    _settingsSub = settingsRepo.systemSettingsChanges.listen((_) {
      // Không emit state rỗng khi dashboard chưa tải lần đầu; danh sách hiện có mới
      // cần resolve lại theo ngưỡng hệ thống vừa thay đổi.
      if (state.devices.isNotEmpty) _updateDevices(state.devices);
    });
  }

  final DeviceRepository deviceRepo;
  final GeocodingRepository geocodingRepo;
  final SettingsRepository settingsRepo;
  // addressCache dùng chung theo tọa độ; deviceAddressKeys ghi tọa độ mới nhất mà mỗi
  // thiết bị đang chờ để response cũ không ghi đè địa chỉ của vị trí mới.
  final Map<String, String> _addressCache = {};
  final Map<String, String> _deviceAddressKeys = {};
  StreamSubscription<DeviceModel>? _deviceUpdatesSub;
  StreamSubscription<SystemSettingsModel>? _settingsSub;

  /// Tải snapshot REST ban đầu; cập nhật sau đó được hợp nhất từ WebSocket.
  Future<void> loadDashboard() async {
    // State loading giữ nguyên dữ liệu cũ để refresh không làm danh sách biến mất đột ngột.
    emit(state.copyWith(isLoading: true, error: null));
    try {
      // Repository parse toàn bộ response `/devices/` thành DeviceModel.
      final devices = await deviceRepo.getDevices();
      _updateDevices(devices);
    } catch (e) {
      // Lỗi được giữ trong state để DashboardPage chọn khối thông báo phù hợp.
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void setSearchQuery(String query) {
    // Query nằm trong state để widget lọc nhất quán, không gọi lại API.
    emit(state.copyWith(searchQuery: query));
  }

  void setStatusFilter(DeviceFilter filter) {
    // Filter chỉ thay cách nhìn; state.devices vẫn giữ nguyên snapshot nguồn.
    emit(state.copyWith(statusFilter: filter));
  }

  void _onDeviceUpdated(DeviceModel device) {
    // Thay đúng phần tử theo database id; thiết bị mới được thêm nếu snapshot chưa có.
    final updatedDevices = List<DeviceModel>.from(state.devices);
    final index = updatedDevices.indexWhere((d) => d.id == device.id);
    // ID đã tồn tại nghĩa đây là snapshot mới của cùng thiết bị.
    if (index >= 0) {
      updatedDevices[index] = device;
    } else {
      // Thiết bị đăng ký sau lần tải đầu được thêm vào dashboard mà không cần refresh.
      updatedDevices.add(device);
    }
    // Tính lại bộ đếm và địa chỉ từ danh sách sau hợp nhất.
    _updateDevices(updatedDevices);
  }

  void _updateDevices(List<DeviceModel> devices) {
    // Mọi bộ đếm dùng chung DeviceStatusResolver để thẻ, bộ lọc và thống kê không
    // tự diễn giải online/moving theo các ngưỡng khác nhau.
    // Tính lại từ đầu để một DEVICE_UPDATE không làm các bộ đếm cộng dồn sai.
    int online = 0,
        offline = 0,
        moving = 0,
        stopped = 0,
        inactive = 0,
        stale = 0,
        attention = 0;

    for (final dev in devices) {
      // Chỉ gọi reverse geocoding khi backend cung cấp đủ hai thành phần GPS thật.
      if (dev.latitude != null && dev.longitude != null) {
        _resolveAddressForDashboard(dev.id, dev.latitude!, dev.longitude!);
      }

      final status = DeviceStatusResolver.resolve(
        isOnline: dev.isOnline,
        lastSeenAt: dev.lastSeenAt,
        latestMeasuredAt: dev.latestMeasuredAt,
        currentSpeedMps: dev.currentSpeedMps,
        baseStatus: dev.status,
      );

      // Connectivity luôn thuộc đúng một trong hai nhóm, vì vậy tổng online+offline
      // phải bằng tổng thiết bị đang hiển thị.
      if (status.connectivity == ConnectivityStatus.online) {
        online++;
      } else {
        offline++;
      }

      // stale là trục độ mới dữ liệu độc lập với online/offline.
      if (status.freshness == DataFreshnessStatus.stale) {
        stale++;
      }

      // Movement unknown không bị tính nhầm vào moving hoặc stopped.
      if (status.movement == MovementStatus.moving) {
        moving++;
      } else if (status.movement == MovementStatus.stopped) {
        stopped++;
      }

      // Activity inactive lấy từ trạng thái quản lý thật, không suy từ mất mạng.
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
    // Làm tròn giống cache backend để dịch chuyển GPS rất nhỏ không gọi geocoding lại.
    final cacheKey = '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    final cached = _addressCache[cacheKey];
    // Trả sớm khi đúng thiết bị, đúng tọa độ và đúng địa chỉ đã nằm trong state.
    if (_deviceAddressKeys[deviceId] == cacheKey &&
        cached != null &&
        state.deviceAddresses[deviceId] == cached) {
      return;
    }

    _deviceAddressKeys[deviceId] = cacheKey;

    // Cache hit chỉ cập nhật map địa chỉ trong state, không gọi HTTP.
    if (cached != null) {
      final newAddresses = Map<String, String>.from(state.deviceAddresses);
      newAddresses[deviceId] = cached;
      emit(state.copyWith(deviceAddresses: newAddresses));
      return;
    }

    if (state.deviceAddresses.containsKey(deviceId)) {
      // Khi thiết bị sang tọa độ chưa có cache, bỏ địa chỉ cũ để UI không gắn nhầm
      // tên đường cũ trong lúc chờ request mới.
      final newAddresses = Map<String, String>.from(state.deviceAddresses)
        ..remove(deviceId);
      emit(state.copyWith(deviceAddresses: newAddresses));
    }

    // Repository trả null khi provider không khả dụng; GPS gốc vẫn được giữ nguyên.
    final address = await geocodingRepo.reverseAddress(lat, lng);
    final normalizedAddress = address?.trim();
    if (normalizedAddress == null || normalizedAddress.isEmpty) {
      return;
    }

    _addressCache[cacheKey] = normalizedAddress;
    // Chỉ áp dụng response nếu thiết bị vẫn đang ở đúng cacheKey đã yêu cầu.
    // isClosed ngăn emit sau khi DashboardCubit đã bị hủy khi chuyển màn hình.
    if (_deviceAddressKeys[deviceId] != cacheKey || isClosed) {
      return;
    }

    final newAddresses = Map<String, String>.from(state.deviceAddresses);
    newAddresses[deviceId] = normalizedAddress;
    emit(state.copyWith(deviceAddresses: newAddresses));
  }

  @override
  Future<void> close() async {
    // Hủy subscription để repository dùng chung không gọi Cubit sau khi rời màn hình.
    await _deviceUpdatesSub?.cancel();
    await _settingsSub?.cancel();
    await super.close();
  }
}
