import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/device_repository.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../domain/entities/device_query_filter.dart';
import 'dashboard_cubit.dart';
import 'dashboard_state.dart';
import 'widgets/device_list_panel.dart';
import 'widgets/stats_overview.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DashboardCubit(
        deviceRepo: context.read<DeviceRepository>(),
        geocodingRepo: context.read<GeocodingRepository>(),
      )..loadDashboard(),
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state.error != null) {
          return _ErrorView(error: state.error!);
        }

        return Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 800;
              if (isDesktop) {
                return _DesktopLayout(state: state);
              }
              return _MobileLayout(state: state);
            },
          ),
        );
      },
    );
  }
}

/// ─── Desktop: Left sidebar (stats) + Right content (device grid) ────────────
class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.state});
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleCount = DeviceQueryFilter.filter(
      state.devices,
      query: state.searchQuery,
      statusFilter: state.statusFilter,
    ).length;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left panel: Summary ──────────────────────────────────────────────
        SizedBox(
          width: 260,
          child: Container(
            color: theme.colorScheme.surface,
            child: Column(
              children: [
                // Panel header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tổng quan',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${state.totalDevices} thiết bị',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Stats
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _SidebarStats(state: state),
                ),
                const Divider(height: 1),
                // Quick filters hint
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: _SidebarLegend(),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        // ── Right panel: Device list ─────────────────────────────────────────
        Expanded(
          child: Column(
            children: [
              // Header bar
              Container(
                color: theme.colorScheme.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Danh sách thiết bị',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$visibleCount/${state.totalDevices} thiết bị hiển thị',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: 'Tải lại',
                          onPressed: () =>
                              context.read<DashboardCubit>().loadDashboard(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(children: [Expanded(child: _SearchBar())]),
                    const SizedBox(height: 10),
                    _StatusFilterBar(selected: state.statusFilter),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Device grid
              Expanded(
                child: DeviceGrid(
                  devices: state.devices,
                  searchQuery: state.searchQuery,
                  statusFilter: state.statusFilter,
                  deviceAddresses: state.deviceAddresses,
                  latestUsages: state.latestUsages,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ─── Mobile: Vertical scroll with AppBar ────────────────────────────────────
class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.state});
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleCount = DeviceQueryFilter.filter(
      state.devices,
      query: state.searchQuery,
      statusFilter: state.statusFilter,
    ).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Dashboard',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Tải lại',
            onPressed: () => context.read<DashboardCubit>().loadDashboard(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _SearchBar(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _StatusFilterBar(selected: state.statusFilter),
          ),
          // Stats wrap
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: StatsOverview(state: state),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Text(
                  '$visibleCount/${state.totalDevices} thiết bị hiển thị',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Device list
          Expanded(
            child: DeviceGrid(
              devices: state.devices,
              searchQuery: state.searchQuery,
              statusFilter: state.statusFilter,
              deviceAddresses: state.deviceAddresses,
              latestUsages: state.latestUsages,
            ),
          ),
        ],
      ),
    );
  }
}

/// ─── Shared Widgets ──────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: const InputDecoration(
        hintText: 'Tìm kiếm thiết bị, người dùng...',
        prefixIcon: Icon(Icons.search_rounded, size: 20),
        isDense: true,
      ),
      onChanged: (v) => context.read<DashboardCubit>().setSearchQuery(v),
    );
  }
}

/// Shared status filter used by dashboard device lists.
class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.selected});

  final DeviceFilter selected;

  static const _options = [
    _FilterOption(DeviceFilter.all, 'Tất cả'),
    _FilterOption(DeviceFilter.online, 'Trực tuyến'),
    _FilterOption(DeviceFilter.offline, 'Ngoại tuyến'),
    _FilterOption(DeviceFilter.moving, 'Di chuyển'),
    _FilterOption(DeviceFilter.stopped, 'Đang dừng'),
    _FilterOption(DeviceFilter.stale, 'Mất tín hiệu'),
  ];

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _options.map((option) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(option.label),
                selected: selected == option.filter,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => context
                    .read<DashboardCubit>()
                    .setStatusFilter(option.filter),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _FilterOption {
  const _FilterOption(this.filter, this.label);

  final DeviceFilter filter;
  final String label;
}

/// Sidebar stat items - compact vertical list for desktop left panel.
class _SidebarStats extends StatelessWidget {
  const _SidebarStats({required this.state});
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final items = [
      _StatRow(
        label: 'Trực tuyến',
        value: state.onlineCount,
        color: const Color(0xFF16A34A),
        icon: Icons.wifi_rounded,
      ),
      _StatRow(
        label: 'Ngoại tuyến',
        value: state.offlineCount,
        color: Colors.grey.shade500,
        icon: Icons.wifi_off_rounded,
      ),
      _StatRow(
        label: 'Di chuyển',
        value: state.movingCount,
        color: const Color(0xFF2563EB),
        icon: Icons.navigation_rounded,
      ),
      _StatRow(
        label: 'Đang dừng',
        value: state.stoppedCount,
        color: const Color(0xFFD97706),
        icon: Icons.pause_circle_rounded,
      ),
      _StatRow(
        label: 'Mất tín hiệu',
        value: state.staleCount,
        color: const Color(0xFFDC2626),
        icon: Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
      ),
      _StatRow(
        label: 'Cần kiểm tra',
        value: state.attentionCount,
        color: const Color(0xFFEA580C),
        icon: Icons.warning_amber_rounded,
      ),
    ];

    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(item.icon, color: item.color, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${item.value}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: item.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _StatRow {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  const _StatRow({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
}

class _SidebarLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trạng thái',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _LegendItem(
          color: const Color(0xFF2563EB),
          icon: Icons.navigation_rounded,
          label: 'Đang di chuyển',
        ),
        const SizedBox(height: 5),
        _LegendItem(
          color: const Color(0xFFD97706),
          icon: Icons.pause_circle_rounded,
          label: 'Đang dừng',
        ),
        const SizedBox(height: 5),
        _LegendItem(
          color: Colors.grey.shade500,
          icon: Icons.wifi_off_rounded,
          label: 'Ngoại tuyến',
        ),
        const SizedBox(height: 5),
        _LegendItem(
          color: const Color(0xFFDC2626),
          icon: Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
          label: 'Mất tín hiệu',
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.icon,
    required this.label,
  });
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// ─── Error view ──────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: theme.colorScheme.error.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              'Không thể kết nối backend',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.read<DashboardCubit>().loadDashboard(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}
