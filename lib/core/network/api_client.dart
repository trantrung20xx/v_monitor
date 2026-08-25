import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';

typedef UnauthorizedHandler = Future<void> Function();

class ApiClient {
  final Dio _dio;
  final int _getRetryCount;
  final Duration _retryDelay;
  String? _accessToken;
  UnauthorizedHandler? _unauthorizedHandler;

  ApiClient({Dio? dio, int? getRetryCount, Duration? retryDelay})
    : _getRetryCount = getRetryCount ?? AppConfig.httpGetRetryCount,
      _retryDelay = retryDelay ?? AppConfig.httpRetryDelay,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: Duration(
                seconds: AppConfig.connectTimeoutSeconds,
              ),
              receiveTimeout: Duration(
                seconds: AppConfig.connectTimeoutSeconds,
              ),
            ),
          ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _accessToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          // Chỉ phát tín hiệu thu hồi khi request đang dùng khóa đăng nhập.
          // Lỗi 401 của lần nhập sai mật khẩu không được coi là một lần bị ép thoát.
          if (error.response?.statusCode == 401 && _accessToken != null) {
            _accessToken = null;
            final callback = _unauthorizedHandler;
            if (callback != null) unawaited(callback());
          }
          handler.next(error);
        },
      ),
    );
  }

  String get baseUrl => _dio.options.baseUrl;

  void setAccessToken(String? token) {
    final normalized = token?.trim();
    _accessToken = normalized == null || normalized.isEmpty ? null : normalized;
  }

  void setUnauthorizedHandler(UnauthorizedHandler? handler) {
    _unauthorizedHandler = handler;
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) {
    return _getWithRetry(path, queryParameters: queryParameters);
  }

  Future<Response> post(String path, {dynamic data}) async {
    return _dio.post(path, data: data);
  }

  Future<Response> patch(String path, {dynamic data}) async {
    return _dio.patch(path, data: data);
  }

  Future<Response> _getWithRetry(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    var retryIndex = 0;
    while (true) {
      try {
        return await _dio.get(path, queryParameters: queryParameters);
      } on DioException catch (error) {
        if (retryIndex >= _getRetryCount || !_canRetryGet(error)) {
          rethrow;
        }

        // Khoảng chờ tăng theo cấp số nhân để một đợt mất mạng hoặc lỗi 503
        // không khiến nhiều thiết bị đồng thời gửi lại request liên tục.
        final exponent = retryIndex > 10 ? 10 : retryIndex;
        final multiplier = 1 << exponent;
        retryIndex++;
        final delay = Duration(
          milliseconds: _retryDelay.inMilliseconds * multiplier,
        );
        if (delay > Duration.zero) await Future<void>.delayed(delay);
      }
    }
  }

  bool _canRetryGet(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        return const {
          408,
          429,
          502,
          503,
          504,
        }.contains(error.response?.statusCode);
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return false;
    }
  }
}
