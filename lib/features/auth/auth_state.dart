// Ảnh chụp bất biến của phiên xác thực. status mô tả vòng đời; currentUser chứa
// quyền thật từ backend; message chỉ phục vụ phản hồi giao diện.
import 'package:equatable/equatable.dart';

import '../../data/models/user_model.dart';

// Các trạng thái loại trừ nhau của vòng đời phiên đăng nhập.
enum AuthStatus {
  checking,
  unauthenticated,
  authenticating,
  authenticated,
  serverUnavailable,
}

class AuthState extends Equatable {
  // Không có copyWith vì mỗi chuyển trạng thái xác thực tạo một snapshot đầy đủ, rõ ràng.
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
