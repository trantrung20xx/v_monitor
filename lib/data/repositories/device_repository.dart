// Cổng dữ liệu thiết bị: gọi REST cho danh sách/chi tiết và lọc WebSocket thành
// stream DeviceModel/DeviceEventModel. Repository không tự tính online hay chuyển động.
import 'package:flutter/foundation.dart';
import '../models/device_model.dart';
import '../models/device_event_model.dart';
import '../../core/network/api_client.dart';
import '../../core/network/websocket_client.dart';

/// Lớp Repository chịu trách nhiệm tương tác với API liên quan đến Thiết bị.
/// Nhận instance của ApiClient và WebsocketClient từ bên ngoài.
class DeviceRepository {
  // Client được inject để dùng chung base URL/token; repository không tự tạo kết nối.
  final ApiClient _apiClient;
  final WebsocketClient _websocketClient;

  DeviceRepository(this._apiClient, this._websocketClient);

  /// Lấy danh sách toàn bộ thiết bị từ Backend thông qua endpoint `/devices/`.
  Future<List<DeviceModel>> getDevices() async {
    // limit 5000 khớp quy mô danh sách vận hành và vẫn chịu trần bảo vệ của backend.
    try {
      final response = await _apiClient.get(
        '/devices/',
        queryParameters: const {'limit': 5000},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => DeviceModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      // Màn hình giám sát coi mất snapshot là danh sách rỗng và ghi log chẩn đoán;
      // Cubit không nhận raw DioException từ phương thức này.
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

  /// Lắng nghe dữ liệu realtime từ thiết bị qua WebSocket
  Stream<DeviceModel> get deviceUpdates {
    // Bỏ control frame và event khác; chỉ parse khi có đúng envelope DEVICE_UPDATE.
    return _websocketClient.messages
        .where(
          (data) => data['type'] == 'DEVICE_UPDATE' && data['device'] != null,
        )
        .map((data) => DeviceModel.fromJson(data['device']));
  }

  /// Lắng nghe các sự kiện realtime phát sinh từ thiết bị qua WebSocket
  Stream<DeviceEventModel> get deviceEvents {
    // Stream này chỉ chuyển kiểu dữ liệu, không tự thêm/suy luận sự kiện ở client.
    return _websocketClient.messages
        .where(
          (data) => data['type'] == 'DEVICE_EVENT' && data['event'] != null,
        )
        .map((data) => DeviceEventModel.fromJson(data['event']));
  }
}
