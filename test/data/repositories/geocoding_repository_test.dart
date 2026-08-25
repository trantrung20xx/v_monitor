// Xác nhận cache địa chỉ, gộp request và khoảng chờ thử lại sau lỗi geocoding.
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

  test('GeocodingRepository retries after an address lookup failure', () async {
    final apiClient = _FakeApiClient()
      ..formattedAddress = null
      ..displayName = null;
    final repository = GeocodingRepository(
      apiClient,
      failureRetryDelay: Duration.zero,
    );

    final failedAddress = await repository.reverseAddress(21.0285, 105.8126);
    apiClient.formattedAddress = '31 Nguyễn Chí Thanh, Hà Nội';
    final recoveredAddress = await repository.reverseAddress(21.0285, 105.8126);

    expect(failedAddress, isNull);
    expect(recoveredAddress, '31 Nguyễn Chí Thanh, Hà Nội');
    expect(apiClient.requestCount, 2);
  });
}

class _FakeApiClient extends ApiClient {
  String? lastPath;
  Map<String, dynamic>? lastQuery;
  int requestCount = 0;
  String? formattedAddress = 'So 1 Trang Tien, Hoan Kiem, Ha Noi';
  String? displayName = 'Longer display name';

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
        'formatted_address': formattedAddress,
        'display_name': displayName,
        'provider': 'test',
      },
    );
  }
}
