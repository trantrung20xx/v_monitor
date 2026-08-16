import 'package:flutter/foundation.dart';
import '../models/location_model.dart';
import '../models/location_history_response.dart';
import '../models/device_event_model.dart';
import '../../core/network/api_client.dart';

/// Lớp Repository phụ trách việc truy vấn dữ liệu theo dõi (vị trí lịch sử, sự kiện) của thiết bị.
class TrackingRepository {
  final ApiClient _apiClient;
  TrackingRepository(this._apiClient);

  /// Lấy danh sách lịch sử vị trí của một thiết bị (gần nhất theo limit).
  /// Gọi API `/tracking/$deviceId/history` và trả về danh sách [LocationModel].
  Future<List<LocationModel>> getLocationHistory(String deviceId) async {
    try {
      final response = await _apiClient.get('/tracking/$deviceId/history');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => LocationModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Lỗi khi lấy lịch sử vị trí: $e');
      return [];
    }
  }

  /// Lấy danh sách lịch sử vị trí trong khoảng thời gian [from, to].
  /// Gọi API `/tracking/$deviceId/history/range` và trả về [LocationHistoryResponse].
  Future<LocationHistoryResponse?> getLocationHistoryRange(
    String deviceId, {
    required DateTime from,
    required DateTime to,
    int? maxSamples,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      };
      if (maxSamples != null) {
        queryParams['max_samples'] = maxSamples;
      }

      final response = await _apiClient.get(
        '/tracking/$deviceId/history/range',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data is Map) {
        return LocationHistoryResponse.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }
      return null;
    } catch (e) {
      debugPrint('Lỗi khi lấy lịch sử hành trình theo khoảng: $e');
      rethrow;
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
      debugPrint('Lỗi khi lấy sự kiện thiết bị: $e');
      return [];
    }
  }
}
