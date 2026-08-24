import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/app_menu.dart';
import '../../../data/models/user_model.dart';
import '../settings_cubit.dart';

enum _UserRoleFilter { all, member, admin }

enum _UserLoginFilter { all, allowed, blocked }

enum _UserFilterAction {
  roleAll,
  roleMember,
  roleAdmin,
  loginAll,
  loginAllowed,
  loginBlocked,
  reset,
}

class UserManagementCard extends StatefulWidget {
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
  State<UserManagementCard> createState() => _UserManagementCardState();
}

class _UserManagementCardState extends State<UserManagementCard> {
  final TextEditingController _searchController = TextEditingController();
  _UserRoleFilter _roleFilter = _UserRoleFilter.all;
  _UserLoginFilter _loginFilter = _UserLoginFilter.all;
  String _normalizedQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<UserModel> get _visibleUsers {
    return widget.users
        .where((user) {
          final matchesRole = switch (_roleFilter) {
            _UserRoleFilter.all => true,
            _UserRoleFilter.member => !user.isAdmin,
            _UserRoleFilter.admin => user.isAdmin,
          };
          if (!matchesRole) return false;
          final matchesLoginPermission = switch (_loginFilter) {
            _UserLoginFilter.all => true,
            _UserLoginFilter.allowed => user.isActive,
            _UserLoginFilter.blocked => !user.isActive,
          };
          if (!matchesLoginPermission) return false;
          if (_normalizedQuery.isEmpty) return true;
          final searchableText = _normalizeSearchText(
            '${user.fullName} ${user.username} ${user.email ?? ''}',
          );
          return searchableText.contains(_normalizedQuery);
        })
        .toList(growable: false);
  }

  void _updateSearch(String value) {
    setState(() => _normalizedQuery = _normalizeSearchText(value));
  }

  void _clearSearch() {
    _searchController.clear();
    _updateSearch('');
  }

  int get _activeFilterCount {
    return (_roleFilter == _UserRoleFilter.all ? 0 : 1) +
        (_loginFilter == _UserLoginFilter.all ? 0 : 1);
  }

