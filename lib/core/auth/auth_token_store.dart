import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class AuthTokenStore {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> clearToken();
}

class SecureAuthTokenStore implements AuthTokenStore {
  SecureAuthTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'v_monitor_access_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String token) {
    // Kho bảo mật của hệ điều hành giữ khóa đăng nhập ngoài file cấu hình thông
    // thường, hạn chế khả năng sao chép khóa khi máy trạm bị truy cập trái phép.
    return _storage.write(key: _tokenKey, value: token);
  }

  @override
  Future<void> clearToken() => _storage.delete(key: _tokenKey);
}
