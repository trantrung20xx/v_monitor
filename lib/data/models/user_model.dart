class UserModel {
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
