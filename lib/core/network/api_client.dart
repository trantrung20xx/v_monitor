// Lớp HTTP duy nhất của Flutter: gắn Bearer token, xử lý 401 và retry có backoff
// cho GET tạm lỗi. POST/PATCH không retry để tránh lặp thao tác ghi nghiệp vụ.
import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';

typedef UnauthorizedHandler = Future<void> Function();

class ApiClient {
  // Dio giữ cấu hình HTTP; tham số retry lấy từ AppConfig nhưng có thể inject trong
  // test. Token/callback thay đổi theo vòng đời đăng nhập.
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
    // Interceptor là điểm duy nhất gắn/xóa credential cho mọi repository, tránh
    // từng endpoint tự xây Authorization header khác nhau.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Đọc token tại đúng thời điểm request để lần đăng nhập/đăng xuất mới có hiệu lực ngay.
          final token = _accessToken;
          // Không tạo Authorization header khi chưa đăng nhập.
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          // Chuyển request tiếp tục qua các interceptor và adapter của Dio.
          handler.next(options);
        },
        onError: (error, handler) {
          // Chỉ phát tín hiệu thu hồi khi request đang dùng khóa đăng nhập.
          // Lỗi 401 của lần nhập sai mật khẩu không được coi là một lần bị ép thoát.
          if (error.response?.statusCode == 401 && _accessToken != null) {
            // Xóa token trước callback để request tiếp theo không tiếp tục gửi credential cũ.
            _accessToken = null;
            final callback = _unauthorizedHandler;
            // Callback chạy bất đồng bộ, không giữ luồng hoàn tất DioException hiện tại.
            if (callback != null) unawaited(callback());
          }
          // Lỗi vẫn được truyền cho repository/Cubit hiển thị hoặc xử lý theo nghiệp vụ.
          handler.next(error);
        },
      ),
    );
  }

  String get baseUrl => _dio.options.baseUrl;

  void setAccessToken(String? token) {
    // null/rỗng đều biểu diễn chưa đăng nhập và không tạo Bearer header rỗng.
    final normalized = token?.trim();
    // Token chỉ được giữ trong bộ nhớ của client; lưu bền thuộc AuthTokenStore.
    _accessToken = normalized == null || normalized.isEmpty ? null : normalized;
  }

  void setUnauthorizedHandler(UnauthorizedHandler? handler) {
    _unauthorizedHandler = handler;
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) {
    // Toàn bộ GET đi qua retry an toàn; phương thức ghi gọi Dio trực tiếp.
    return _getWithRetry(path, queryParameters: queryParameters);
  }

  Future<Response> post(String path, {dynamic data}) async {
    return _dio.post(path, data: data);
  }

  Future<Response> patch(String path, {dynamic data}) async {
    return _dio.patch(path, data: data);
  }

  Future<Response> delete(String path, {dynamic data}) async {
    return _dio.delete(path, data: data);
  }

  Future<Response> _getWithRetry(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    // retryIndex là số lần thử thêm; vòng lặp kết thúc bằng response thành công
    // hoặc rethrow đúng DioException cuối cho Cubit xử lý.
    var retryIndex = 0;
    while (true) {
      try {
        // Mỗi vòng lặp tạo một lần GET mới với cùng path/query.
        return await _dio.get(path, queryParameters: queryParameters);
      } on DioException catch (error) {
        // Dừng khi hết số lần thử hoặc loại lỗi không an toàn để retry.
        if (retryIndex >= _getRetryCount || !_canRetryGet(error)) {
          rethrow;
        }

        // Khoảng chờ tăng theo cấp số nhân để một đợt mất mạng hoặc lỗi 503
        // không khiến nhiều thiết bị đồng thời gửi lại request liên tục.
        // Chặn exponent ở 10 để phép dịch bit không tạo Duration quá lớn.
        final exponent = retryIndex > 10 ? 10 : retryIndex;
        final multiplier = 1 << exponent;
        // Tăng chỉ số sau khi đã tính delay cho lần retry sắp tới.
        retryIndex++;
        final delay = Duration(
          milliseconds: _retryDelay.inMilliseconds * multiplier,
        );
        // Delay bằng 0 được bỏ qua để test hoặc cấu hình retry tức thời.
        if (delay > Duration.zero) await Future<void>.delayed(delay);
      }
    }
  }

  bool _canRetryGet(DioException error) {
    // Chỉ lỗi mạng tạm thời hoặc HTTP có khả năng phục hồi mới retry. 4xx nghiệp vụ,
    // chứng chỉ sai, request hủy và lỗi không xác định được trả ngay.
    switch (error.type) {
      // Timeout và mất kết nối có thể phục hồi mà chưa nhận phản hồi nghiệp vụ.
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        // Chỉ retry các mã quá tải/gateway tạm thời; các lỗi 4xx khác phải trả ngay
        // vì lặp lại cùng request không sửa được dữ liệu đầu vào hay quyền truy cập.
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
        // Chứng chỉ sai và request bị hủy cần quyết định rõ từ caller, không tự lặp.
        return false;
    }
  }
}
