import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/config/map_tile_providers.dart';
import '../../data/models/user_model.dart';
import '../../data/models/user_settings_model.dart';
import '../auth/auth_cubit.dart';
import '../auth/change_password_dialog.dart';
import 'settings_cubit.dart';
import 'settings_state.dart';
import 'widgets/tracking_settings_card.dart';
import 'widgets/user_management_card.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _usersRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settingsCubit = context.read<SettingsCubit>();
    if (settingsCubit.state.status == SettingsLoadStatus.initial) {
      settingsCubit.initialize();
    }
    if (!_usersRequested &&
        context.read<AuthCubit>().state.user?.isAdmin == true) {
      _usersRequested = true;
      settingsCubit.loadUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthCubit>().state.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt'),
        actions: [
          IconButton(
            tooltip: 'Tải lại cài đặt',
            onPressed: () {
              context.read<SettingsCubit>().initialize();
              if (user?.isAdmin == true) {
                context.read<SettingsCubit>().loadUsers();
              }
            },
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
          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 900;
              return RefreshIndicator(
                onRefresh: () async {
                  await context.read<SettingsCubit>().initialize();
                  if (user?.isAdmin == true && context.mounted) {
                    await context.read<SettingsCubit>().loadUsers();
                  }
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    isDesktop ? 32 : 16,
                    20,
                    isDesktop ? 32 : 16,
                    32,
                  ),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (state.status == SettingsLoadStatus.loading)
                              const LinearProgressIndicator(minHeight: 2),
                            if (state.status == SettingsLoadStatus.error) ...[
                              _LoadErrorBanner(message: state.message),
                              const SizedBox(height: 16),
                            ],
                            if (isDesktop)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _PersonalSettingsCard(state: state),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: _AccountSettingsCard(user: user),
                                  ),
                                ],
                              )
                            else ...[
                              _PersonalSettingsCard(state: state),
                              const SizedBox(height: 16),
                              _AccountSettingsCard(user: user),
                            ],
                            if (user?.isAdmin == true) ...[
                              const SizedBox(height: 28),
                              Text(
                                'Quản trị',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              TrackingSettingsCard(
                                settings: state.systemSettings,
                                saving: state.systemSaving,
                              ),
                              const SizedBox(height: 16),
                              UserManagementCard(
                                users: state.users,
                                loading: state.usersLoading,
                                operationInProgress:
                                    state.userOperationInProgress,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
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

class _AccountSettingsCard extends StatelessWidget {
  const _AccountSettingsCard({required this.user});

  final UserModel? user;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Tài khoản',
      icon: Icons.manage_accounts_outlined,
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
  });

  final String title;
  final IconData icon;
  final Widget child;

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
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
