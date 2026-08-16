import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/dashboard_page.dart';
import '../features/device_detail/device_detail_page.dart';
import '../features/journey_history/journey_history_page.dart';
import '../features/map/map_view_page.dart';

/// Application route configuration.
class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => _AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            name: 'dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/map',
            name: 'map',
            builder: (context, state) => const MapViewPage(),
          ),
          GoRoute(
            path: '/history',
            name: 'history',
            builder: (context, state) {
              final deviceId = state.uri.queryParameters['device_id'];
              return JourneyHistoryPage(initialDeviceId: deviceId);
            },
          ),
        ],
      ),
      GoRoute(
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

/// Shell with NavigationRail for desktop / bottom nav for mobile.
class _AppShell extends StatefulWidget {
  const _AppShell({required this.child});
  final Widget child;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _selectedIndex = 0;

  static const _destinations = [
    NavigationRailDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: Text('Dashboard'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.map_outlined),
      selectedIcon: Icon(Icons.map),
      label: Text('Bản đồ'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.route_outlined),
      selectedIcon: Icon(Icons.route_rounded),
      label: Text('Lịch sử'),
    ),
  ];

  void _onDestinationSelected(int index) {
    setState(() => _selectedIndex = index);
    switch (index) {
      case 0:
        context.goNamed('dashboard');
      case 1:
        context.goNamed('map');
      case 2:
        context.goNamed('history');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine current index from location
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = location.startsWith('/history')
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
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              leading: const SizedBox(height: 8),
              destinations: _destinations,
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: widget.child),
          ],
        ),
      );
    }

    // Mobile layout with bottom nav
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Bản đồ',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route_rounded),
            label: 'Lịch sử',
          ),
        ],
      ),
    );
  }
}
