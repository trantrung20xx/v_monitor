import 'package:equatable/equatable.dart';

import '../../data/models/system_settings_model.dart';
import '../../data/models/device_model.dart';
import '../../data/models/mqtt_device_sighting_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/user_settings_model.dart';

enum SettingsLoadStatus { initial, loading, ready, error }

class SettingsState extends Equatable {
  const SettingsState({
    this.status = SettingsLoadStatus.initial,
    this.userSettings = const UserSettingsModel(),
    this.systemSettings = const SystemSettingsModel(),
    this.users = const [],
    this.devices = const [],
    this.mqttDeviceSightings = const [],
    this.personalSaving = false,
    this.systemSaving = false,
    this.usersLoading = false,
    this.userOperationInProgress = false,
    this.devicesLoading = false,
    this.deviceOperationInProgress = false,
    this.message,
  });

  final SettingsLoadStatus status;
  final UserSettingsModel userSettings;
  final SystemSettingsModel systemSettings;
  final List<UserModel> users;
  final List<DeviceModel> devices;
  final List<MqttDeviceSightingModel> mqttDeviceSightings;
  final bool personalSaving;
  final bool systemSaving;
  final bool usersLoading;
  final bool userOperationInProgress;
  final bool devicesLoading;
  final bool deviceOperationInProgress;
  final String? message;

  SettingsState copyWith({
    SettingsLoadStatus? status,
    UserSettingsModel? userSettings,
    SystemSettingsModel? systemSettings,
    List<UserModel>? users,
    List<DeviceModel>? devices,
    List<MqttDeviceSightingModel>? mqttDeviceSightings,
    bool? personalSaving,
    bool? systemSaving,
    bool? usersLoading,
    bool? userOperationInProgress,
    bool? devicesLoading,
    bool? deviceOperationInProgress,
    String? message,
    bool clearMessage = false,
  }) {
    return SettingsState(
      status: status ?? this.status,
      userSettings: userSettings ?? this.userSettings,
      systemSettings: systemSettings ?? this.systemSettings,
      users: users ?? this.users,
      devices: devices ?? this.devices,
      mqttDeviceSightings: mqttDeviceSightings ?? this.mqttDeviceSightings,
      personalSaving: personalSaving ?? this.personalSaving,
      systemSaving: systemSaving ?? this.systemSaving,
      usersLoading: usersLoading ?? this.usersLoading,
      userOperationInProgress:
          userOperationInProgress ?? this.userOperationInProgress,
      devicesLoading: devicesLoading ?? this.devicesLoading,
      deviceOperationInProgress:
          deviceOperationInProgress ?? this.deviceOperationInProgress,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  List<Object?> get props => [
    status,
    userSettings,
    systemSettings,
    users,
    devices,
    mqttDeviceSightings,
    personalSaving,
    systemSaving,
    usersLoading,
    userOperationInProgress,
    devicesLoading,
    deviceOperationInProgress,
    message,
  ];
}
