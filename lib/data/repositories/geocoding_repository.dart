import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../models/reverse_geocode_model.dart';

class GeocodingRepository {
  GeocodingRepository(this._apiClient);

  final ApiClient _apiClient;
  final Map<String, String?> _addressCache = {};
  final Map<String, Future<String?>> _pendingRequests = {};

  Future<String?> reverseAddress(double latitude, double longitude) {
    final key =
        '${latitude.toStringAsFixed(5)},${longitude.toStringAsFixed(5)}';
    if (_addressCache.containsKey(key)) {
      return Future.value(_addressCache[key]);
    }

    final pending = _pendingRequests[key];
    if (pending != null) return pending;

    final request = _fetchAddress(latitude, longitude).then((address) {
      _addressCache[key] = address;
      _pendingRequests.remove(key);
      return address;
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
