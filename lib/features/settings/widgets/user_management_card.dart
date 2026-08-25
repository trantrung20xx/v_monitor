// Giao diện quản trị tài khoản: tìm kiếm, lọc vai trò/quyền đăng nhập, tạo/sửa,
// bật/tạm khóa và reset mật khẩu; mọi thao tác ghi vẫn phải qua API ADMIN.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/app_menu.dart';
import '../../../data/models/user_model.dart';
import '../settings_cubit.dart';

// Hai chiều lọc độc lập: vai trò nghiệp vụ và quyền đăng nhập hiện tại.
enum _UserRoleFilter { all, member, admin }

enum _UserLoginFilter { all, allowed, blocked }

// Action của popup gộp cả hai nhóm để không chiếm hai hàng bộ lọc trên giao diện.
enum _UserFilterAction {
  roleAll,
  roleMember,
  roleAdmin,
  loginAll,
  loginAllowed,
  loginBlocked,
  reset,
}

// Khối quản trị tài khoản dành cho ADMIN. Danh sách UserModel lấy từ SettingsState;
// widget chỉ tìm kiếm/lọc và chuyển thao tác tạo/sửa/reset về SettingsCubit.
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
  // SearchController và hai filter là state trình bày cục bộ, không ghi xuống server.
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
    // Chuẩn hóa không dấu/chữ thường rồi áp dụng vai trò, quyền đăng nhập và từ khóa.
    // `isActive` là dữ liệu thật từ backend, không suy ra theo trạng thái online.
    return widget.users
        .where((user) {
          // Vai trò lấy từ role thật; isAdmin chỉ là getter đọc role == ADMIN.
          final matchesRole = switch (_roleFilter) {
            _UserRoleFilter.all => true,
            _UserRoleFilter.member => !user.isAdmin,
            _UserRoleFilter.admin => user.isAdmin,
          };
          // Loại sai vai trò trước khi xét quyền và từ khóa.
          if (!matchesRole) return false;
          // Quyền đăng nhập đọc trực tiếp isActive do backend quản lý.
          final matchesLoginPermission = switch (_loginFilter) {
            _UserLoginFilter.all => true,
            _UserLoginFilter.allowed => user.isActive,
            _UserLoginFilter.blocked => !user.isActive,
          };
          // Tài khoản sai quyền đăng nhập không tham gia tìm kiếm text.
          if (!matchesLoginPermission) return false;
          // Từ khóa rỗng giữ toàn bộ tài khoản đã qua hai bộ lọc.
          if (_normalizedQuery.isEmpty) return true;
          // Ghép ba trường nhận diện thành một chuỗi chuẩn hóa để tìm một lần.
          final searchableText = _normalizeSearchText(
            '${user.fullName} ${user.username} ${user.email ?? ''}',
          );
          return searchableText.contains(_normalizedQuery);
        })
        .toList(growable: false);
  }

  void _updateSearch(String value) {
    // Chỉ rebuild khi chuỗi chuẩn hóa thay đổi để tránh dựng lại không cần thiết.
    setState(() => _normalizedQuery = _normalizeSearchText(value));
  }

  void _clearSearch() {
    _searchController.clear();
    _updateSearch('');
  }

  int get _activeFilterCount {
    // Badge đếm số chiều lọc khác `all`, không phải số tài khoản khớp.
    return (_roleFilter == _UserRoleFilter.all ? 0 : 1) +
        (_loginFilter == _UserLoginFilter.all ? 0 : 1);
  }

  void _selectFilter(_UserFilterAction action) {
    // Một popup cập nhật đúng nhóm filter; lựa chọn Xóa bộ lọc đặt lại cả hai nhóm.
    // Toàn bộ switch nằm trong một setState để mỗi lựa chọn chỉ rebuild một lần.
    setState(() {
      switch (action) {
        // Nhóm role chỉ thay _roleFilter và giữ nguyên lựa chọn quyền đăng nhập.
        case _UserFilterAction.roleAll:
          _roleFilter = _UserRoleFilter.all;
        case _UserFilterAction.roleMember:
          _roleFilter = _UserRoleFilter.member;
        case _UserFilterAction.roleAdmin:
          _roleFilter = _UserRoleFilter.admin;
        // Nhóm login chỉ thay _loginFilter và giữ nguyên lựa chọn vai trò.
        case _UserFilterAction.loginAll:
          _loginFilter = _UserLoginFilter.all;
        case _UserFilterAction.loginAllowed:
          _loginFilter = _UserLoginFilter.allowed;
        case _UserFilterAction.loginBlocked:
          _loginFilter = _UserLoginFilter.blocked;
        // Reset đồng thời đưa cả hai chiều lọc về `all`.
        case _UserFilterAction.reset:
          _roleFilter = _UserRoleFilter.all;
          _loginFilter = _UserLoginFilter.all;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Header chứa tìm kiếm, lọc và nút thêm; phần dưới chỉ dựng danh sách đã lọc
    // hoặc trạng thái rỗng để giữ cấu trúc dễ quét trên màn hình hẹp.
    final visibleUsers = _visibleUsers;
    // Các bộ đếm luôn tính từ danh sách gốc để menu lọc không đổi số theo chính filter.
    final memberCount = widget.users.where((user) => !user.isAdmin).length;
    final adminCount = widget.users.length - memberCount;
    final allowedLoginCount = widget.users
        .where((user) => user.isActive)
        .length;
    final blockedLoginCount = widget.users.length - allowedLoginCount;
    // Card bao toàn bộ tiêu đề, thanh công cụ và danh sách để giữ một vùng quản trị nhất quán.
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hàng đầu hiển thị tiêu đề/tổng số bên trái và hai thao tác bên phải.
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
                      // Trong lúc tải, khóa refresh để không gửi request danh sách trùng.
                      ? null
                      : () => context.read<SettingsCubit>().loadUsers(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                const SizedBox(width: 2),
                IconButton.filledTonal(
                  key: const Key('create-user-button'),
                  tooltip: 'Thêm tài khoản',
                  onPressed: widget.operationInProgress
                      // Trong thao tác ghi, khóa form mới để tránh hai operation chồng nhau.
                      ? null
                      : () => showUserEditorDialog(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                // Ô tìm kiếm chiếm phần co giãn; menu lọc chỉ rút về icon dưới 520 px.
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
                              // Không dựng nút xóa khi query rỗng để giảm chiếm chỗ.
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
            // Các nhánh dưới loại trừ nhau theo ưu tiên: loading → nguồn rỗng → lọc rỗng → danh sách.
            if (widget.loading)
              const LinearProgressIndicator(minHeight: 2)
            else if (widget.users.isEmpty)
              // Nguồn rỗng nghĩa API chưa có tài khoản để quản trị.
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Chưa có tài khoản để hiển thị.')),
              )
            else if (visibleUsers.isEmpty)
              // Nguồn có dữ liệu nhưng không khớp bộ lọc/từ khóa hiện tại.
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
              // Chỉ map danh sách đã lọc; mỗi row nhận đúng một UserModel.
              ...visibleUsers.map((user) => _UserRow(user: user)),
          ],
        ),
      ),
    );
  }
}

