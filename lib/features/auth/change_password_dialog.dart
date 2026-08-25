// Hộp thoại đổi mật khẩu của chính người dùng: kiểm tra nhập lại tại UI rồi giao
// AuthCubit xác minh mật khẩu hiện tại và thu hồi phiên theo nghiệp vụ backend.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme_colors.dart';
import 'auth_cubit.dart';

// Dialog đổi mật khẩu của tài khoản hiện tại; AuthCubit gọi backend và xóa phiên sau thành công.
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  // Ba controller không rời khỏi dialog; `_submitting` ngăn nhấn gửi nhiều lần.
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Form kiểm tra trường rỗng/khớp xác nhận trước, sau đó chuyển mật khẩu hiện tại
    // và mới tới AuthCubit. Thông báo backend được hiển thị tại `_error`.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await context.read<AuthCubit>().changePassword(
      currentPassword: _currentController.text,
      newPassword: _newController.text,
    );
    if (!mounted || error == null) return;
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    // SingleChildScrollView giữ đủ trường và nút hành động khi bàn phím mở trên mobile.
    return AlertDialog(
      title: const Text('Đổi mật khẩu'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Sau khi đổi mật khẩu, toàn bộ máy đang đăng nhập sẽ tự thoát và phải dùng mật khẩu mới.',
              ),
              const SizedBox(height: 18),
              TextFormField(
                key: const Key('current-password'),
                controller: _currentController,
                obscureText: true,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu hiện tại',
                ),
                validator: (value) => (value ?? '').isEmpty
                    ? 'Mật khẩu hiện tại không được để trống.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('new-password'),
                controller: _newController,
                obscureText: true,
                enabled: !_submitting,
                decoration: const InputDecoration(labelText: 'Mật khẩu mới'),
                validator: (value) => (value ?? '').length < 8
                    ? 'Mật khẩu mới phải có ít nhất 8 ký tự.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('confirm-password'),
                controller: _confirmController,
                obscureText: true,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  labelText: 'Xác nhận mật khẩu mới',
                ),
                validator: (value) => value != _newController.text
                    ? 'Mật khẩu xác nhận không trùng khớp.'
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(color: context.appColors.dangerStrong),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('change-password-submit'),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppPalette.onAccent,
                  ),
                )
              : const Text('Đổi mật khẩu'),
        ),
      ],
    );
  }
}
