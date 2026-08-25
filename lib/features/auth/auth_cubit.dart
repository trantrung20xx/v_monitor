// Điều phối phiên đăng nhập: khôi phục token, tải người dùng, đăng nhập/đăng xuất,
// đổi mật khẩu và đồng bộ trạng thái HTTP với WebSocket.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/auth/auth_token_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/websocket_client.dart';
import '../../data/models/user_model.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  // Ba dependency dùng chung một credential: HTTP gọi REST, WebSocket nhận realtime
  // và tokenStore duy trì đăng nhập an toàn qua các lần mở ứng dụng.
  AuthCubit(this._apiClient, this._websocketClient, this._tokenStore)
    : super(const AuthState()) {
    _apiClient.setUnauthorizedHandler(_handleUnauthorized);
    _websocketClient.setUnauthorizedHandler(_handleUnauthorized);
  }

  final ApiClient _apiClient;
  final WebsocketClient _websocketClient;
  final AuthTokenStore _tokenStore;
  // Chặn nhiều callback 401 đồng thời cùng xóa token và phát state lặp.
  bool _clearingCredential = false;

  /// Khôi phục phiên đã lưu, xác minh token với backend rồi mới mở WebSocket.
  Future<void> initialize() async {
    emit(const AuthState(status: AuthStatus.checking));

    final String? storedToken;
    try {
      storedToken = await _tokenStore.readToken();
    } catch (_) {
      emit(
        const AuthState(
          status: AuthStatus.unauthenticated,
          message: 'Không thể đọc thông tin đăng nhập đã lưu trên máy.',
        ),
      );
      return;
    }

    if (storedToken == null || storedToken.trim().isEmpty) {
      // Không có token là trạng thái chưa đăng nhập bình thường, không phải lỗi server.
      _deactivateCredential();
      emit(const AuthState(status: AuthStatus.unauthenticated));
      return;
    }

    _activateCredential(storedToken);
    try {
      // `/auth/me` là bước xác minh token/version/quyền hiện vẫn hợp lệ.
      final response = await _apiClient.get('/auth/me');
      final user = UserModel.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      emit(AuthState(status: AuthStatus.authenticated, user: user));
      _websocketClient.connect();
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await _clearCredential(
          message: 'Thông tin đăng nhập đã bị thu hồi. Vui lòng đăng nhập lại.',
        );
        return;
      }
      _websocketClient.disconnect();
      emit(
        const AuthState(
          status: AuthStatus.serverUnavailable,
          message: 'Không thể kết nối máy chủ để xác thực tài khoản.',
        ),
      );
    } catch (_) {
      _websocketClient.disconnect();
      emit(
        const AuthState(
          status: AuthStatus.serverUnavailable,
          message: 'Dữ liệu tài khoản từ máy chủ không hợp lệ.',
        ),
      );
    }
  }

  /// Xác thực, lưu token bền vững, cập nhật state rồi mới kết nối realtime.
  Future<void> login(String username, String password) async {
    if (state.status == AuthStatus.authenticating) return;
    emit(const AuthState(status: AuthStatus.authenticating));

    try {
      final response = await _apiClient.post(
        '/auth/login',
        data: {'username': username.trim(), 'password': password},
      );
      final body = Map<String, dynamic>.from(response.data as Map);
      final token = body['access_token']?.toString().trim() ?? '';
      final userData = body['user'];
      if (token.isEmpty || userData is! Map) {
        throw const FormatException('Phản hồi đăng nhập thiếu dữ liệu');
      }

      // Khóa chỉ được kích hoạt sau khi đã ghi thành công vào kho bảo mật, bảo
      // đảm lần mở ứng dụng kế tiếp không rơi vào trạng thái đăng nhập dở dang.
      await _tokenStore.writeToken(token);
      _activateCredential(token);
      final user = UserModel.fromJson(Map<String, dynamic>.from(userData));
      emit(AuthState(status: AuthStatus.authenticated, user: user));
      _websocketClient.connect();
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      emit(
        AuthState(
          status: AuthStatus.unauthenticated,
          message: statusCode == 401
              ? 'Tên đăng nhập hoặc mật khẩu không chính xác.'
              : _responseMessage(
                  error,
                  'Không thể kết nối máy chủ để đăng nhập.',
                ),
        ),
      );
    } catch (_) {
      _deactivateCredential();
      emit(
        const AuthState(
          status: AuthStatus.unauthenticated,
          message: 'Không thể lưu thông tin đăng nhập an toàn trên máy.',
        ),
      );
    }
  }

  /// Tải lại tài khoản từ backend sau khi thông tin hồ sơ được cập nhật.
  /// Việc đọc lại `/auth/me` bảo đảm tên, email và quyền hiển thị luôn lấy từ
  /// nguồn đã xác thực thay vì tự sửa dữ liệu người dùng ở phía giao diện.
  Future<String?> refreshCurrentUser() async {
    if (!state.isAuthenticated) {
      return 'Tài khoản hiện tại chưa được xác thực.';
    }
    try {
      final response = await _apiClient.get('/auth/me');
      final user = UserModel.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      emit(AuthState(status: AuthStatus.authenticated, user: user));
      return null;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await _clearCredential(
          message: 'Thông tin đăng nhập đã bị thu hồi. Vui lòng đăng nhập lại.',
        );
      }
      return _responseMessage(error, 'Không thể tải lại thông tin tài khoản.');
    } catch (_) {
      return 'Dữ liệu tài khoản từ máy chủ không hợp lệ.';
    }
  }

  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _apiClient.post(
        '/auth/change-password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
      // Backend tăng token_version trong cùng giao dịch đổi mật khẩu. Khóa trên
      // máy hiện tại cũng phải bị xóa để mọi máy đăng nhập lại bằng mật khẩu mới.
      await _clearCredential(
        message: 'Mật khẩu đã thay đổi. Vui lòng đăng nhập lại.',
      );
      return null;
    } on DioException catch (error) {
      return _responseMessage(error, 'Không thể thay đổi mật khẩu.');
    } catch (_) {
      return 'Không thể thay đổi mật khẩu.';
    }
  }

  Future<void> logout() => _clearCredential();

  // HTTP và WebSocket cùng gọi nhánh này khi backend thu hồi credential.
  Future<void> _handleUnauthorized() {
    return _clearCredential(
      message: 'Thông tin đăng nhập đã bị thu hồi. Vui lòng đăng nhập lại.',
    );
  }

  void _activateCredential(String token) {
    // Cùng một token được gắn vào Bearer header HTTP và bản tin AUTH WebSocket.
    _apiClient.setAccessToken(token);
    _websocketClient.setAccessToken(token);
  }

  void _deactivateCredential() {
    // Xóa credential trong bộ nhớ trước và đóng socket để ngừng nhận dữ liệu bảo vệ.
    _apiClient.setAccessToken(null);
    _websocketClient.setAccessToken(null);
    _websocketClient.disconnect();
  }

  Future<void> _clearCredential({String? message}) async {
    if (_clearingCredential) return;
    _clearingCredential = true;
    _deactivateCredential();
    try {
      // Xóa kho bền vững để lần mở tiếp theo không thử lại token đã thu hồi.
      await _tokenStore.clearToken();
    } finally {
      _clearingCredential = false;
      emit(AuthState(status: AuthStatus.unauthenticated, message: message));
    }
  }

  static String _responseMessage(DioException error, String fallback) {
    // Ưu tiên thông điệp nghiệp vụ `detail`; fallback dùng cho lỗi mạng/response lạ.
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      final detail = data['detail'].toString().trim();
      if (detail.isNotEmpty) return detail;
    }
    return fallback;
  }

  @override
  Future<void> close() async {
    // Gỡ callback trước khi Cubit đóng để client dùng chung không emit vào state đã hủy.
    _apiClient.setUnauthorizedHandler(null);
    _websocketClient.setUnauthorizedHandler(null);
    _websocketClient.disconnect();
    await super.close();
  }
}
