// Cổng reverse geocoding có cache địa chỉ hợp lệ, gộp request cùng tọa độ và
// trì hoãn thử lại sau lỗi để không gây bão request khi mạng hoặc provider gián đoạn.
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../models/reverse_geocode_model.dart';

class GeocodingRepository {
  GeocodingRepository(
    this._apiClient, {
    this.failureRetryDelay = const Duration(seconds: 15),
  });

  final ApiClient _apiClient;
  // Khoảng chờ cục bộ trước khi thử lại cùng tọa độ sau lỗi mạng/provider.
  final Duration failureRetryDelay;
  // Giữ kiểu nullable tương thích với instance được tạo trước hot reload.
  // Giá trị null vẫn không được lưu nên tra cứu thất bại luôn có thể thử lại.
  final Map<String, String?> _addressCache = {};
  // failedAt chống gọi dồn khi lỗi; pendingRequests gộp request đang chạy cùng tọa độ.
  final Map<String, DateTime> _failedAt = {};
  final Map<String, Future<String?>> _pendingRequests = {};

  Future<String?> reverseAddress(double latitude, double longitude) {
    // Làm tròn năm chữ số để các dao động GPS rất nhỏ dùng chung kết quả địa chỉ.
    final key =
        '${latitude.toStringAsFixed(5)},${longitude.toStringAsFixed(5)}';
    final cachedAddress = _addressCache[key];
    if (cachedAddress != null) {
      return Future.value(cachedAddress);
    }

    // Một tọa độ vừa lỗi được cooldown cục bộ để nhiều widget không gọi lại liên tục.
    final failedAt = _failedAt[key];
    if (failedAt != null) {
      if (DateTime.now().difference(failedAt) < failureRetryDelay) {
        return Future.value(null);
      }
      _failedAt.remove(key);
    }

    final pending = _pendingRequests[key];
    // Trả cùng Future cho mọi widget hỏi cùng tọa độ tại cùng thời điểm.
    if (pending != null) return pending;

    // Đăng ký Future vào pending trước khi trả; nhánh then chỉ cache địa chỉ có thật,
    // whenComplete luôn gỡ pending ở cả thành công lẫn lỗi.
    final request = _fetchAddress(latitude, longitude)
        .then((address) {
          if (address == null) {
            _failedAt[key] = DateTime.now();
          } else {
            _addressCache[key] = address;
            _failedAt.remove(key);
          }
          return address;
        })
        .whenComplete(() {
          _pendingRequests.remove(key);
        });
    _pendingRequests[key] = request;
    return request;
  }

  Future<String?> _fetchAddress(double latitude, double longitude) async {
    // Backend sở hữu provider, timeout và retry; Flutter chỉ dùng hợp đồng API nội bộ.
    try {
      final response = await _apiClient.get(
        '/geocoding/reverse',
        queryParameters: {'latitude': latitude, 'longitude': longitude},
      );
      if (response.statusCode == 200 && response.data is Map) {
        final model = ReverseGeocodeModel.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
        return model.bestAddress;
      }
    } catch (error) {
      // Địa chỉ là dữ liệu bổ trợ nên trả null thay vì làm hỏng màn hình GPS/bản đồ.
      debugPrint('Reverse geocoding failed: $error');
    }
    return null;
  }
}
