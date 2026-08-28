// Điều phối toàn bộ cài đặt: tải/lưu tùy chọn cá nhân, ngưỡng hệ thống, tài khoản,
// thiết bị đăng ký và thiết bị MQTT chờ duyệt; quyền ADMIN được backend kiểm tra lại.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/config/map_tile_providers.dart';
import '../../core/utils/device_formatters.dart';
import '../../data/models/device_model.dart';
import '../../data/models/mqtt_device_sighting_model.dart';
import '../../data/models/system_settings_model.dart';
import '../../data/models/user_settings_model.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/device_status_resolver.dart';
import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._repository) : super(const SettingsState()) {
    // Stream repository đưa snapshot đã được server xác nhận vào state và cấu hình
    // các formatter/resolver dùng toàn ứng dụng.
    _userSettingsSubscription = _repository.userSettingsChanges.listen((value) {
      DeviceFormatters.configureSpeedUnit(value.speedUnit);
      emit(state.copyWith(userSettings: value));
    });
    _systemSettingsSubscription = _repository.systemSettingsChanges.listen((
      value,
    ) {
      DeviceStatusResolver.configureRuntime(
        onlineTimeout: Duration(seconds: value.offlineTimeoutSeconds),
        movementSpeedThresholdMps: value.movementThresholdMps,
      );
      emit(state.copyWith(systemSettings: value));
    });
  }

  final SettingsRepository _repository;
  // Hai subscription đưa cấu hình server về các resolver dùng toàn ứng dụng.
  StreamSubscription<UserSettingsModel>? _userSettingsSubscription;
  StreamSubscription<SystemSettingsModel>? _systemSettingsSubscription;
  // Cờ nội bộ ngăn request khởi tạo/làm mới nền trùng nhau; cờ thao tác hiển thị
  // cho UI nằm trong SettingsState.
  bool _initializing = false;
  bool _refreshingDeviceManagement = false;

  Future<void> initialize() async {
    // Guard ngăn nhiều SettingsPage cùng kích hoạt hai chuỗi request khởi tạo.
    if (_initializing) return;
    // Đặt cờ trước emit để callback đồng bộ không thể đi vào lần thứ hai.
    _initializing = true;
    emit(
      state.copyWith(status: SettingsLoadStatus.loading, clearMessage: true),
    );

    final errors = <String>[];
    // Hai nhóm cài đặt được tải độc lập để lỗi một endpoint vẫn giữ được nhóm còn lại.
    try {
      // Repository tự phát snapshot userSettings qua stream subscription ở constructor.
      await _repository.loadUserSettings();
    } catch (error) {
      errors.add(_errorMessage(error, 'Không thể tải cài đặt cá nhân.'));
    }
    try {
      // System settings sau khi tải đồng thời cấu hình DeviceStatusResolver.
      await _repository.loadSystemSettings();
    } catch (error) {
      errors.add(_errorMessage(error, 'Không thể tải cấu hình theo dõi.'));
    }

    // Kết thúc trạng thái khóa trước emit cuối để lần retry kế tiếp được phép chạy.
    _initializing = false;
    // Ghép lỗi của hai nguồn thành một thông báo nhưng vẫn giữ dữ liệu nguồn thành công.
    emit(
      state.copyWith(
        status: errors.isEmpty
            ? SettingsLoadStatus.ready
            : SettingsLoadStatus.error,
        message: errors.isEmpty ? null : errors.join(' '),
        clearMessage: errors.isEmpty,
      ),
    );
  }

  Future<String?> updateTheme(String theme) {
    // UI đổi ngay qua optimistic state; _updatePersonal sẽ rollback nếu server từ chối.
    return _updatePersonal(
      optimistic: state.userSettings.copyWith(theme: theme),
      changes: {'theme': theme},
    );
  }

  Future<String?> updateMapType(AppMapType mapType) {
    final value = mapType == AppMapType.satellite ? 'satellite' : 'street';
    return _updatePersonal(
      optimistic: state.userSettings.copyWith(
        preferences: {...state.userSettings.preferences, 'map_type': value},
      ),
      changes: {
        'preferences': {'map_type': value},
      },
    );
  }

  Future<String?> updateSpeedUnit(SpeedUnit speedUnit) {
    final value = speedUnit == SpeedUnit.mps ? 'mps' : 'kmh';
    return _updatePersonal(
      optimistic: state.userSettings.copyWith(
        preferences: {...state.userSettings.preferences, 'speed_unit': value},
      ),
      changes: {
        'preferences': {'speed_unit': value},
      },
    );
  }

  Future<String?> updateJourneyNodeLabelMode(JourneyNodeLabelMode mode) {
    final value = mode == JourneyNodeLabelMode.dateTimeOnly
        ? 'date_time_only'
        : 'date_time_and_address';
    return _updatePersonal(
      optimistic: state.userSettings.copyWith(
        preferences: {
          ...state.userSettings.preferences,
          'journey_node_label_mode': value,
        },
      ),
      changes: {
        'preferences': {'journey_node_label_mode': value},
      },
    );
  }

  Future<String?> _updatePersonal({
    required UserSettingsModel optimistic,
    required Map<String, dynamic> changes,
  }) async {
    // Chỉ cho phép một PATCH cá nhân tại một thời điểm để rollback không chồng nhau.
    if (state.personalSaving) return 'Một cài đặt khác đang được lưu.';
    final previous = state.userSettings;
    // `previous` là snapshot do Cubit đang giữ trước thao tác; `emit` phát một state
    // mới, không tự gán lại biến state cũ và không sửa object bất biến tại chỗ.
    emit(
      state.copyWith(
        userSettings: optimistic,
        personalSaving: true,
        clearMessage: true,
      ),
    );
    try {
      // Repository phát snapshot server qua stream; emit này chỉ tắt chỉ báo đang lưu.
      await _repository.updateUserSettings(changes);
      emit(state.copyWith(personalSaving: false, clearMessage: true));
      return null;
    } catch (error) {
      // Khôi phục đúng snapshot trước thao tác để giao diện không hiển thị cài đặt
      // chưa thực sự được backend lưu.
      final message = _errorMessage(error, 'Không thể lưu cài đặt cá nhân.');
      emit(
        state.copyWith(
          userSettings: previous,
          personalSaving: false,
          message: message,
        ),
      );
      return message;
    }
  }

  Future<String?> saveSystemSettings(SystemSettingsModel value) async {
    // Không optimistic với ngưỡng vận hành vì các ngưỡng ảnh hưởng logic toàn hệ thống.
    // Guard tránh hai admin action trên cùng giao diện gửi PATCH chồng nhau.
    if (state.systemSaving) return 'Cấu hình đang được lưu.';
    emit(state.copyWith(systemSaving: true, clearMessage: true));
    try {
      await _repository.updateSystemSettings(value.toJson());
      emit(state.copyWith(systemSaving: false, clearMessage: true));
      return null;
    } catch (error) {
      final message = _errorMessage(error, 'Không thể lưu cấu hình theo dõi.');
      emit(state.copyWith(systemSaving: false, message: message));
      return message;
    }
  }

  Future<void> loadUsers() async {
    // Chỉ màn quản trị gọi phương thức này; backend vẫn kiểm tra ADMIN tại endpoint.
    // Danh sách hiện tại được giữ trong khi tải để layout không co giật.
    if (state.usersLoading) return;
    emit(state.copyWith(usersLoading: true, clearMessage: true));
    try {
      final users = await _repository.loadUsers();
      emit(state.copyWith(users: users, usersLoading: false));
    } catch (error) {
      emit(
        state.copyWith(
          usersLoading: false,
          message: _errorMessage(error, 'Không thể tải danh sách tài khoản.'),
        ),
      );
    }
  }

  Future<String?> createUser(Map<String, dynamic> data) async {
    // Dùng runner chung để khóa thao tác, chuẩn hóa lỗi và tải lại danh sách thật.
    return _runUserOperation(() => _repository.createUser(data));
  }

  Future<String?> updateUser(
    String userId,
    Map<String, dynamic> data, {
    bool refreshUsers = true,
  }) async {
    // `refreshUsers=false` phục vụ sửa hồ sơ cá nhân để tránh tải danh sách quản trị.
    return _runUserOperation(
      () => _repository.updateUser(userId, data),
      refreshUsers: refreshUsers,
    );
  }

  Future<String?> resetUserPassword(String userId, String newPassword) async {
    // Backend tăng token_version của tài khoản mục tiêu; Cubit chỉ làm mới danh sách.
    return _runUserOperation(
      () => _repository.resetUserPassword(userId, newPassword),
    );
  }

  Future<void> loadDeviceManagement() async {
    // Guard không cho thao tác điều hướng/rebuild kích hoạt hai lần tải song song.
    if (state.devicesLoading) return;
    emit(state.copyWith(devicesLoading: true, clearMessage: true));
    try {
      // Hai tab thiết bị đã đăng ký/chờ duyệt tải song song nhưng cùng kết thúc trong
      // một state để UI không hiển thị số liệu lệch thời điểm giữa hai danh sách.
      final results = await Future.wait([
        _repository.loadManagedDevices(),
        _repository.loadMqttDeviceSightings(),
      ]);
      emit(
        state.copyWith(
          devices: results[0] as List<DeviceModel>,
          mqttDeviceSightings: results[1] as List<MqttDeviceSightingModel>,
          devicesLoading: false,
          clearMessage: true,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          devicesLoading: false,
          message: _errorMessage(
            error,
            'Không thể tải danh sách quản lý thiết bị.',
          ),
        ),
      );
    }
  }

  Future<void> refreshDeviceManagement() async {
    // Refresh nền giữ nguyên nội dung và không bật loading toàn trang.
    // Ba điều kiện bảo vệ tránh refresh tranh chấp với lần tải đầu hoặc thao tác ghi.
    if (_refreshingDeviceManagement ||
        state.devicesLoading ||
        state.deviceOperationInProgress) {
      return;
    }
    _refreshingDeviceManagement = true;
    try {
      final results = await Future.wait([
        _repository.loadManagedDevices(),
        _repository.loadMqttDeviceSightings(),
      ]);
      // Cubit có thể bị đóng trong lúc hai request chạy; kiểm tra trước emit.
      if (!isClosed) {
        emit(
          state.copyWith(
            devices: results[0] as List<DeviceModel>,
            mqttDeviceSightings: results[1] as List<MqttDeviceSightingModel>,
          ),
        );
      }
    } catch (_) {
      // Refresh nền là best-effort nên giữ dữ liệu hiện tại và không phát message lỗi lặp.
      // Làm mới nền không che nội dung hiện có hoặc lặp thông báo lỗi mạng.
    } finally {
      // Luôn mở khóa kể cả request lỗi để chu kỳ refresh sau còn hoạt động.
      _refreshingDeviceManagement = false;
    }
  }

  Future<String?> createDevice(Map<String, dynamic> data) {
    // Cả thêm thủ công và đăng ký sighting dùng cùng endpoint/runner nghiệp vụ.
    return _runDeviceOperation(() => _repository.createDevice(data));
  }

  Future<String?> updateDevice(String deviceId, Map<String, dynamic> data) {
    // PATCH hồ sơ hoặc is_enabled, sau đó đọc lại cả hai tab để phản ánh side effect.
    return _runDeviceOperation(() => _repository.updateDevice(deviceId, data));
  }

  Future<String?> deleteDevice(String deviceId) {
    // Chỉ tải lại danh sách sau khi DELETE đã được backend commit thành công.
    return _runDeviceOperation(
      () => _repository.deleteDevice(deviceId),
      failureMessage: 'Không thể xóa thiết bị.',
    );
  }

  Future<String?> _runDeviceOperation(
    Future<dynamic> Function() operation, {
    String failureMessage = 'Không thể cập nhật thiết bị.',
  }) async {
    // Một runner chung đảm bảo create/update/delete dùng cùng cơ chế khóa và báo lỗi.
    if (state.deviceOperationInProgress) {
      return 'Một thao tác thiết bị khác đang được thực hiện.';
    }
    emit(state.copyWith(deviceOperationInProgress: true, clearMessage: true));
    try {
      // operation là callback repository cụ thể được truyền từ thao tác quản lý thiết bị.
      await operation();
      // Luôn đọc lại nguồn thật sau thao tác vì backend có thể chuẩn hóa dữ liệu; đăng
      // ký hoặc xóa trong lúc thiết bị phát MQTT cũng có thể đổi danh sách chờ.
      final results = await Future.wait([
        _repository.loadManagedDevices(),
        _repository.loadMqttDeviceSightings(),
      ]);
      emit(
        state.copyWith(
          devices: results[0] as List<DeviceModel>,
          mqttDeviceSightings: results[1] as List<MqttDeviceSightingModel>,
          deviceOperationInProgress: false,
          clearMessage: true,
        ),
      );
      return null;
    } catch (error) {
      final message = _errorMessage(error, failureMessage);
      emit(state.copyWith(deviceOperationInProgress: false, message: message));
      return message;
    }
  }

  Future<String?> _runUserOperation(
    Future<dynamic> Function() operation, {
    bool refreshUsers = true,
  }) async {
    // Chặn create/update/reset password chạy đồng thời trên cùng SettingsCubit.
    if (state.userOperationInProgress) {
      return 'Một thao tác tài khoản khác đang được thực hiện.';
    }
    emit(state.copyWith(userOperationInProgress: true, clearMessage: true));
    try {
      // Chỉ sau khi backend xác nhận mới quyết định có tải lại danh sách hay giữ state cũ.
      await operation();
      // Trang hồ sơ chỉ sửa tài khoản hiện tại nên không tải cả danh sách
      // người dùng. Trang quản trị vẫn làm mới danh sách như trước.
      final users = refreshUsers ? await _repository.loadUsers() : state.users;
      emit(
        state.copyWith(
          users: users,
          userOperationInProgress: false,
          clearMessage: true,
        ),
      );
      return null;
    } catch (error) {
      final message = _errorMessage(error, 'Không thể cập nhật tài khoản.');
      emit(state.copyWith(userOperationInProgress: false, message: message));
      return message;
    }
  }

  void reset() {
    // Gọi khi đăng xuất để đơn vị tốc độ/ngưỡng của người trước không rò sang phiên sau.
    DeviceFormatters.resetRuntime();
    DeviceStatusResolver.resetRuntime();
    _repository.clearRuntimeValues();
    emit(const SettingsState());
  }

  static String _errorMessage(Object error, String fallback) {
    // Chi tiết nghiệp vụ từ FastAPI được ưu tiên; không phát raw lỗi kỹ thuật ra UI.
    if (error is DioException) {
      // FastAPI trả lỗi chuẩn trong khóa detail; các dạng payload khác dùng fallback.
      final data = error.response?.data;
      if (data is Map && data['detail'] is String) {
        final detail = data['detail'].toString().trim();
        // Chuỗi detail rỗng không hữu ích và không được đưa lên giao diện.
        if (detail.isNotEmpty) return detail;
      }
    }
    return fallback;
  }

  @override
  Future<void> close() async {
    await _userSettingsSubscription?.cancel();
    await _systemSettingsSubscription?.cancel();
    await super.close();
  }
}
