import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

class ApiClient {
  final Dio _dio;

  ApiClient()
    : _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: Duration(seconds: AppConfig.connectTimeoutSeconds),
          receiveTimeout: Duration(seconds: AppConfig.connectTimeoutSeconds),
        ),
      ) {
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(responseBody: true));
    }
  }

  String get baseUrl => _dio.options.baseUrl;

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return _dio.get(path, queryParameters: queryParameters);
  }

  Future<Response> post(String path, {dynamic data}) async {
    return _dio.post(path, data: data);
  }
}
