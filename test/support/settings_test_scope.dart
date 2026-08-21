import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';
import 'package:v_monitor/data/models/system_settings_model.dart';
import 'package:v_monitor/data/models/user_model.dart';
import 'package:v_monitor/data/models/user_settings_model.dart';
import 'package:v_monitor/data/repositories/settings_repository.dart';
import 'package:v_monitor/features/settings/settings_cubit.dart';

/// Cung cấp dependency Settings tối thiểu cho các widget test đã tồn tại.
class SettingsTestScope extends StatefulWidget {
  const SettingsTestScope({super.key, required this.child});

  final Widget child;

  @override
  State<SettingsTestScope> createState() => _SettingsTestScopeState();
}

class _SettingsTestScopeState extends State<SettingsTestScope> {
  late final _MemorySettingsRepository _repository;
  late final SettingsCubit _cubit;

  @override
  void initState() {
    super.initState();
    _repository = _MemorySettingsRepository();
    _cubit = SettingsCubit(_repository);
  }

  @override
  void dispose() {
    unawaited(_cubit.close());
    unawaited(_repository.dispose());
    _repository.websocket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<SettingsRepository>.value(
      value: _repository,
      child: BlocProvider<SettingsCubit>.value(
        value: _cubit,
        child: widget.child,
      ),
    );
  }
}

class _MemorySettingsRepository extends SettingsRepository {
  factory _MemorySettingsRepository() {
    final websocket = WebsocketClient();
    return _MemorySettingsRepository._(websocket);
  }

  _MemorySettingsRepository._(this.websocket) : super(ApiClient(), websocket);

  final WebsocketClient websocket;
  final _userController = StreamController<UserSettingsModel>.broadcast();
  final _systemController = StreamController<SystemSettingsModel>.broadcast();
  UserSettingsModel _user = const UserSettingsModel();
  SystemSettingsModel _system = const SystemSettingsModel();

  @override
  UserSettingsModel get userSettings => _user;

  @override
  SystemSettingsModel get systemSettings => _system;

  @override
  Stream<UserSettingsModel> get userSettingsChanges => _userController.stream;

  @override
  Stream<SystemSettingsModel> get systemSettingsChanges =>
      _systemController.stream;

  @override
  Future<UserSettingsModel> loadUserSettings() async => _user;

  @override
  Future<SystemSettingsModel> loadSystemSettings() async => _system;

  @override
  Future<UserSettingsModel> updateUserSettings(
    Map<String, dynamic> changes,
  ) async {
    final preferenceChanges = changes['preferences'];
    _user = _user.copyWith(
      theme: changes['theme']?.toString(),
      preferences: preferenceChanges is Map
          ? {
              ..._user.preferences,
              ...Map<String, dynamic>.from(preferenceChanges),
            }
          : _user.preferences,
    );
    _userController.add(_user);
    return _user;
  }

  @override
  Future<SystemSettingsModel> updateSystemSettings(
    Map<String, dynamic> changes,
  ) async {
    _system = SystemSettingsModel.fromJson({..._system.toJson(), ...changes});
    _systemController.add(_system);
    return _system;
  }

  @override
  Future<List<UserModel>> loadUsers() async => const [];

  @override
  Future<void> dispose() async {
    await _userController.close();
    await _systemController.close();
    await super.dispose();
  }
}
