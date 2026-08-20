import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/auth/auth_token_store.dart';
import '../../core/network/api_client.dart';
import '../../core/network/websocket_client.dart';
import '../../data/models/user_model.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._apiClient, this._websocketClient, this._tokenStore)
    : super(const AuthState()) {
    _apiClient.setUnauthorizedHandler(_handleUnauthorized);
    _websocketClient.setUnauthorizedHandler(_handleUnauthorized);
  }

  final ApiClient _apiClient;
  final WebsocketClient _websocketClient;
  final AuthTokenStore _tokenStore;
  bool _clearingCredential = false;

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
      _deactivateCredential();
      emit(const AuthState(status: AuthStatus.unauthenticated));
      return;
    }

    _activateCredential(storedToken);
    try {
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

  Future<void> _handleUnauthorized() {
    return _clearCredential(
      message: 'Thông tin đăng nhập đã bị thu hồi. Vui lòng đăng nhập lại.',
    );
  }

  void _activateCredential(String token) {
    _apiClient.setAccessToken(token);
    _websocketClient.setAccessToken(token);
  }

  void _deactivateCredential() {
    _apiClient.setAccessToken(null);
    _websocketClient.setAccessToken(null);
    _websocketClient.disconnect();
  }

  Future<void> _clearCredential({String? message}) async {
    if (_clearingCredential) return;
    _clearingCredential = true;
    _deactivateCredential();
    try {
      await _tokenStore.clearToken();
    } finally {
      _clearingCredential = false;
      emit(AuthState(status: AuthStatus.unauthenticated, message: message));
    }
  }

  static String _responseMessage(DioException error, String fallback) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      final detail = data['detail'].toString().trim();
      if (detail.isNotEmpty) return detail;
    }
    return fallback;
  }

  @override
  Future<void> close() async {
    _apiClient.setUnauthorizedHandler(null);
    _websocketClient.setUnauthorizedHandler(null);
    _websocketClient.disconnect();
    await super.close();
  }
}
