// Cổng dữ liệu cài đặt, tài khoản và quản lý thiết bị. Giá trị runtime được cache
// trong repository và cập nhật ngay từ SYSTEM_SETTINGS_UPDATED qua WebSocket.
import 'dart:async';

import '../../core/network/api_client.dart';
import '../../core/network/websocket_client.dart';
import '../models/device_model.dart';
import '../models/mqtt_device_sighting_model.dart';
import '../models/system_settings_model.dart';
import '../models/user_model.dart';
import '../models/user_settings_model.dart';

class SettingsRepository {
  SettingsRepository(this._apiClient, this._websocketClient) {
    _websocketSubscription = _websocketClient.messages
        .where((message) => message['type'] == 'SYSTEM_SETTINGS_UPDATED')
        .listen(_handleSystemSettingsEvent);
  }

  final ApiClient _apiClient;
  final WebsocketClient _websocketClient;
  // Controller broadcast cho phép App/theme, SettingsCubit và màn hình hành trình
  // cùng nghe một giá trị runtime mà không tạo nhiều request riêng.
  final _userSettingsController =
      StreamController<UserSettingsModel>.broadcast();
  final _systemSettingsController =
      StreamController<SystemSettingsModel>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _websocketSubscription;

  // Hai snapshot mặc định tồn tại trước khi đăng nhập/tải server và được thay toàn bộ
  // bằng response đã parse thành công.
  UserSettingsModel _userSettings = const UserSettingsModel();
  SystemSettingsModel _systemSettings = const SystemSettingsModel();

  UserSettingsModel get userSettings => _userSettings;
  SystemSettingsModel get systemSettings => _systemSettings;
  Stream<UserSettingsModel> get userSettingsChanges =>
      _userSettingsController.stream;
  Stream<SystemSettingsModel> get systemSettingsChanges =>
      _systemSettingsController.stream;

  Future<UserSettingsModel> loadUserSettings() async {
    // Cài đặt cá nhân thuộc tài khoản đang mang Bearer token.
    final response = await _apiClient.get('/auth/settings');
    return _setUserSettings(
      UserSettingsModel.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      ),
    );
  }

  Future<SystemSettingsModel> loadSystemSettings() async {
    // Cấu hình theo dõi dùng chung toàn hệ thống; quyền đọc do backend quyết định.
    final response = await _apiClient.get('/system/settings');
    return _setSystemSettings(
      SystemSettingsModel.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      ),
    );
  }

  Future<UserSettingsModel> updateUserSettings(
    Map<String, dynamic> changes,
  ) async {
    // Chỉ phát stream sau khi PATCH trả model đã được backend xác nhận.
    final response = await _apiClient.patch('/auth/settings', data: changes);
    return _setUserSettings(
      UserSettingsModel.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      ),
    );
  }

  Future<SystemSettingsModel> updateSystemSettings(
    Map<String, dynamic> changes,
  ) async {
    // Endpoint quản trị kiểm tra ADMIN; frontend không được xem là lớp bảo mật.
    final response = await _apiClient.patch('/system/settings', data: changes);
    return _setSystemSettings(
      SystemSettingsModel.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      ),
    );
  }

  Future<List<UserModel>> loadUsers() async {
    // Danh sách tài khoản chỉ dùng trong quản trị và bị backend giới hạn/phân quyền.
    final response = await _apiClient.get(
      '/users/',
      queryParameters: const {'limit': 1000},
    );
    final data = response.data as List<dynamic>;
    return data
        .map(
          (item) => UserModel.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<UserModel> createUser(Map<String, dynamic> data) async {
    final response = await _apiClient.post('/users/', data: data);
    return UserModel.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<UserModel> updateUser(String userId, Map<String, dynamic> data) async {
    final response = await _apiClient.patch('/users/$userId', data: data);
    return UserModel.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<void> resetUserPassword(String userId, String newPassword) async {
    await _apiClient.post(
      '/users/$userId/reset-password',
      data: {'new_password': newPassword},
    );
  }

  Future<List<DeviceModel>> loadManagedDevices() async {
    // Dữ liệu tab đã đăng ký lấy từ bảng devices kèm latest state thật.
    final response = await _apiClient.get(
      '/devices/',
      queryParameters: const {'limit': 5000},
    );
    final data = response.data as List<dynamic>;
    return data
        .map(
          (item) =>
              DeviceModel.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<List<MqttDeviceSightingModel>> loadMqttDeviceSightings() async {
    // Dữ liệu tab chờ duyệt là thống kê mã lạ, không phải thiết bị được phép hoạt động.
    final response = await _apiClient.get(
      '/devices/mqtt-sightings',
      queryParameters: const {'limit': 5000},
    );
    final data = response.data as List<dynamic>;
    return data
        .map(
          (item) => MqttDeviceSightingModel.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<DeviceModel> createDevice(Map<String, dynamic> data) async {
    final response = await _apiClient.post('/devices/', data: data);
    return DeviceModel.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<DeviceModel> updateDevice(
    String deviceId,
    Map<String, dynamic> data,
  ) async {
    final response = await _apiClient.patch('/devices/$deviceId', data: data);
    return DeviceModel.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  void clearRuntimeValues() {
    // Xóa snapshot khi đăng xuất và phát default để mọi consumer bỏ cấu hình phiên cũ.
    _userSettings = const UserSettingsModel();
    _systemSettings = const SystemSettingsModel();
    _userSettingsController.add(_userSettings);
    _systemSettingsController.add(_systemSettings);
  }

  UserSettingsModel _setUserSettings(UserSettingsModel value) {
    // Gán snapshot trước rồi phát để getter và stream luôn quan sát cùng giá trị.
    _userSettings = value;
    _userSettingsController.add(value);
    return value;
  }

  SystemSettingsModel _setSystemSettings(SystemSettingsModel value) {
    _systemSettings = value;
    _systemSettingsController.add(value);
    return value;
  }

  void _handleSystemSettingsEvent(Map<String, dynamic> message) {
    // Chỉ chấp nhận event có object settings; frame sai hợp đồng bị bỏ an toàn.
    final data = message['settings'];
    if (data is Map) {
      _setSystemSettings(
        SystemSettingsModel.fromJson(Map<String, dynamic>.from(data)),
      );
    }
  }

  Future<void> dispose() async {
    // Repository sống ở cấp ứng dụng nên chỉ dispose khi toàn cây dependency kết thúc.
    await _websocketSubscription?.cancel();
    await _userSettingsController.close();
    await _systemSettingsController.close();
  }
}
