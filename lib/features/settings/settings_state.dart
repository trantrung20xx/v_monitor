import 'package:equatable/equatable.dart';

import '../../data/models/system_settings_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/user_settings_model.dart';

enum SettingsLoadStatus { initial, loading, ready, error }

class SettingsState extends Equatable {
  const SettingsState({
    this.status = SettingsLoadStatus.initial,
    this.userSettings = const UserSettingsModel(),
    this.systemSettings = const SystemSettingsModel(),
    this.users = const [],
    this.personalSaving = false,
    this.systemSaving = false,
    this.usersLoading = false,
    this.userOperationInProgress = false,
    this.message,
  });

  final SettingsLoadStatus status;
  final UserSettingsModel userSettings;
  final SystemSettingsModel systemSettings;
  final List<UserModel> users;
  final bool personalSaving;
  final bool systemSaving;
  final bool usersLoading;
  final bool userOperationInProgress;
  final String? message;

  SettingsState copyWith({
    SettingsLoadStatus? status,
    UserSettingsModel? userSettings,
    SystemSettingsModel? systemSettings,
    List<UserModel>? users,
    bool? personalSaving,
    bool? systemSaving,
    bool? usersLoading,
    bool? userOperationInProgress,
    String? message,
    bool clearMessage = false,
  }) {
    return SettingsState(
      status: status ?? this.status,
      userSettings: userSettings ?? this.userSettings,
      systemSettings: systemSettings ?? this.systemSettings,
      users: users ?? this.users,
      personalSaving: personalSaving ?? this.personalSaving,
      systemSaving: systemSaving ?? this.systemSaving,
      usersLoading: usersLoading ?? this.usersLoading,
      userOperationInProgress:
          userOperationInProgress ?? this.userOperationInProgress,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  List<Object?> get props => [
    status,
    userSettings,
    systemSettings,
    users,
    personalSaving,
    systemSaving,
    usersLoading,
    userOperationInProgress,
    message,
  ];
}
