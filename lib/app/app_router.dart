import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/dashboard_page.dart';
import '../features/device_detail/device_detail_page.dart';
import '../features/map/map_view_page.dart';
import '../features/auth/auth_cubit.dart';
import '../features/settings/settings_page.dart';
import '../core/theme/app_theme_colors.dart';
import '../core/widgets/app_menu.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'shell',
);

/// Cấu hình điều hướng của phần ứng dụng đã xác thực.
class AppRouter {
  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    routes: [
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => _AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            name: 'dashboard',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DashboardPage()),
          ),
          GoRoute(path: '/dashboard', redirect: (context, state) => '/'),
          GoRoute(
            path: '/map',
            name: 'map',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: MapViewPage()),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsPage()),
          ),
          GoRoute(
            path: '/settings/personal',
            name: 'settings-personal',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsPage(section: SettingsSection.personal),
            ),
          ),
          GoRoute(
            path: '/settings/account',
            name: 'settings-account',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsPage(section: SettingsSection.account),
            ),
          ),
          GoRoute(
            path: '/settings/about',
            name: 'settings-about',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsPage(section: SettingsSection.about),
            ),
          ),
          GoRoute(
            path: '/settings/tracking',
            name: 'settings-tracking',
            redirect: _redirectNonAdminSettings,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsPage(section: SettingsSection.tracking),
            ),
          ),
          GoRoute(
            path: '/settings/users',
            name: 'settings-users',
            redirect: _redirectNonAdminSettings,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsPage(section: SettingsSection.users),
            ),
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/devices/:id',
        name: 'device-detail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return DeviceDetailPage(deviceId: id);
        },
      ),
    ],
  );
}

String? _redirectNonAdminSettings(BuildContext context, GoRouterState state) {
  // Không dựng trang quản trị nếu trạng thái xác thực hiện tại chưa cấp quyền
  // ADMIN. Các API bên trong vẫn được backend bảo vệ.
  return context.read<AuthCubit>().state.hasAdminAccess ? null : '/settings';
}

/// Khung điều hướng dùng thanh bên trên desktop và thanh đáy trên màn hình nhỏ.
class _AppShell extends StatefulWidget {
  const _AppShell({required this.child});
  final Widget child;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _selectedIndex = 0;
  bool _isMobileAccountMenuOpen = false;

  void _onPrimaryDestinationSelected(int index) {
    setState(() => _selectedIndex = index);
    switch (index) {
      case 0:
        context.goNamed('dashboard');
      case 1:
        context.goNamed('map');
    }
  }

  Future<void> _onMobileDestinationSelected(int index) async {
    if (index == 2) {
      if (_isMobileAccountMenuOpen) return;
      setState(() => _isMobileAccountMenuOpen = true);
      await _showMobileAccountMenu(context);
      if (mounted) setState(() => _isMobileAccountMenuOpen = false);
      return;
    }
    _onPrimaryDestinationSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    // Xác định mục điều hướng hiện tại từ đường dẫn.
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = location.startsWith('/settings')
        ? 2
        : location.startsWith('/map')
        ? 1
        : 0;
    if (currentIndex != _selectedIndex) {
      _selectedIndex = currentIndex;
    }

    final isWide = MediaQuery.sizeOf(context).width >= 800;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            _DesktopNavRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onPrimaryDestinationSelected,
            ),
            Expanded(child: widget.child),
          ],
        ),
      );
    }

    // Trên màn hình nhỏ, thanh điều hướng đáy giữ các chức năng chính trong
    // vùng dễ thao tác và đưa tác vụ tài khoản vào một mục riêng biệt.
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _isMobileAccountMenuOpen ? 2 : _selectedIndex,
        onDestinationSelected: _onMobileDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Bản đồ',
          ),
          NavigationDestination(
            key: Key('mobile-account-destination'),
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.manage_accounts_rounded),
            label: 'Tài khoản',
          ),
        ],
      ),
    );
  }
}