// Nút popup lọc kết hợp vai trò và quyền đăng nhập để tối ưu không gian.
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
    // Popup chia mục bằng header nhỏ; checked item thể hiện giá trị đang áp dụng và
    // badge ngoài nút cho biết có bao nhiêu nhóm lọc hoạt động.
    final colors = Theme.of(context).colorScheme;
    // Badge/nền active chỉ bật khi ít nhất một trong hai nhóm khác `all`.
    final hasActiveFilters = activeFilterCount > 0;
    final tooltip = hasActiveFilters
        ? 'Bộ lọc người dùng ($activeFilterCount đang áp dụng)'
        : 'Bộ lọc người dùng';

    // Popup chia nhóm bằng item disabled để header không thể bị chọn như một filter.
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
        // Hành động reset chỉ xuất hiện khi thực sự có filter cần xóa.
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
      // Semantics mô tả nút và số filter cho trình đọc màn hình ở cả hai dạng.
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
              // Mobile dùng icon và badge Positioned để giữ chiều rộng 56 px.
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
              // Desktop hiển thị icon, chữ và badge trong một hàng dễ đọc.
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

// Badge số bộ lọc đang bật, không lặp lại toàn bộ tên bộ lọc trên thanh công cụ.
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

// Tiêu đề phân nhóm trong popup, không phải lựa chọn có thể nhấn.
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
  // Bỏ dấu tiếng Việt và chuyển chữ thường để tìm tên thân thiện hơn; dữ liệu gốc
  // trong UserModel không bị thay đổi.
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
  // Thay từng ký tự có dấu bằng chữ cơ sở để tìm tên tiếng Việt không cần gõ dấu.
  for (final entry in replacements.entries) {
    for (final character in entry.key.characters) {
      normalized = normalized.replaceAll(character, entry.value);
    }
  }
  return normalized;
}

