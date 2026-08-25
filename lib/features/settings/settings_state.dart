// State bất biến của cài đặt. Các cờ saving/loading tách theo nhóm để một thao tác
// không khóa toàn trang; message/error thể hiện kết quả gần nhất cho người dùng.
import 'package:equatable/equatable.dart';

import '../../data/models/system_settings_model.dart';
import '../../data/models/device_model.dart';
import '../../data/models/mqtt_device_sighting_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/user_settings_model.dart';

// Vòng đời tải chung của trang, tách khỏi các cờ thao tác theo từng nhóm.
enum SettingsLoadStatus { initial, loading, ready, error }

class SettingsState extends Equatable {
  // Constructor const tạo snapshot mặc định nhẹ và hỗ trợ so sánh state trong test.
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

  // status là vòng đời tải chung; userSettings/systemSettings là hai phạm vi cấu hình.
  final SettingsLoadStatus status;
  final UserSettingsModel userSettings;
  final SystemSettingsModel systemSettings;
  // users/devices/sightings là dữ liệu thật từ API, không phải danh sách mẫu trên UI.
  final List<UserModel> users;
  final List<DeviceModel> devices;
  final List<MqttDeviceSightingModel> mqttDeviceSightings;
  // Mỗi cờ chỉ khóa nhóm tương ứng để thao tác khác trên trang vẫn sử dụng được.
  final bool personalSaving;
  final bool systemSaving;
  final bool usersLoading;
  final bool userOperationInProgress;
  final bool devicesLoading;
  final bool deviceOperationInProgress;
  // message chứa phản hồi thành công/lỗi gần nhất và được xóa tường minh qua clearMessage.
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
    // `state` của Cubit không bị gán trực tiếp. copyWith lấy snapshot hiện tại làm
    // nền, thay trường được truyền rồi emit một SettingsState mới.
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
    // Equatable dùng toàn bộ trường để xác định hai snapshot có thực sự khác nhau.
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
