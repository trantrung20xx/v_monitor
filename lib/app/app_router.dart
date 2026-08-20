import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/dashboard_page.dart';
import '../features/device_detail/device_detail_page.dart';
import '../features/map/map_view_page.dart';
import '../features/auth/auth_cubit.dart';
import '../features/auth/change_password_dialog.dart';

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

/// Khung điều hướng dùng thanh bên trên desktop và thanh đáy trên màn hình nhỏ.
class _AppShell extends StatefulWidget {
  const _AppShell({required this.child});
  final Widget child;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _selectedIndex = 0;

  void _onDestinationSelected(int index) {
    if (index == 2) {
      _showMobileAccountActions();
      return;
    }
    setState(() => _selectedIndex = index);
    switch (index) {
      case 0:
        context.goNamed('dashboard');
      case 1:
        context.goNamed('map');
    }
  }

  Future<void> _showMobileAccountActions() async {
    final authCubit = context.read<AuthCubit>();
    final user = authCubit.state.user;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person_outline_rounded),
                ),
                title: Text(user?.fullName ?? user?.username ?? 'Tài khoản'),
                subtitle: Text(
                  user?.isAdmin == true ? 'Quản trị viên' : 'Người xem',
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: const Text('Đổi mật khẩu'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showChangePasswordDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Đăng xuất'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  authCubit.logout();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Xác định mục điều hướng hiện tại từ đường dẫn.
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = location.startsWith('/map') ? 1 : 0;
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
              onDestinationSelected: _onDestinationSelected,
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
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
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
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle_rounded),
            label: 'Tài khoản',
          ),
        ],
      ),
    );
  }
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
    return Container(
      width: 88,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE4E9ED), width: 1)),
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE4E9ED)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1677FF).withValues(alpha: 0.14),
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
    final state = context.watch<AuthCubit>().state;
    final user = state.user;
    final displayName = user?.fullName.trim().isNotEmpty == true
        ? user!.fullName.trim()
        : user?.username ?? 'Tài khoản';

    return PopupMenuButton<String>(
      tooltip: displayName,
      onSelected: (value) {
        if (value == 'change-password') {
          _showChangePasswordDialog(context);
        } else if (value == 'logout') {
          context.read<AuthCubit>().logout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  user?.isAdmin == true ? 'Quản trị viên' : 'Người xem',
                  style: const TextStyle(color: Color(0xFF66727D)),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'change-password',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.password_rounded),
            title: Text('Đổi mật khẩu'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded),
            title: Text('Đăng xuất'),
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
              backgroundColor: const Color(0xFF1677FF).withValues(alpha: 0.12),
              child: const Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: Color(0xFF1677FF),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tài khoản',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF66727D)),
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
    const activeColor = Color(0xFF1677FF);
    const inactiveColor = Color(0xFF66727D);

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
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.25)
                  : Colors.transparent,
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
