import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/config/map_tile_providers.dart';
import '../../data/models/user_model.dart';
import '../../data/models/user_settings_model.dart';
import '../auth/auth_cubit.dart';
import '../auth/change_password_dialog.dart';
import 'settings_cubit.dart';
import 'settings_state.dart';
import 'widgets/tracking_settings_card.dart';
import 'widgets/user_management_card.dart';

enum SettingsSection { overview, personal, account, about, tracking, users }

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.section});

  // Nullable để instance được giữ lại qua hot reload từ phiên bản cũ không
  // làm ứng dụng crash; giá trị thiếu luôn được quy về trang tổng quan.
  final SettingsSection? section;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _usersRequested = false;

  SettingsSection get _requestedSection =>
      widget.section ?? SettingsSection.overview;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settingsCubit = context.read<SettingsCubit>();
    if (settingsCubit.state.status == SettingsLoadStatus.initial) {
      settingsCubit.initialize();
    }
    if (!_usersRequested &&
        _requestedSection == SettingsSection.users &&
        context.read<AuthCubit>().state.hasAdminAccess) {
      _usersRequested = true;
      settingsCubit.loadUsers();
    }
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.section ?? SettingsSection.overview) != _requestedSection) {
      _usersRequested = false;
      if (_requestedSection == SettingsSection.users &&
          context.read<AuthCubit>().state.hasAdminAccess) {
        _usersRequested = true;
        context.read<SettingsCubit>().loadUsers();
      }
    }
  }

  Future<void> _reload(bool hasAdminAccess) async {
    await context.read<SettingsCubit>().initialize();
    if (_requestedSection == SettingsSection.users &&
        hasAdminAccess &&
        mounted) {
      await context.read<SettingsCubit>().loadUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final user = authState.user;
    final hasAdminAccess = authState.hasAdminAccess;
    final requestedSection = _requestedSection;
    final visibleSection = _isAdminSection(requestedSection) && !hasAdminAccess
        ? SettingsSection.overview
        : requestedSection;
    return Scaffold(
      appBar: AppBar(
        leading: visibleSection == SettingsSection.overview
            ? null
            : IconButton(
                tooltip: 'Quay lại Cài đặt',
                onPressed: () => context.goNamed('settings'),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(_sectionTitle(visibleSection)),
        actions: [
          IconButton(
            tooltip: 'Tải lại cài đặt',
            onPressed: () => _reload(hasAdminAccess),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: BlocConsumer<SettingsCubit, SettingsState>(
        listenWhen: (previous, current) =>
            previous.message != current.message && current.message != null,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.message!)));
        },
        builder: (context, state) {
          return _SettingsSectionView(
            section: visibleSection,
            state: state,
            user: user,
            hasAdminAccess: hasAdminAccess,
            onRefresh: () => _reload(hasAdminAccess),
          );
        },
      ),
    );
  }
}

bool _isAdminSection(SettingsSection section) =>
    section == SettingsSection.tracking || section == SettingsSection.users;

String _sectionTitle(SettingsSection section) => switch (section) {
  SettingsSection.overview => 'Cài đặt',
  SettingsSection.personal => 'Giao diện & hiển thị',
  SettingsSection.account => 'Tài khoản & bảo mật',
  SettingsSection.about => 'Thông tin phần mềm',
  SettingsSection.tracking => 'Theo dõi thiết bị',
  SettingsSection.users => 'Quản lý người dùng',
};

class _SettingsSectionView extends StatelessWidget {
  const _SettingsSectionView({
    required this.section,
    required this.state,
    required this.user,
    required this.hasAdminAccess,
    required this.onRefresh,
  });

  final SettingsSection section;
  final SettingsState state;
  final UserModel? user;
  final bool hasAdminAccess;
  final RefreshCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth >= 900 ? 32.0 : 16.0;
        final maxWidth = section == SettingsSection.users ? 1120.0 : 840.0;
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              20,
              horizontalPadding,
              32,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.status == SettingsLoadStatus.loading)
                        const LinearProgressIndicator(minHeight: 2),
                      if (state.status == SettingsLoadStatus.error) ...[
                        _LoadErrorBanner(message: state.message),
                        const SizedBox(height: 16),
                      ],
                      if (section == SettingsSection.overview)
                        _SettingsOverview(hasAdminAccess: hasAdminAccess)
                      else
                        _sectionContent(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionContent() => switch (section) {
    SettingsSection.personal => _PersonalSettingsCard(state: state),
    SettingsSection.account => _AccountSettingsCard(
      user: user,
      hasAdminAccess: hasAdminAccess,
      operationInProgress: state.userOperationInProgress,
    ),
    SettingsSection.about => const _SoftwareInformationCard(),
    SettingsSection.tracking => TrackingSettingsCard(
      settings: state.systemSettings,
      saving: state.systemSaving,
    ),
    SettingsSection.users => UserManagementCard(
      users: state.users,
      loading: state.usersLoading,
      operationInProgress: state.userOperationInProgress,
    ),
    SettingsSection.overview => const SizedBox.shrink(),
  };
}

