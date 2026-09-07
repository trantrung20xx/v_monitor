// Cache LRU/TTL và hàng chờ hữu hạn cho địa chỉ đang được xem.
import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../models/reverse_geocode_model.dart';

class GeocodingRepository {
  GeocodingRepository(
    this._apiClient, {
    this.failureRetryDelay = const Duration(seconds: 15),
    this.cacheSize = AppConfig.geocodingCacheSize,
    this.maxPending = AppConfig.geocodingMaxPending,
    this.maxConcurrent = AppConfig.geocodingConcurrency,
    this.cacheTtl = const Duration(seconds: AppConfig.geocodingCacheTtlSeconds),
  }) {
    if (cacheSize < 1 ||
        maxPending < 1 ||
        maxConcurrent < 1 ||
        cacheTtl <= Duration.zero) {
      throw ArgumentError('Giới hạn geocoding phải lớn hơn 0');
    }
  }

  final ApiClient _apiClient;
  final Duration failureRetryDelay;
  final int cacheSize;
  final int maxPending;
  final int maxConcurrent;
  final Duration cacheTtl;
  final _cache = <String, ({String address, DateTime expires})>{};
  final _failedAt = <String, DateTime>{};
  final Map<String, Future<String?>> _pendingRequests = {};
  final _queue =
      Queue<
        ({String key, double lat, double lng, Completer<String?> result})
      >();
  int _active = 0;

  Future<String?> reverseAddress(double latitude, double longitude) {
    final key =
        '${latitude.toStringAsFixed(5)},${longitude.toStringAsFixed(5)}';
    final now = DateTime.now();
    final cached = _cache.remove(key);
    if (cached != null && now.isBefore(cached.expires)) {
      _cache[key] = cached;
      return Future.value(cached.address);
    }
    final failedAt = _failedAt[key];
    if (failedAt != null && now.difference(failedAt) < failureRetryDelay) {
      return Future.value(null);
    }
    _failedAt.remove(key);
    final pending = _pendingRequests[key];
    if (pending != null) return pending;
    if (_pendingRequests.length >= maxPending) return Future.value(null);
    final result = Completer<String?>();
    _pendingRequests[key] = result.future;
    _queue.add((key: key, lat: latitude, lng: longitude, result: result));
    _drain();
    return result.future;
  }

  void _drain() {
    while (_active < maxConcurrent && _queue.isNotEmpty) {
      final request = _queue.removeFirst();
      _active++;
      unawaited(_run(request));
    }
  }

  Future<void> _run(
    ({String key, double lat, double lng, Completer<String?> result}) request,
  ) async {
    try {
      final address = await _fetchAddress(request.lat, request.lng);
      if (address == null) {
        _failedAt[request.key] = DateTime.now();
        while (_failedAt.length > cacheSize) {
          _failedAt.remove(_failedAt.keys.first);
        }
      } else {
        _cache[request.key] = (
          address: address,
          expires: DateTime.now().add(cacheTtl),
        );
        while (_cache.length > cacheSize) {
          _cache.remove(_cache.keys.first);
        }
      }
      request.result.complete(address);
    } catch (_) {
      request.result.complete(null);
    } finally {
      _pendingRequests.remove(request.key);
      _active--;
      _drain();
    }
  }

  Future<String?> _fetchAddress(double latitude, double longitude) async {
    try {
      final response = await _apiClient.get(
        '/geocoding/reverse',
        queryParameters: {'latitude': latitude, 'longitude': longitude},
      );
      if (response.statusCode == 200 && response.data is Map) {
        return ReverseGeocodeModel.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        ).bestAddress;
      }
    } catch (error) {
      debugPrint('Reverse geocoding failed: $error');
    }
    return null;
  }
}
