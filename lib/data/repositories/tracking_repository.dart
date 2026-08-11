import '../models/location_model.dart';
import '../models/device_event_model.dart';
import '../../core/network/api_client.dart';

class TrackingRepository {
  final ApiClient _apiClient;
  TrackingRepository(this._apiClient);

  Future<List<LocationModel>> getLocationHistory(String deviceId) async {
    try {
      final response = await _apiClient.get('/tracking/$deviceId/history');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => LocationModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching location history: $e');
      return [];
    }
  }

  Future<List<DeviceEventModel>> getEvents(String deviceId) async {
    try {
      final response = await _apiClient.get('/tracking/$deviceId/events');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => DeviceEventModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching device events: $e');
      return [];
    }
  }
}
