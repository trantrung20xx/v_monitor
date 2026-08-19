import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/data/repositories/geocoding_repository.dart';

void main() {
  test('GeocodingRepository requests reverse address from backend', () async {
    final apiClient = _FakeApiClient();
    final repository = GeocodingRepository(apiClient);

    final address = await repository.reverseAddress(21.147, 105.8048);
    final cachedAddress = await repository.reverseAddress(21.147, 105.8048);

    expect(address, 'So 1 Trang Tien, Hoan Kiem, Ha Noi');
    expect(cachedAddress, address);
    expect(apiClient.requestCount, 1);
    expect(apiClient.lastPath, '/geocoding/reverse');
    expect(apiClient.lastQuery?['latitude'], 21.147);
    expect(apiClient.lastQuery?['longitude'], 105.8048);
  });
}

class _FakeApiClient extends ApiClient {
  String? lastPath;
  Map<String, dynamic>? lastQuery;
  int requestCount = 0;

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    requestCount++;
    lastPath = path;
    lastQuery = queryParameters;
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {
        'latitude': 21.147,
        'longitude': 105.8048,
        'formatted_address': 'So 1 Trang Tien, Hoan Kiem, Ha Noi',
        'display_name': 'Longer display name',
        'provider': 'test',
      },
    );
  }
}
