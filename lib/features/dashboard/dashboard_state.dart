import 'package:equatable/equatable.dart';

import '../../data/models/device_model.dart';
import '../../domain/entities/device_query_filter.dart';

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
    this.stoppedCount = 0,
    this.inactiveCount = 0,
    this.staleCount = 0,
    this.attentionCount = 0,
    this.searchQuery = '',
    this.statusFilter = DeviceFilter.all,
    this.deviceAddresses = const {},
  });

  final bool isLoading;
  final String? error;
  final List<DeviceModel> devices;
  final int totalDevices;
  final int onlineCount;
  final int offlineCount;
  final int movingCount;
  final int stoppedCount;
  final int inactiveCount;
  final int staleCount;
  final int attentionCount;
  final String searchQuery;
  final DeviceFilter statusFilter;
  final Map<String, String> deviceAddresses;

  DashboardState copyWith({
    bool? isLoading,
    String? error,
    List<DeviceModel>? devices,
    int? totalDevices,
    int? onlineCount,
    int? offlineCount,
    int? movingCount,
    int? stoppedCount,
    int? inactiveCount,
    int? staleCount,
    int? attentionCount,
    String? searchQuery,
    DeviceFilter? statusFilter,
    Map<String, String>? deviceAddresses,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      devices: devices ?? this.devices,
      totalDevices: totalDevices ?? this.totalDevices,
      onlineCount: onlineCount ?? this.onlineCount,
      offlineCount: offlineCount ?? this.offlineCount,
      movingCount: movingCount ?? this.movingCount,
      stoppedCount: stoppedCount ?? this.stoppedCount,
      inactiveCount: inactiveCount ?? this.inactiveCount,
      staleCount: staleCount ?? this.staleCount,
      attentionCount: attentionCount ?? this.attentionCount,
      searchQuery: searchQuery ?? this.searchQuery,
      statusFilter: statusFilter ?? this.statusFilter,
      deviceAddresses: deviceAddresses ?? this.deviceAddresses,
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
    stoppedCount,
    inactiveCount,
    staleCount,
    attentionCount,
    searchQuery,
    statusFilter,
    deviceAddresses,
  ];
}
