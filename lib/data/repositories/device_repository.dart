import '../models/device_model.dart';
import '../../core/network/api_client.dart';

class DeviceRepository {
  final ApiClient _apiClient;
  DeviceRepository(this._apiClient);

  Future<List<DeviceModel>> getDevices() async {
    try {
      final response = await _apiClient.get('/devices/');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => DeviceModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Error fetching devices: $e');
      return [];
    }
  }

  Future<DeviceModel?> getDevice(String id) async {
    try {
      final response = await _apiClient.get('/devices/$id');
      if (response.statusCode == 200) {
        return DeviceModel.fromJson(response.data);
      }
      return null;
    } catch (e) {
      print('Error fetching device: $e');
      return null;
    }
  }
}