class _SettingsOverview extends StatelessWidget {
  const _SettingsOverview({required this.hasAdminAccess});

  final bool hasAdminAccess;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SettingsGroupTitle(title: 'Cá nhân'),
        const SizedBox(height: 10),
        _SettingsDestinationGrid(
          destinations: const [
            _SettingsDestination(
              keyName: 'settings-section-personal',
              routeName: 'settings-personal',
              title: 'Giao diện & hiển thị',
              description: 'Chủ đề, loại bản đồ và đơn vị tốc độ',
              icon: Icons.palette_outlined,
            ),
            _SettingsDestination(
              keyName: 'settings-section-account',
              routeName: 'settings-account',
              title: 'Tài khoản & bảo mật',
              description: 'Thông tin tài khoản, mật khẩu và đăng xuất',
              icon: Icons.manage_accounts_outlined,
            ),
          ],
        ),
        // Các widget quản trị chỉ được tạo khi AuthState đã xác thực quyền
        // ADMIN; không phải cơ chế ẩn giao diện sau khi widget đã dựng.
        if (hasAdminAccess) ...[
          const SizedBox(height: 28),
          const _SettingsGroupTitle(title: 'Quản trị'),
          const SizedBox(height: 10),
          _SettingsDestinationGrid(
            destinations: const [
              _SettingsDestination(
                keyName: 'settings-section-tracking',
                routeName: 'settings-tracking',
                title: 'Theo dõi thiết bị',
                description: 'Ngưỡng ngoại tuyến, chuyển động và hành trình',
                icon: Icons.sensors_rounded,
              ),
              _SettingsDestination(
                keyName: 'settings-section-users',
                routeName: 'settings-users',
                title: 'Quản lý người dùng',
                description: 'Tài khoản, vai trò và quyền truy cập',
                icon: Icons.admin_panel_settings_outlined,
              ),
            ],
          ),
        ],
        const SizedBox(height: 28),
        const _SettingsGroupTitle(title: 'Thông tin'),
        const SizedBox(height: 10),
        _SettingsDestinationGrid(
          destinations: const [
            _SettingsDestination(
              keyName: 'settings-section-about',
              routeName: 'settings-about',
              title: 'Thông tin phần mềm',
              description: 'Biểu tượng, phiên bản và thông tin ứng dụng',
              icon: Icons.info_outline_rounded,
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsDestination {
  const _SettingsDestination({
    required this.keyName,
    required this.routeName,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String keyName;
  final String routeName;
  final String title;
  final String description;
  final IconData icon;
}

class _SettingsDestinationGrid extends StatelessWidget {
  const _SettingsDestinationGrid({required this.destinations});

  final List<_SettingsDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: destinations.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 126,
          ),
          itemBuilder: (context, index) {
            final destination = destinations[index];
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: Key(destination.keyName),
                onTap: () => context.pushNamed(destination.routeName),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          destination.icon,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              destination.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              destination.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SettingsGroupTitle extends StatelessWidget {
  const _SettingsGroupTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _PersonalSettingsCard extends StatelessWidget {
  const _PersonalSettingsCard({required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return _SettingsCard(
      title: 'Cá nhân',
      icon: Icons.tune_rounded,
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            key: const Key('theme-setting'),
            isExpanded: true,
            initialValue: state.userSettings.theme,
            decoration: const InputDecoration(
              labelText: 'Giao diện',
              prefixIcon: Icon(Icons.palette_outlined),
            ),
            items: const [
              DropdownMenuItem(value: 'system', child: Text('Theo hệ thống')),
              DropdownMenuItem(value: 'light', child: Text('Sáng')),
              DropdownMenuItem(value: 'dark', child: Text('Tối')),
            ],
            onChanged: state.personalSaving
                ? null
                : (value) {
                    if (value != null) cubit.updateTheme(value);
                  },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<AppMapType>(
            key: const Key('map-type-setting'),
            isExpanded: true,
            initialValue: state.userSettings.mapType,
            decoration: const InputDecoration(
              labelText: 'Loại bản đồ',
              prefixIcon: Icon(Icons.map_outlined),
            ),
            items: const [
              DropdownMenuItem(
                value: AppMapType.standard,
                child: Text('Đường phố'),
              ),
              DropdownMenuItem(
                value: AppMapType.satellite,
                child: Text('Vệ tinh'),
              ),
            ],
            onChanged: state.personalSaving
                ? null
                : (value) {
                    if (value != null) cubit.updateMapType(value);
                  },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<SpeedUnit>(
            key: const Key('speed-unit-setting'),
            isExpanded: true,
            initialValue: state.userSettings.speedUnit,
            decoration: const InputDecoration(
              labelText: 'Đơn vị tốc độ',
              prefixIcon: Icon(Icons.speed_rounded),
            ),
            items: const [
              DropdownMenuItem(value: SpeedUnit.kmh, child: Text('km/h')),
              DropdownMenuItem(value: SpeedUnit.mps, child: Text('m/s')),
            ],
            onChanged: state.personalSaving
                ? null
                : (value) {
                    if (value != null) cubit.updateSpeedUnit(value);
                  },
          ),
          if (state.personalSaving) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }
}

class _SoftwareInformationCard extends StatefulWidget {
  const _SoftwareInformationCard();

  @override
  State<_SoftwareInformationCard> createState() =>
      _SoftwareInformationCardState();
}

class _SoftwareInformationCardState extends State<_SoftwareInformationCard> {
  // Metadata chỉ cần đọc một lần trong vòng đời của trang. Dữ liệu lấy từ gói
  // ứng dụng đã build nên luôn đồng bộ với version trong pubspec.yaml.
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                key: const Key('software-app-icon'),
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: colors.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                // Ảnh thương hiệu có khoảng trắng bao quanh; phóng trong vùng
                // cắt giúp biểu tượng rõ ràng mà không sửa file ảnh gốc.
                child: Transform.scale(
                  scale: 1.85,
                  child: Image.asset(
                    'assets/branding/v_monitor_logo.png',
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    semanticLabel: 'Biểu tượng V Monitor',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'V Monitor',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              'Phần mềm giám sát thiết bị nội bộ',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: FutureBuilder<PackageInfo>(
                future: _packageInfo,
                builder: (context, snapshot) {
                  final packageInfo = snapshot.data;
                  return Column(
                    children: [
                      const _SoftwareInfoRow(
                        icon: Icons.apps_rounded,
                        label: 'Tên phần mềm',
                        value: 'V Monitor',
                      ),
                      const Divider(height: 1, indent: 56),
                      _SoftwareInfoRow(
                        valueKey: const Key('software-version-value'),
                        icon: Icons.new_releases_outlined,
                        label: 'Phiên bản',
                        value: _metadataValue(
                          packageInfo?.version,
                          snapshot.connectionState,
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      _SoftwareInfoRow(
                        valueKey: const Key('software-build-value'),
                        icon: Icons.build_circle_outlined,
                        label: 'Bản dựng',
                        value: _metadataValue(
                          packageInfo?.buildNumber,
                          snapshot.connectionState,
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      _SoftwareInfoRow(
                        valueKey: const Key('software-package-value'),
                        icon: Icons.fingerprint_rounded,
                        label: 'Mã ứng dụng',
                        value: _metadataValue(
                          packageInfo?.packageName,
                          snapshot.connectionState,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _metadataValue(String? value, ConnectionState connectionState) {
    if (connectionState == ConnectionState.waiting) return 'Đang tải…';
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? 'Không xác định' : normalized;
  }
}

class _SoftwareInfoRow extends StatelessWidget {
  const _SoftwareInfoRow({
    this.valueKey,
    required this.icon,
    required this.label,
    required this.value,
  });

  final Key? valueKey;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 18),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              key: valueKey,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountSettingsCard extends StatelessWidget {
  const _AccountSettingsCard({
    required this.user,
    required this.hasAdminAccess,
    required this.operationInProgress,
  });

  final UserModel? user;
  final bool hasAdminAccess;
  final bool operationInProgress;

  Future<void> _editCurrentAccount(BuildContext context) async {
    final currentUser = user;
    if (!hasAdminAccess || currentUser == null) return;
    final saved = await showUserEditorDialog(
      context,
      user: currentUser,
      profileOnly: true,
    );
    if (saved != true || !context.mounted) return;

    // Đọc lại `/auth/me` để tên và email mới đồng bộ ở thẻ tài khoản, menu
    // người dùng và mọi màn hình khác đang theo dõi AuthState.
    final error = await context.read<AuthCubit>().refreshCurrentUser();
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Tài khoản',
      icon: Icons.manage_accounts_outlined,
      // Nút không được tạo cho tài khoản thành viên; backend vẫn kiểm tra
      // require_admin khi API cập nhật được gọi.
      trailing: hasAdminAccess && user != null
          ? TextButton.icon(
              key: const Key('edit-current-account'),
              onPressed: operationInProgress
                  ? null
                  : () => _editCurrentAccount(context),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Sửa'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountField(label: 'Họ tên', value: user?.fullName ?? '—'),
          _AccountField(label: 'Username', value: user?.username ?? '—'),
          _AccountField(label: 'Email', value: user?.email ?? 'Chưa thiết lập'),
          _AccountField(
            label: 'Vai trò',
            value: user?.isAdmin == true ? 'Quản trị viên' : 'Người dùng',
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('open-change-password'),
            onPressed: () => _showChangePasswordDialog(context),
            icon: const Icon(Icons.password_rounded),
            label: const Text('Đổi mật khẩu'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            key: const Key('logout-from-settings'),
            onPressed: () => context.read<AuthCubit>().logout(),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }
}

class _AccountField extends StatelessWidget {
  const _AccountField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _LoadErrorBanner extends StatelessWidget {
  const _LoadErrorBanner({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message ?? 'Không thể tải đầy đủ cài đặt.',
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: () => context.read<SettingsCubit>().initialize(),
              child: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showChangePasswordDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider.value(
      value: context.read<AuthCubit>(),
      child: const ChangePasswordDialog(),
    ),
  );
}
