import 'package:flutter/foundation.dart';
import '../models/location_model.dart';
import '../models/device_event_model.dart';
import '../../core/network/api_client.dart';

/// Lớp Repository phụ trách việc truy vấn dữ liệu theo dõi (vị trí lịch sử, sự kiện) của thiết bị.
class TrackingRepository {
  final ApiClient _apiClient;
  TrackingRepository(this._apiClient);

  /// Lấy danh sách lịch sử vị trí của một thiết bị.
  /// Gọi API `/tracking/$deviceId/history` và trả về danh sách [LocationModel].
  Future<List<LocationModel>> getLocationHistory(String deviceId) async {
    try {
      // Gửi yêu cầu GET tới API backend
      final response = await _apiClient.get('/tracking/$deviceId/history');
      if (response.statusCode == 200) {
        // Ánh xạ dữ liệu JSON thành các model Dart
        final List<dynamic> data = response.data;
        return data.map((json) => LocationModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      // Ghi log lỗi bằng debugPrint (khắc phục cảnh báo avoid_print)
      debugPrint('Lỗi khi lấy lịch sử vị trí: $e');
      return [];
    }
  }

  /// Lấy danh sách các sự kiện (Cảnh báo pin, lỗi, v.v.) của thiết bị.
  /// Gọi API `/tracking/$deviceId/events` và trả về danh sách [DeviceEventModel].
  Future<List<DeviceEventModel>> getEvents(String deviceId) async {
    try {
      final response = await _apiClient.get('/tracking/$deviceId/events');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => DeviceEventModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      // Ghi log lỗi bằng debugPrint
      debugPrint('Lỗi khi lấy sự kiện thiết bị: $e');
      return [];
    }
  }
}
