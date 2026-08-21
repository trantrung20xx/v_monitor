import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/user_model.dart';
import '../settings_cubit.dart';

class UserManagementCard extends StatelessWidget {
  const UserManagementCard({
    super.key,
    required this.users,
    required this.loading,
    required this.operationInProgress,
  });

  final List<UserModel> users;
  final bool loading;
  final bool operationInProgress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final title = Row(
                  children: [
                    Icon(
                      Icons.group_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Quản lý người dùng',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tải lại danh sách',
                      onPressed: loading
                          ? null
                          : () => context.read<SettingsCubit>().loadUsers(),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                );
                final createButton = FilledButton.icon(
                  key: const Key('create-user-button'),
                  onPressed: operationInProgress
                      ? null
                      : () => _showUserDialog(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Thêm tài khoản'),
                );
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [title, const SizedBox(height: 10), createButton],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 10),
                    createButton,
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Tài khoản do quản trị viên tạo; người dùng không thể tự đăng ký.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 16),
            if (loading)
              const LinearProgressIndicator(minHeight: 2)
            else if (users.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Chưa có tài khoản để hiển thị.')),
              )
            else
              ...users.map((user) => _UserRow(user: user)),
          ],
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          key: Key('managed-user-${user.id}'),
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: CircleAvatar(
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onPrimaryContainer,
            child: Text(
              user.fullName.trim().isNotEmpty
                  ? user.fullName.trim().characters.first.toUpperCase()
                  : user.username.characters.first.toUpperCase(),
            ),
          ),
          title: Text(
            user.fullName.trim().isNotEmpty ? user.fullName : user.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('@${user.username}'),
              _StatusLabel(
                text: user.isAdmin ? 'Quản trị viên' : 'Người dùng',
                color: colors.primary,
              ),
              _StatusLabel(
                text: user.isActive ? 'Đang hoạt động' : 'Đã khóa',
                color: user.isActive ? const Color(0xFF15803D) : colors.error,
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            key: Key('user-actions-${user.id}'),
            tooltip: 'Thao tác tài khoản',
            onSelected: (action) {
              if (action == 'edit') {
                _showUserDialog(context, user: user);
              } else if (action == 'password') {
                _showResetPasswordDialog(context, user);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Sửa tài khoản'),
                ),
              ),
              PopupMenuItem(
                value: 'password',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.password_rounded),
                  title: Text('Đặt lại mật khẩu'),
                ),
              ),
            ],
          ),
        ),
        const Divider(),
      ],
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _UserEditorDialog extends StatefulWidget {
  const _UserEditorDialog({this.user});

  final UserModel? user;

  @override
  State<_UserEditorDialog> createState() => _UserEditorDialogState();
}

class _UserEditorDialogState extends State<_UserEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _fullNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late String _role;
  late bool _isActive;
  bool _submitting = false;
  String? _error;

  bool get _isEditing => widget.user != null;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _usernameController = TextEditingController(text: user?.username ?? '');
    _fullNameController = TextEditingController(text: user?.fullName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _passwordController = TextEditingController();
    _role = user?.role ?? 'USER';
    _isActive = user?.isActive ?? true;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    final data = <String, dynamic>{
      'full_name': _fullNameController.text.trim(),
      'email': email.isEmpty ? null : email,
      'role': _role,
      'is_active': _isActive,
    };
    final cubit = context.read<SettingsCubit>();
    final error = _isEditing
        ? await cubit.updateUser(widget.user!.id, data)
        : await cubit.createUser({
            ...data,
            'username': _usernameController.text.trim(),
            'password': _passwordController.text,
          });
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Sửa tài khoản' : 'Thêm tài khoản'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('user-username-field'),
                  controller: _usernameController,
                  enabled: !_isEditing && !_submitting,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (value) => (value ?? '').trim().length < 3
                      ? 'Username phải có ít nhất 3 ký tự.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('user-full-name-field'),
                  controller: _fullNameController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(labelText: 'Họ tên'),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Họ tên không được để trống.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('user-email-field'),
                  controller: _emailController,
                  enabled: !_submitting,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (không bắt buộc)',
                  ),
                ),
                if (!_isEditing) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('user-password-field'),
                    controller: _passwordController,
                    enabled: !_submitting,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu ban đầu',
                    ),
                    validator: (value) => (value ?? '').length < 8
                        ? 'Mật khẩu phải có ít nhất 8 ký tự.'
                        : null,
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('user-role-field'),
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Vai trò'),
                  items: const [
                    DropdownMenuItem(value: 'USER', child: Text('Người dùng')),
                    DropdownMenuItem(
                      value: 'ADMIN',
                      child: Text('Quản trị viên'),
                    ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _role = value ?? 'USER'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cho phép đăng nhập'),
                  value: _isActive,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _isActive = value),
                ),
                if (_error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('save-user-button'),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Lưu'),
        ),
      ],
    );
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.user});

  final UserModel user;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await context.read<SettingsCubit>().resetUserPassword(
      widget.user.id,
      _passwordController.text,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Đặt lại mật khẩu'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tài khoản: ${widget.user.username}'),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('reset-password-field'),
                controller: _passwordController,
                obscureText: true,
                enabled: !_submitting,
                decoration: const InputDecoration(labelText: 'Mật khẩu mới'),
                validator: (value) => (value ?? '').length < 8
                    ? 'Mật khẩu phải có ít nhất 8 ký tự.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('reset-password-confirmation'),
                controller: _confirmationController,
                obscureText: true,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  labelText: 'Xác nhận mật khẩu mới',
                ),
                validator: (value) => value != _passwordController.text
                    ? 'Mật khẩu xác nhận không trùng khớp.'
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
          key: const Key('reset-password-button'),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Đặt lại'),
        ),
      ],
    );
  }
}

Future<void> _showUserDialog(BuildContext context, {UserModel? user}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider.value(
      value: context.read<SettingsCubit>(),
      child: _UserEditorDialog(user: user),
    ),
  );
}

Future<void> _showResetPasswordDialog(BuildContext context, UserModel user) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider.value(
      value: context.read<SettingsCubit>(),
      child: _ResetPasswordDialog(user: user),
    ),
  );
}
