import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../models/reverse_geocode_model.dart';

class GeocodingRepository {
  GeocodingRepository(
    this._apiClient, {
    this.failureRetryDelay = const Duration(seconds: 15),
  });

  final ApiClient _apiClient;
  final Duration failureRetryDelay;
  // Giữ kiểu nullable tương thích với instance được tạo trước hot reload.
  // Giá trị null vẫn không được lưu nên tra cứu thất bại luôn có thể thử lại.
  final Map<String, String?> _addressCache = {};
  final Map<String, DateTime> _failedAt = {};
  final Map<String, Future<String?>> _pendingRequests = {};

  Future<String?> reverseAddress(double latitude, double longitude) {
    final key =
        '${latitude.toStringAsFixed(5)},${longitude.toStringAsFixed(5)}';
    final cachedAddress = _addressCache[key];
    if (cachedAddress != null) {
      return Future.value(cachedAddress);
    }

    final failedAt = _failedAt[key];
    if (failedAt != null) {
      if (DateTime.now().difference(failedAt) < failureRetryDelay) {
        return Future.value(null);
      }
      _failedAt.remove(key);
    }

    final pending = _pendingRequests[key];
    if (pending != null) return pending;

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
      debugPrint('Reverse geocoding failed: $error');
    }
    return null;
  }
}
