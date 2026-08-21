import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';

typedef UnauthorizedHandler = Future<void> Function();

class ApiClient {
  final Dio _dio;
  String? _accessToken;
  UnauthorizedHandler? _unauthorizedHandler;

  ApiClient({Dio? dio})
    : _dio =
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

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return _dio.get(path, queryParameters: queryParameters);
  }

  Future<Response> post(String path, {dynamic data}) async {
    return _dio.post(path, data: data);
  }

  Future<Response> patch(String path, {dynamic data}) async {
    return _dio.patch(path, data: data);
  }
}
