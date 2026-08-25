// Hồ sơ tài khoản an toàn phía frontend: vai trò và quyền đăng nhập lấy từ backend;
// không có mật khẩu, hash hay logic tự nâng quyền.
class UserModel {
  // Hồ sơ tài khoản an toàn từ API; không bao giờ chứa password hash hoặc token.
  const UserModel({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.email,
  });

  final String id;
  final String username;
  final String fullName;
  final String? email;
  final String role;
  final bool isActive;

  bool get isAdmin => role == 'ADMIN';

  factory UserModel.fromJson(Map<String, dynamic> json) {
    // is_active quyết định quyền đăng nhập; role quyết định phạm vi thao tác sau xác thực.
    return UserModel(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      email: json['email']?.toString(),
      role: json['role']?.toString() ?? 'USER',
      isActive: json['is_active'] == true,
    );
  }
}