// Một dòng tài khoản hiển thị định danh, vai trò, quyền đăng nhập và thao tác.
// Mọi giá trị lấy trực tiếp từ UserModel do API trả về.
class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    // Layout co giãn giữ badge và nút thao tác không ép tên/email hoặc gây overflow.
    final colors = Theme.of(context).colorScheme;
    // Mỗi tài khoản là một surface riêng với viền nhẹ để quét danh sách dài.
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
            // Stack chồng avatar định danh với icon quyền đăng nhập ở góc dưới.
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
                      // Ưu tiên chữ đầu họ tên; fallback username khi fullName rỗng.
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
            // Tên dài bị ellipsis trong một dòng để trailing menu luôn còn chỗ.
            user.fullName.trim().isNotEmpty ? user.fullName : user.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          // Wrap cho username và badge vai trò tự xuống dòng khi màn hình hẹp.
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
            // Popup gom sửa hồ sơ và reset mật khẩu để hàng không có nhiều nút lẻ.
            key: Key('user-actions-${user.id}'),
            tooltip: 'Thao tác tài khoản',
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
            onSelected: (action) {
              // Chuỗi action chỉ tồn tại cục bộ trong menu, không gửi lên backend.
              if (action == 'edit') {
                showUserEditorDialog(context, user: user);
              } else if (action == 'password') {
                // Reset password dùng dialog riêng để không trộn mật khẩu với form hồ sơ.
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

// Chỉ báo ngắn bằng icon/màu cho `isActive`; tooltip cung cấp diễn giải đầy đủ.
class _LoginPermissionIndicator extends StatelessWidget {
  const _LoginPermissionIndicator({super.key, required this.allowed});

  final bool allowed;

  @override
  Widget build(BuildContext context) {
    // `isActive` là quyền đăng nhập, không phải trạng thái online theo thời gian thực.
    final colors = Theme.of(context).colorScheme;
    // Label đầy đủ nằm trong tooltip/semantics; item chỉ hiện icon ngắn gọn.
    final label = allowed ? 'Được phép đăng nhập' : 'Không được phép đăng nhập';
    // Màu success/error lấy từ theme hiện tại, không hard-code mã màu.
    final color = allowed ? context.appColors.successStrong : colors.error;

    // ExcludeSemantics ngăn Icon đọc tên kỹ thuật thêm lần nữa sau label bên ngoài.
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

// Badge vai trò USER/ADMIN dùng palette theme, tách biệt với quyền đăng nhập.
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

// Dialog tạo hoặc sửa tài khoản. `profileOnly` chỉ cho sửa hồ sơ cá nhân;
// ngữ cảnh quản trị mới hiển thị vai trò và quyền đăng nhập.
class _UserEditorDialog extends StatefulWidget {
  const _UserEditorDialog({this.user, this.profileOnly = false});

  final UserModel? user;
  final bool profileOnly;

  @override
  State<_UserEditorDialog> createState() => _UserEditorDialogState();
}

class _UserEditorDialogState extends State<_UserEditorDialog> {
  // Controller giữ dữ liệu form; role/active khởi tạo từ UserModel và chỉ được gửi
  // khi form đang ở ngữ cảnh quản trị phù hợp.
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
    // Khi sửa, controller lấy snapshot UserModel; khi tạo, các ô bắt đầu rỗng.
    final user = widget.user;
    _usernameController = TextEditingController(text: user?.username ?? '');
    _fullNameController = TextEditingController(text: user?.fullName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _passwordController = TextEditingController();
    // Tài khoản mới mặc định thành viên và được phép đăng nhập.
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
    // Form tạo yêu cầu mật khẩu; form sửa không gửi mật khẩu. Cubit chờ backend ghi
    // audit và kiểm tra quản trị viên cuối cùng trước khi dialog đóng.
    // Guard ngăn double-click và chỉ gửi khi toàn bộ validator trả null.
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    // Payload nền luôn chứa họ tên/email; email rỗng được gửi null để xóa giá trị cũ.
    final data = <String, dynamic>{
      'full_name': _fullNameController.text.trim(),
      'email': email.isEmpty ? null : email,
      if (!widget.profileOnly) ...{'role': _role, 'is_active': _isActive},
    };
    final cubit = context.read<SettingsCubit>();
    // Chế độ sửa dùng PATCH; chế độ tạo bổ sung username và mật khẩu cho POST.
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
    // Dialog có thể đã đóng trong lúc chờ API nên phải kiểm tra mounted trước setState/pop.
    if (!mounted) return;
    // true báo caller profileOnly rằng hồ sơ đã lưu và cần làm mới AuthCubit.
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    // Lỗi nghiệp vụ được giữ ngay trong dialog và mở lại nút gửi.
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Nội dung dialog cuộn dọc và co theo màn hình để bàn phím không cắt trường
    // nhập hoặc nút Lưu.
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
                  // Username chỉ chỉnh khi tạo; backend không hỗ trợ đổi username qua PATCH này.
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
                // Mật khẩu ban đầu chỉ tồn tại ở form tạo và không nằm trong form sửa hồ sơ.
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
                // profileOnly ẩn role/isActive để người dùng không tự nâng quyền.
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
// Bộ chọn vai trò trình bày hai lựa chọn dễ hiểu; giá trị gửi vẫn là USER/ADMIN.
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
    // Nhãn/icon thân thiện chỉ dùng hiển thị; value gửi backend vẫn giữ enum tiếng Anh.
    final selectedLabel = isAdmin ? 'Quản trị viên' : 'Thành viên';
    final selectedIcon = isAdmin
        ? Icons.admin_panel_settings_outlined
        : Icons.person_outline_rounded;

    // PopupMenuButton bị disable cùng form khi request đang gửi.
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
      // value USER/ADMIN được trả cho onSelected; AppMenuItem chỉ quyết định trình bày.
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

// Dialog đặt mật khẩu mới cho tài khoản mục tiêu, được mở từ hàng người dùng của ADMIN.
class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.user});

  final UserModel user;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  // Hai controller dùng để xác nhận nhập lại; mật khẩu không đưa vào state ứng dụng.
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
    // Kiểm tra độ khớp tại client để phản hồi nhanh; backend vẫn áp dụng policy và
    // tăng token_version nhằm thu hồi mọi phiên cũ của tài khoản.
    // Guard ngăn gửi lặp và chỉ chạy khi độ dài/xác nhận đã hợp lệ.
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    // Mật khẩu chỉ được truyền trực tiếp vào Cubit, không đưa vào SettingsState.
    final error = await context.read<SettingsCubit>().resetUserPassword(
      widget.user.id,
      _passwordController.text,
    );
    // Dialog có thể bị route đóng trong lúc request đang chạy.
    if (!mounted) return;
    // Thành công đóng dialog; không hiển thị lại mật khẩu hoặc thông báo chứa mật khẩu.
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    // Lỗi backend được hiển thị và cho phép gửi lại sau khi sửa.
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
    // Không cho đóng bằng chạm nền để tránh mất dữ liệu form ngoài ý muốn.
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
      // Dialog dùng đúng SettingsCubit của trang thay vì tạo instance rỗng mới.
      value: context.read<SettingsCubit>(),
      child: _ResetPasswordDialog(user: user),
    ),
  );
}
