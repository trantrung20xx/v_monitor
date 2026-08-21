import 'dart:async';

import '../../core/network/api_client.dart';
import '../../core/network/websocket_client.dart';
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
  final _userSettingsController =
      StreamController<UserSettingsModel>.broadcast();
  final _systemSettingsController =
      StreamController<SystemSettingsModel>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _websocketSubscription;

  UserSettingsModel _userSettings = const UserSettingsModel();
  SystemSettingsModel _systemSettings = const SystemSettingsModel();

  UserSettingsModel get userSettings => _userSettings;
  SystemSettingsModel get systemSettings => _systemSettings;
  Stream<UserSettingsModel> get userSettingsChanges =>
      _userSettingsController.stream;
  Stream<SystemSettingsModel> get systemSettingsChanges =>
      _systemSettingsController.stream;

  Future<UserSettingsModel> loadUserSettings() async {
    final response = await _apiClient.get('/auth/settings');
    return _setUserSettings(
      UserSettingsModel.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      ),
    );
  }

  Future<SystemSettingsModel> loadSystemSettings() async {
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
    final response = await _apiClient.patch('/system/settings', data: changes);
    return _setSystemSettings(
      SystemSettingsModel.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      ),
    );
  }

  Future<List<UserModel>> loadUsers() async {
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

  void clearRuntimeValues() {
    _userSettings = const UserSettingsModel();
    _systemSettings = const SystemSettingsModel();
    _userSettingsController.add(_userSettings);
    _systemSettingsController.add(_systemSettings);
  }

  UserSettingsModel _setUserSettings(UserSettingsModel value) {
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
    final data = message['settings'];
    if (data is Map) {
      _setSystemSettings(
        SystemSettingsModel.fromJson(Map<String, dynamic>.from(data)),
      );
    }
  }

  Future<void> dispose() async {
    await _websocketSubscription?.cancel();
    await _userSettingsController.close();
    await _systemSettingsController.close();
  }
}
