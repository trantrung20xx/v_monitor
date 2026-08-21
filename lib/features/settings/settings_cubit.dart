import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/config/map_tile_providers.dart';
import '../../core/utils/device_formatters.dart';
import '../../data/models/system_settings_model.dart';
import '../../data/models/user_settings_model.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/device_status_resolver.dart';
import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._repository) : super(const SettingsState()) {
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
  StreamSubscription<UserSettingsModel>? _userSettingsSubscription;
  StreamSubscription<SystemSettingsModel>? _systemSettingsSubscription;
  bool _initializing = false;

  Future<void> initialize() async {
    if (_initializing) return;
    _initializing = true;
    emit(
      state.copyWith(status: SettingsLoadStatus.loading, clearMessage: true),
    );

    final errors = <String>[];
    try {
      await _repository.loadUserSettings();
    } catch (error) {
      errors.add(_errorMessage(error, 'Không thể tải cài đặt cá nhân.'));
    }
    try {
      await _repository.loadSystemSettings();
    } catch (error) {
      errors.add(_errorMessage(error, 'Không thể tải cấu hình theo dõi.'));
    }

    _initializing = false;
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

  Future<String?> _updatePersonal({
    required UserSettingsModel optimistic,
    required Map<String, dynamic> changes,
  }) async {
    if (state.personalSaving) return 'Một cài đặt khác đang được lưu.';
    final previous = state.userSettings;
    emit(
      state.copyWith(
        userSettings: optimistic,
        personalSaving: true,
        clearMessage: true,
      ),
    );
    try {
      await _repository.updateUserSettings(changes);
      emit(state.copyWith(personalSaving: false, clearMessage: true));
      return null;
    } catch (error) {
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
    return _runUserOperation(() => _repository.createUser(data));
  }

  Future<String?> updateUser(
    String userId,
    Map<String, dynamic> data, {
    bool refreshUsers = true,
  }) async {
    return _runUserOperation(
      () => _repository.updateUser(userId, data),
      refreshUsers: refreshUsers,
    );
  }

  Future<String?> resetUserPassword(String userId, String newPassword) async {
    return _runUserOperation(
      () => _repository.resetUserPassword(userId, newPassword),
    );
  }

  Future<String?> _runUserOperation(
    Future<dynamic> Function() operation, {
    bool refreshUsers = true,
  }) async {
    if (state.userOperationInProgress) {
      return 'Một thao tác tài khoản khác đang được thực hiện.';
    }
    emit(state.copyWith(userOperationInProgress: true, clearMessage: true));
    try {
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
    DeviceFormatters.resetRuntime();
    DeviceStatusResolver.resetRuntime();
    _repository.clearRuntimeValues();
    emit(const SettingsState());
  }

  static String _errorMessage(Object error, String fallback) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] is String) {
        final detail = data['detail'].toString().trim();
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
