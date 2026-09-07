// Xác nhận cache địa chỉ, gộp request và khoảng chờ thử lại sau lỗi geocoding.
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/data/repositories/geocoding_repository.dart';

void main() {
  test(
    'geocoding bounds pending requests and concurrency, then resumes queue',
    () async {
      final client = _BlockedApiClient();
      final repository = GeocodingRepository(
        client,
        maxPending: 3,
        maxConcurrent: 1,
      );
      final first = repository.reverseAddress(1, 1);
      final duplicate = repository.reverseAddress(1, 1);
      final second = repository.reverseAddress(2, 2);
      final third = repository.reverseAddress(3, 3);
      expect(identical(first, duplicate), isTrue);
      expect(await repository.reverseAddress(4, 4), isNull);
      expect(client.requests.length, 1);
      for (var i = 0; i < 3; i++) {
        client.requests[i].complete(
          Response(
            requestOptions: RequestOptions(path: '/geocoding/reverse'),
            statusCode: 200,
            data: {'formatted_address': 'Address $i', 'provider': 'test'},
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(client.requests.length, (i + 2).clamp(1, 3));
      }
      expect(await Future.wait([first, second, third]), [
        'Address 0',
        'Address 1',
        'Address 2',
      ]);
    },
  );

  test(
    'geocoding LRU evicts old coordinates and TTL expires cached addresses',
    () async {
      final api = _FakeApiClient();
      final repository = GeocodingRepository(api, cacheSize: 2);
      await repository.reverseAddress(1, 1);
      await repository.reverseAddress(2, 2);
      await repository.reverseAddress(1, 1);
      await repository.reverseAddress(3, 3);
      await repository.reverseAddress(2, 2);
      expect(api.requestCount, 4);
      final ttl = GeocodingRepository(
        api,
        cacheTtl: const Duration(milliseconds: 1),
      );
      await ttl.reverseAddress(1, 1);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await ttl.reverseAddress(1, 1);
      expect(api.requestCount, 6);
    },
  );
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

class _BlockedApiClient extends ApiClient {
  final requests = <Completer<Response>>[];
  @override
  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) {
    final response = Completer<Response>();
    requests.add(response);
    return response.future;
  }
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