Future<void> _showMobileAccountMenu(BuildContext context) {
  final authCubit = context.read<AuthCubit>();
  final user = authCubit.state.user;
  final displayName = user?.fullName.trim().isNotEmpty == true
      ? user!.fullName.trim()
      : user?.username ?? 'Tài khoản';

  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppMenuStyle.surfaceColor(context),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppMenuHeader(
            key: const Key('mobile-account-profile'),
            displayName: displayName,
            roleLabel: user?.isAdmin == true ? 'Quản trị viên' : 'Người xem',
            touchTarget: true,
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.goNamed('settings-account');
            },
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 6),
          AppMenuItem(
            key: const Key('mobile-account-settings'),
            icon: Icons.settings_rounded,
            label: 'Cài đặt',
            trailing: const Icon(Icons.chevron_right_rounded),
            touchTarget: true,
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.goNamed('settings');
            },
          ),
          AppMenuItem(
            key: const Key('mobile-account-logout'),
            icon: Icons.logout_rounded,
            label: 'Đăng xuất',
            isDestructive: true,
            touchTarget: true,
            onTap: () {
              Navigator.of(sheetContext).pop();
              authCubit.logout();
            },
          ),
        ],
      ),
    ),
  );
}

class _DesktopNavRail extends StatelessWidget {
  const _DesktopNavRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Logo phía trên giúp nhận diện ứng dụng khi thanh bên được thu gọn.
            Container(
              key: const Key('app-brand-logo'),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: appColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: appColors.borderSoft),
                boxShadow: [
                  BoxShadow(
                    color: appColors.primary.withValues(alpha: 0.14),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Transform.scale(
                scale: 1.85,
                child: Image.asset(
                  'assets/branding/v_monitor_logo.png',
                  width: 38,
                  height: 38,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  semanticLabel: 'V Monitor',
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Các mục điều hướng dùng chung cùng chỉ số với cấu hình router.
            _NavItem(
              index: 0,
              isSelected: selectedIndex == 0,
              icon: Icons.dashboard_rounded,
              label: 'Dashboard',
              onTap: () => onDestinationSelected(0),
            ),
            const SizedBox(height: 6),
            _NavItem(
              index: 1,
              isSelected: selectedIndex == 1,
              icon: Icons.map_rounded,
              label: 'Bản đồ',
              onTap: () => onDestinationSelected(1),
            ),
            const Spacer(),
            const _DesktopAccountMenu(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _DesktopAccountMenu extends StatelessWidget {
  const _DesktopAccountMenu();

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final state = context.watch<AuthCubit>().state;
    final user = state.user;
    final displayName = user?.fullName.trim().isNotEmpty == true
        ? user!.fullName.trim()
        : user?.username ?? 'Tài khoản';

    return PopupMenuButton<String>(
      tooltip: displayName,
      constraints: const BoxConstraints(minWidth: 276, maxWidth: 304),
      onSelected: (value) {
        if (value == 'account') {
          context.goNamed('settings-account');
        } else if (value == 'settings') {
          context.goNamed('settings');
        } else if (value == 'logout') {
          context.read<AuthCubit>().logout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          key: const Key('account-menu-profile'),
          value: 'account',
          height: 68,
          padding: EdgeInsets.zero,
          child: AppMenuHeader(
            displayName: displayName,
            roleLabel: user?.isAdmin == true ? 'Quản trị viên' : 'Người xem',
          ),
        ),
        const PopupMenuDivider(height: 9),
        const PopupMenuItem<String>(
          key: Key('account-menu-settings'),
          value: 'settings',
          height: 42,
          padding: EdgeInsets.zero,
          child: AppMenuItem(icon: Icons.settings_rounded, label: 'Cài đặt'),
        ),
        const PopupMenuItem<String>(
          key: Key('account-menu-logout'),
          value: 'logout',
          height: 42,
          padding: EdgeInsets.zero,
          child: AppMenuItem(
            icon: Icons.logout_rounded,
            label: 'Đăng xuất',
            isDestructive: true,
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: appColors.primary.withValues(alpha: 0.12),
              child: Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: appColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tài khoản',
              style: TextStyle(
                fontSize: 10.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.isSelected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final int index;
  final bool isSelected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final activeColor = colors.primary;
    final inactiveColor = colors.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.08)
                : AppPalette.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.25)
                  : AppPalette.transparent,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? activeColor : inactiveColor,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? activeColor : inactiveColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