  void _selectFilter(_UserFilterAction action) {
    setState(() {
      switch (action) {
        case _UserFilterAction.roleAll:
          _roleFilter = _UserRoleFilter.all;
        case _UserFilterAction.roleMember:
          _roleFilter = _UserRoleFilter.member;
        case _UserFilterAction.roleAdmin:
          _roleFilter = _UserRoleFilter.admin;
        case _UserFilterAction.loginAll:
          _loginFilter = _UserLoginFilter.all;
        case _UserFilterAction.loginAllowed:
          _loginFilter = _UserLoginFilter.allowed;
        case _UserFilterAction.loginBlocked:
          _loginFilter = _UserLoginFilter.blocked;
        case _UserFilterAction.reset:
          _roleFilter = _UserRoleFilter.all;
          _loginFilter = _UserLoginFilter.all;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleUsers = _visibleUsers;
    final memberCount = widget.users.where((user) => !user.isAdmin).length;
    final adminCount = widget.users.length - memberCount;
    final allowedLoginCount = widget.users
        .where((user) => user.isActive)
        .length;
    final blockedLoginCount = widget.users.length - allowedLoginCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.group_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quản lý người dùng',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.loading
                            ? 'Đang tải danh sách...'
                            : '${widget.users.length} tài khoản',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('reload-users-button'),
                  tooltip: 'Tải lại danh sách',
                  onPressed: widget.loading
                      ? null
                      : () => context.read<SettingsCubit>().loadUsers(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                const SizedBox(width: 2),
                IconButton.filledTonal(
                  key: const Key('create-user-button'),
                  tooltip: 'Thêm tài khoản',
                  onPressed: widget.operationInProgress
                      ? null
                      : () => showUserEditorDialog(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('user-search-field'),
                        controller: _searchController,
                        onChanged: _updateSearch,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Tìm theo tên, username hoặc email',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _normalizedQuery.isEmpty
                              ? null
                              : IconButton(
                                  key: const Key('clear-user-search'),
                                  tooltip: 'Xóa tìm kiếm',
                                  onPressed: _clearSearch,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _UserFilterMenuButton(
                      compact: constraints.maxWidth < 520,
                      activeFilterCount: _activeFilterCount,
                      totalCount: widget.users.length,
                      memberCount: memberCount,
                      adminCount: adminCount,
                      allowedLoginCount: allowedLoginCount,
                      blockedLoginCount: blockedLoginCount,
                      roleFilter: _roleFilter,
                      loginFilter: _loginFilter,
                      onSelected: _selectFilter,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            if (widget.loading)
              const LinearProgressIndicator(minHeight: 2)
            else if (widget.users.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Chưa có tài khoản để hiển thị.')),
              )
            else if (visibleUsers.isEmpty)
              Padding(
                key: const Key('user-filter-empty'),
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    Icon(
                      Icons.person_search_outlined,
                      size: 36,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Không tìm thấy tài khoản phù hợp.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ...visibleUsers.map((user) => _UserRow(user: user)),
          ],
        ),
      ),
    );
  }
}

class _UserFilterMenuButton extends StatelessWidget {
  const _UserFilterMenuButton({
    required this.compact,
    required this.activeFilterCount,
    required this.totalCount,
    required this.memberCount,
    required this.adminCount,
    required this.allowedLoginCount,
    required this.blockedLoginCount,
    required this.roleFilter,
    required this.loginFilter,
    required this.onSelected,
  });

  final bool compact;
  final int activeFilterCount;
  final int totalCount;
  final int memberCount;
  final int adminCount;
  final int allowedLoginCount;
  final int blockedLoginCount;
  final _UserRoleFilter roleFilter;
  final _UserLoginFilter loginFilter;
  final ValueChanged<_UserFilterAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasActiveFilters = activeFilterCount > 0;
    final tooltip = hasActiveFilters
        ? 'Bộ lọc người dùng ($activeFilterCount đang áp dụng)'
        : 'Bộ lọc người dùng';

    return PopupMenuButton<_UserFilterAction>(
      key: const Key('user-filter-button'),
      tooltip: tooltip,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 300),
      onSelected: onSelected,
      itemBuilder: (context) => [
        const PopupMenuItem<_UserFilterAction>(
          enabled: false,
          height: 34,
          padding: EdgeInsets.zero,
          child: _FilterMenuHeader(
            icon: Icons.badge_outlined,
            label: 'Vai trò',
          ),
        ),
        _menuItem(
          key: const Key('user-filter-all'),
          value: _UserFilterAction.roleAll,
          icon: Icons.people_outline_rounded,
          label: 'Mọi vai trò ($totalCount)',
          selected: roleFilter == _UserRoleFilter.all,
        ),
        _menuItem(
          key: const Key('user-filter-member'),
          value: _UserFilterAction.roleMember,
          icon: Icons.person_outline_rounded,
          label: 'Thành viên ($memberCount)',
          selected: roleFilter == _UserRoleFilter.member,
        ),
        _menuItem(
          key: const Key('user-filter-admin'),
          value: _UserFilterAction.roleAdmin,
          icon: Icons.admin_panel_settings_outlined,
          label: 'Quản trị viên ($adminCount)',
          selected: roleFilter == _UserRoleFilter.admin,
        ),
        const PopupMenuDivider(height: 10),
        const PopupMenuItem<_UserFilterAction>(
          enabled: false,
          height: 34,
          padding: EdgeInsets.zero,
          child: _FilterMenuHeader(
            icon: Icons.lock_outline_rounded,
            label: 'Quyền đăng nhập',
          ),
        ),
        _menuItem(
          key: const Key('user-login-filter-all'),
          value: _UserFilterAction.loginAll,
          icon: Icons.rule_rounded,
          label: 'Mọi quyền đăng nhập ($totalCount)',
          selected: loginFilter == _UserLoginFilter.all,
        ),
        _menuItem(
          key: const Key('user-login-filter-allowed'),
          value: _UserFilterAction.loginAllowed,
          icon: Icons.lock_open_rounded,
          label: 'Được phép ($allowedLoginCount)',
          selected: loginFilter == _UserLoginFilter.allowed,
        ),
        _menuItem(
          key: const Key('user-login-filter-blocked'),
          value: _UserFilterAction.loginBlocked,
          icon: Icons.lock_rounded,
          label: 'Đã chặn ($blockedLoginCount)',
          selected: loginFilter == _UserLoginFilter.blocked,
        ),
        if (hasActiveFilters) ...[
          const PopupMenuDivider(height: 10),
          _menuItem(
            key: const Key('user-filter-reset'),
            value: _UserFilterAction.reset,
            icon: Icons.filter_alt_off_outlined,
            label: 'Xóa bộ lọc',
            selected: false,
          ),
        ],
      ],
      child: Semantics(
        button: true,
        label: tooltip,
        child: Container(
          height: 56,
          constraints: compact
              ? const BoxConstraints.tightFor(width: 56)
              : const BoxConstraints(minWidth: 118),
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 16),
          decoration: BoxDecoration(
            color: hasActiveFilters
                ? colors.primaryContainer.withValues(alpha: 0.55)
                : colors.surfaceContainerLowest,
            border: Border.all(
              color: hasActiveFilters ? colors.primary : colors.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: compact
              ? Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 21,
                      color: hasActiveFilters
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    if (hasActiveFilters)
                      Positioned(
                        top: -7,
                        right: -7,
                        child: _FilterCountBadge(count: activeFilterCount),
                      ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 21,
                      color: hasActiveFilters
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Bộ lọc',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: hasActiveFilters
                            ? colors.primary
                            : colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasActiveFilters) ...[
                      const SizedBox(width: 8),
                      _FilterCountBadge(count: activeFilterCount),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  PopupMenuItem<_UserFilterAction> _menuItem({
    required Key key,
    required _UserFilterAction value,
    required IconData icon,
    required String label,
    required bool selected,
  }) {
    return PopupMenuItem<_UserFilterAction>(
      key: key,
      value: value,
      height: 44,
      padding: EdgeInsets.zero,
      child: AppMenuItem(
        icon: icon,
        label: label,
        selected: selected,
        trailing: selected
            ? const Icon(Icons.check_rounded)
            : const SizedBox(width: 18),
      ),
    );
  }
}

class _FilterCountBadge extends StatelessWidget {
  const _FilterCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('user-active-filter-count'),
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FilterMenuHeader extends StatelessWidget {
  const _FilterMenuHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _normalizeSearchText(String value) {
  var normalized = value.toLowerCase().trim();
  const replacements = <String, String>{
    'àáạảãâầấậẩẫăằắặẳẵ': 'a',
    'èéẹẻẽêềếệểễ': 'e',
    'ìíịỉĩ': 'i',
    'òóọỏõôồốộổỗơờớợởỡ': 'o',
    'ùúụủũưừứựửữ': 'u',
    'ỳýỵỷỹ': 'y',
    'đ': 'd',
  };
  for (final entry in replacements.entries) {
    for (final character in entry.key.characters) {
      normalized = normalized.replaceAll(character, entry.value);
    }
  }
  return normalized;
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.65),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          key: Key('managed-user-${user.id}'),
          contentPadding: const EdgeInsets.fromLTRB(12, 5, 4, 5),
          leading: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.onPrimaryContainer,
                    child: Text(
                      user.fullName.trim().isNotEmpty
                          ? user.fullName.trim().characters.first.toUpperCase()
                          : user.username.characters.first.toUpperCase(),
                    ),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: _LoginPermissionIndicator(
                    key: Key('user-login-status-${user.id}'),
                    allowed: user.isActive,
                  ),
                ),
              ],
            ),
          ),
          title: Text(
            user.fullName.trim().isNotEmpty ? user.fullName : user.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('@${user.username}'),
              _RoleBadge(
                text: user.isAdmin ? 'Quản trị viên' : 'Thành viên',
                color: colors.primary,
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            key: Key('user-actions-${user.id}'),
            tooltip: 'Thao tác tài khoản',
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
            onSelected: (action) {
              if (action == 'edit') {
                showUserEditorDialog(context, user: user);
              } else if (action == 'password') {
                _showResetPasswordDialog(context, user);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                height: 42,
                padding: EdgeInsets.zero,
                child: AppMenuItem(
                  icon: Icons.edit_outlined,
                  label: 'Sửa tài khoản',
                ),
              ),
              PopupMenuItem(
                value: 'password',
                height: 42,
                padding: EdgeInsets.zero,
                child: AppMenuItem(
                  icon: Icons.password_rounded,
                  label: 'Đặt lại mật khẩu',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginPermissionIndicator extends StatelessWidget {
  const _LoginPermissionIndicator({super.key, required this.allowed});

  final bool allowed;

  @override
  Widget build(BuildContext context) {
    // `isActive` là quyền đăng nhập, không phải trạng thái online theo thời gian thực.
    final colors = Theme.of(context).colorScheme;
    final label = allowed ? 'Được phép đăng nhập' : 'Không được phép đăng nhập';
    final color = allowed ? context.appColors.successStrong : colors.error;

    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        image: true,
        child: ExcludeSemantics(
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.surfaceContainerLowest,
                width: 2,
              ),
            ),
            child: Icon(
              allowed ? Icons.lock_open_rounded : Icons.lock_rounded,
              size: 11,
              color: AppPalette.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.text, required this.color});

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
  const _UserEditorDialog({this.user, this.profileOnly = false});

  final UserModel? user;
  final bool profileOnly;

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
      if (!widget.profileOnly) ...{'role': _role, 'is_active': _isActive},
    };
    final cubit = context.read<SettingsCubit>();
    final error = _isEditing
        ? await cubit.updateUser(
            widget.user!.id,
            data,
            refreshUsers: !widget.profileOnly,
          )
        : await cubit.createUser({
            ...data,
            'username': _usernameController.text.trim(),
            'password': _passwordController.text,
          });
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
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
      title: Text(
        widget.profileOnly
            ? 'Sửa thông tin tài khoản'
            : _isEditing
            ? 'Sửa tài khoản'
            : 'Thêm tài khoản',
      ),
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
                if (!widget.profileOnly) ...[
                  const SizedBox(height: 12),
                  _UserRoleSelector(
                    key: const Key('user-role-field'),
                    value: _role,
                    enabled: !_submitting,
                    onSelected: (value) => setState(() => _role = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cho phép đăng nhập'),
                    value: _isActive,
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _isActive = value),
                  ),
                ],
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
                    color: AppPalette.onAccent,
                  ),
                )
              : const Text('Lưu'),
        ),
      ],
    );
  }
}

/// Bộ chọn vai trò dùng cùng popup item với các danh sách lựa chọn của ứng dụng.
/// Giá trị nghiệp vụ vẫn giữ nguyên `USER` và `ADMIN` khi gửi lên backend.
class _UserRoleSelector extends StatelessWidget {
  const _UserRoleSelector({
    super.key,
    required this.value,
    required this.enabled,
    required this.onSelected,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isAdmin = value == 'ADMIN';
    final selectedLabel = isAdmin ? 'Quản trị viên' : 'Thành viên';
    final selectedIcon = isAdmin
        ? Icons.admin_panel_settings_outlined
        : Icons.person_outline_rounded;

    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: 'Chọn vai trò',
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
      onSelected: onSelected,
      itemBuilder: (context) => [
        _roleMenuItem(
          value: 'USER',
          label: 'Thành viên',
          icon: Icons.person_outline_rounded,
          selected: !isAdmin,
        ),
        _roleMenuItem(
          value: 'ADMIN',
          label: 'Quản trị viên',
          icon: Icons.admin_panel_settings_outlined,
          selected: isAdmin,
        ),
      ],
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: theme.inputDecorationTheme.fillColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(selectedIcon, size: 21, color: colors.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vai trò',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selectedLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _roleMenuItem({
    required String value,
    required String label,
    required IconData icon,
    required bool selected,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 48,
      padding: EdgeInsets.zero,
      child: AppMenuItem(
        icon: icon,
        label: label,
        selected: selected,
        touchTarget: true,
        trailing: selected
            ? const Icon(Icons.check_rounded)
            : const SizedBox(width: 18),
      ),
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
                    color: AppPalette.onAccent,
                  ),
                )
              : const Text('Đặt lại'),
        ),
      ],
    );
  }
}

Future<bool?> showUserEditorDialog(
  BuildContext context, {
  UserModel? user,
  bool profileOnly = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider.value(
      value: context.read<SettingsCubit>(),
      child: _UserEditorDialog(user: user, profileOnly: profileOnly),
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
