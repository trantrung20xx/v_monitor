import 'package:equatable/equatable.dart';

import '../../data/models/device_model.dart';

/// Dashboard state.
class DashboardState extends Equatable {
  const DashboardState({
    this.isLoading = true,
    this.error,
    this.devices = const [],
    this.totalDevices = 0,
    this.onlineCount = 0,
    this.offlineCount = 0,
    this.movingCount = 0,
    this.idleCount = 0,
  });

  final bool isLoading;
  final String? error;
  final List<DeviceModel> devices;
  final int totalDevices;
  final int onlineCount;
  final int offlineCount;
  final int movingCount;
  final int idleCount;

  DashboardState copyWith({
    bool? isLoading,
    String? error,
    List<DeviceModel>? devices,
    int? totalDevices,
    int? onlineCount,
    int? offlineCount,
    int? movingCount,
    int? idleCount,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      devices: devices ?? this.devices,
      totalDevices: totalDevices ?? this.totalDevices,
      onlineCount: onlineCount ?? this.onlineCount,
      offlineCount: offlineCount ?? this.offlineCount,
      movingCount: movingCount ?? this.movingCount,
      idleCount: idleCount ?? this.idleCount,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        error,
        devices,
        totalDevices,
        onlineCount,
        offlineCount,
        movingCount,
        idleCount,
      ];
}
