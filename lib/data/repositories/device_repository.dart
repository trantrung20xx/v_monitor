import 'package:flutter/foundation.dart';
import '../models/device_model.dart';
import '../models/assignment_model.dart';
import '../models/usage_session_model.dart';
import '../../core/network/api_client.dart';
import '../../core/network/websocket_client.dart';

/// Lớp Repository chịu trách nhiệm tương tác với API liên quan đến Thiết bị.
/// Nhận instance của ApiClient và WebsocketClient từ bên ngoài.
class DeviceRepository {
  final ApiClient _apiClient;
  final WebsocketClient _websocketClient;

  DeviceRepository(this._apiClient, this._websocketClient);

  /// Lấy danh sách toàn bộ thiết bị từ Backend thông qua endpoint `/devices/`.
  Future<List<DeviceModel>> getDevices() async {
    try {
      final response = await _apiClient.get('/devices/');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => DeviceModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Lỗi khi lấy danh sách thiết bị: $e');
      return [];
    }
  }

  /// Lấy thông tin chi tiết của một thiết bị cụ thể thông qua ID.
  Future<DeviceModel?> getDevice(String id) async {
    try {
      final response = await _apiClient.get('/devices/$id');
      if (response.statusCode == 200) {
        return DeviceModel.fromJson(response.data);
      }
      return null;
    } catch (e) {
      debugPrint('Lỗi khi lấy thông tin chi tiết thiết bị: $e');
      return null;
    }
  }

  /// Lấy lịch sử phân công người sử dụng cho thiết bị
  Future<List<AssignmentModel>> getDeviceAssignments(String id) async {
    try {
      final response = await _apiClient.get('/devices/$id/assignments');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => AssignmentModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Lỗi khi lấy danh sách phân công: $e');
      return [];
    }
  }

  /// Lấy lịch sử phiên sử dụng của thiết bị
  Future<List<UsageSessionModel>> getDeviceUsages(String id) async {
    try {
      final response = await _apiClient.get('/devices/$id/usages');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => UsageSessionModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Lỗi khi lấy danh sách phiên sử dụng: $e');
      return [];
    }
  }

  Future<Map<String, UsageSessionModel>> getLatestDeviceUsages() async {
    try {
      final response = await _apiClient.get('/devices/usages/latest');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        final usages = data.map((json) => UsageSessionModel.fromJson(json));
        return {
          for (final usage in usages)
            if (usage.deviceId.isNotEmpty) usage.deviceId: usage,
        };
      }
      return {};
    } catch (e) {
      debugPrint('Lỗi khi lấy phiên sử dụng mới nhất: $e');
      return {};
    }
  }

  /// Lắng nghe dữ liệu realtime từ thiết bị qua WebSocket
  Stream<DeviceModel> get deviceUpdates {
    return _websocketClient.messages
        .where(
          (data) => data['type'] == 'DEVICE_UPDATE' && data['device'] != null,
        )
        .map((data) => DeviceModel.fromJson(data['device']));
  }
}
