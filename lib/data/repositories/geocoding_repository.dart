import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../models/reverse_geocode_model.dart';

class GeocodingRepository {
  GeocodingRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<String?> reverseAddress(double latitude, double longitude) async {
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
