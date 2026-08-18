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
            backgroundColor: Color(0xFFF8FAFB),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF1677FF)),
            ),
          );
        }

        if (state.error != null) {
          return _ErrorView(error: state.error!);
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFB),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 900;
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
    final visibleCount = DeviceQueryFilter.filter(
      state.devices,
      query: state.searchQuery,
      statusFilter: state.statusFilter,
    ).length;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left panel: Tổng quan (Section 12, 13, 14) ──────────────────────
          // SizedBox(
          //   width: 270,
          //   child: Container(
          //     decoration: BoxDecoration(
          //       color: Colors.white,
          //       borderRadius: BorderRadius.circular(14),
          //       border: Border.all(color: const Color(0xFFE4E9ED), width: 1),
          //       boxShadow: [
          //         BoxShadow(
          //           color: Colors.black.withValues(alpha: 0.03),
          //           blurRadius: 10,
          //           offset: const Offset(0, 2),
          //         ),
          //       ],
          //     ),
          //     padding: const EdgeInsets.all(16),
          //     child: Column(
          //       crossAxisAlignment: CrossAxisAlignment.start,
          //       children: [
          //         // Panel header
          //         const Text(
          //           'Tổng quan',
          //           style: TextStyle(
          //             fontSize: 18,
          //             fontWeight: FontWeight.w700,
          //             color: Color(0xFF18212A),
          //           ),
          //         ),
          //         const SizedBox(height: 2),
          //         Text(
          //           '${state.totalDevices} thiết bị',
          //           style: const TextStyle(
          //             fontSize: 12.5,
          //             fontWeight: FontWeight.w500,
          //             color: Color(0xFF66727D),
          //           ),
          //         ),
          //         const SizedBox(height: 14),
          //         // Status counters
          //         _SidebarStats(state: state),
          //         const SizedBox(height: 12),
          //         const Divider(height: 1, color: Color(0xFFE8ECEF)),
          //         const SizedBox(height: 12),
          //         // Legend
          //         const _SidebarLegend(),
          //       ],
          //     ),
          //   ),
          // ),
          // const SizedBox(width: 14),
          // ── Right panel: Main Device List (Section 15, 16, 17, 18, 19) ─────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE4E9ED), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top Toolbar: Title + Badge (Left) & Search + Refresh (Right) ──
                  Row(
                    children: [
                      // Title & Count Badge
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Danh sách thiết bị',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF18212A),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '$visibleCount/${state.totalDevices}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // WhatsGPS sleek Search Bar
                      SizedBox(
                        width: 260,
                        child: _SearchBar(initialValue: state.searchQuery),
                      ),
                      const SizedBox(width: 8),
                      // Refresh button
                      _RefreshButton(
                        onPressed: () =>
                            context.read<DashboardCubit>().loadDashboard(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // ── Filter Bar: Segmented Status Pill Strip ──
                  _StatusFilterBar(selected: state.statusFilter, state: state),
                  const SizedBox(height: 10),
                  // ── Device grid ──
                  Expanded(
                    child: DeviceGrid(
                      devices: state.devices,
                      searchQuery: state.searchQuery,
                      statusFilter: state.statusFilter,
                      deviceAddresses: state.deviceAddresses,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ─── Mobile: Vertical scroll with AppBar ────────────────────────────────────
class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.state});
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final visibleCount = DeviceQueryFilter.filter(
      state.devices,
      query: state.searchQuery,
      statusFilter: state.statusFilter,
    ).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          'Dashboard',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF18212A),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF66727D)),
              tooltip: 'Tải lại',
              onPressed: () => context.read<DashboardCubit>().loadDashboard(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Refresh in 1 compact row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Expanded(child: _SearchBar(initialValue: state.searchQuery)),
                const SizedBox(width: 8),
                _RefreshButton(
                  onPressed: () =>
                      context.read<DashboardCubit>().loadDashboard(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _StatusFilterBar(selected: state.statusFilter, state: state),
          ),
          // Stats horizontal carousel
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: StatsOverview(state: state),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                Text(
                  '$visibleCount/${state.totalDevices} thiết bị hiển thị',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF66727D),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8ECEF)),
          // Device list
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DeviceGrid(
                devices: state.devices,
                searchQuery: state.searchQuery,
                statusFilter: state.statusFilter,
                deviceAddresses: state.deviceAddresses,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ─── Shared Widgets ──────────────────────────────────────────────────────────

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: const Center(
            child: Icon(
              Icons.refresh_rounded,
              color: Color(0xFF64748B),
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar({required this.initialValue});
  final String initialValue;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isFocused = _focusNode.hasFocus;
        });
      }
    });
  }

  @override
  void didUpdateWidget(_SearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text &&
        widget.initialValue != oldWidget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: _isFocused ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isFocused ? const Color(0xFF1677FF) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: const Color(0xFF1677FF).withValues(alpha: 0.12),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 10, right: 6),
            child: Icon(
              Icons.search_rounded,
              size: 16,
              color: Color(0xFF94A3B8),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF18212A),
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                hintText: 'Tìm thiết bị, biển số, mã...',
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) =>
                  context.read<DashboardCubit>().setSearchQuery(v),
            ),
          ),
          if (_controller.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  _controller.clear();
                  context.read<DashboardCubit>().setSearchQuery('');
                  setState(() {});
                },
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shared status filter used by dashboard device lists - WhatsGPS style segmented tab strip.
class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.selected, this.state});

  final DeviceFilter selected;
  final DashboardState? state;

  int _countFor(DeviceFilter filter) {
    if (state == null) return 0;
    switch (filter) {
      case DeviceFilter.all:
        return state!.totalDevices;
      case DeviceFilter.online:
        return state!.onlineCount;
      case DeviceFilter.offline:
        return state!.offlineCount;
      case DeviceFilter.moving:
        return state!.movingCount;
      case DeviceFilter.stopped:
        return state!.stoppedCount;
      case DeviceFilter.stale:
        return state!.staleCount;
    }
  }

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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _options.map((option) {
            final isSelected = selected == option.filter;
            final count = state != null ? _countFor(option.filter) : null;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                onTap: () => context.read<DashboardCubit>().setStatusFilter(
                  option.filter,
                ),
                borderRadius: BorderRadius.circular(6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? const Color(0xFF1677FF)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      if (count != null) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(
                                    0xFF1677FF,
                                  ).withValues(alpha: 0.12)
                                : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? const Color(0xFF1677FF)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
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
        color: const Color(0xFF8B949E),
        icon: Icons.wifi_off_rounded,
      ),
      _StatRow(
        label: 'Di chuyển',
        value: state.movingCount,
        color: const Color(0xFF1677FF),
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
      children: items.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(item.icon, color: item.color, size: 14),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF18212A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  height: 19,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${item.value}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: item.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
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
  const _SidebarLegend();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trạng thái',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF18212A),
          ),
        ),
        SizedBox(height: 8),
        _LegendItem(color: Color(0xFF16A34A), label: 'Trực tuyến'),
        SizedBox(height: 4),
        _LegendItem(color: Color(0xFF8B949E), label: 'Ngoại tuyến'),
        SizedBox(height: 4),
        _LegendItem(color: Color(0xFF1677FF), label: 'Di chuyển'),
        SizedBox(height: 4),
        _LegendItem(color: Color(0xFFD97706), label: 'Đang dừng'),
        SizedBox(height: 4),
        _LegendItem(color: Color(0xFFDC2626), label: 'Mất tín hiệu'),
        SizedBox(height: 4),
        _LegendItem(
          color: Color(0xFFEA580C),
          isWarning: true,
          label: 'Cần kiểm tra',
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.isWarning = false,
  });

  final Color color;
  final String label;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (isWarning)
          Icon(Icons.warning_amber_rounded, size: 12, color: color)
        else
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: Color(0xFF66727D),
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
      backgroundColor: const Color(0xFFF8FAFB),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE4E9ED), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 56,
                color: theme.colorScheme.error.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 16),
              const Text(
                'Không thể kết nối backend',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF18212A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                error,
                style: const TextStyle(fontSize: 13, color: Color(0xFF66727D)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1677FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => context.read<DashboardCubit>().loadDashboard(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
