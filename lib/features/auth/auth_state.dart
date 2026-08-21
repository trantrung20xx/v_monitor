import 'package:equatable/equatable.dart';

import '../../data/models/user_model.dart';

enum AuthStatus {
  checking,
  unauthenticated,
  authenticating,
  authenticated,
  serverUnavailable,
}

class AuthState extends Equatable {
  const AuthState({this.status = AuthStatus.checking, this.user, this.message});

  final AuthStatus status;
  final UserModel? user;
  final String? message;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  /// Chỉ cấp quyền quản trị phía giao diện sau khi luồng xác thực đã hoàn tất
  /// và thông tin tài khoản do backend trả về có vai trò ADMIN. Backend vẫn
  /// kiểm tra lại quyền ở từng API quản trị nên điều kiện này không thay thế
  /// cơ chế phân quyền phía máy chủ.
  bool get hasAdminAccess => isAuthenticated && user?.isAdmin == true;

  @override
  List<Object?> get props => [status, user, message];
}
