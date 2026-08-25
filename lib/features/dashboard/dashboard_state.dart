// State bất biến của dashboard gồm dữ liệu gốc, số liệu tổng hợp, bộ lọc và cache
// địa chỉ theo device id. filteredDevices chỉ tạo lát cắt hiển thị, không sửa danh sách gốc.
import 'package:equatable/equatable.dart';

import '../../data/models/device_model.dart';
import '../../domain/entities/device_query_filter.dart';

/// Ảnh chụp toàn bộ dữ liệu cần để dựng dashboard tại một thời điểm.
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

  // Trạng thái tải/lỗi chỉ mô tả lần lấy snapshot REST gần nhất.
  final bool isLoading;
  final String? error;
  // devices là dữ liệu gốc; các count là kết quả đã resolve cùng thời điểm emit.
  final List<DeviceModel> devices;
  final int totalDevices;
  final int onlineCount;
  final int offlineCount;
  final int movingCount;
  final int stoppedCount;
  final int inactiveCount;
  final int staleCount;
  final int attentionCount;
  // Hai điều kiện chỉ lọc phần hiển thị, không xóa hoặc sửa devices.
  final String searchQuery;
  final DeviceFilter statusFilter;
  // Ánh xạ device id sang địa chỉ geocoding hiện có; thiếu khóa nghĩa là chưa dịch được.
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
    // Tạo snapshot mới từ state hiện tại; riêng error nhận trực tiếp để một lần tải
    // thành công có thể xóa lỗi cũ bằng null.
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
    // Mọi dữ liệu ảnh hưởng UI đều tham gia so sánh Equatable.
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
