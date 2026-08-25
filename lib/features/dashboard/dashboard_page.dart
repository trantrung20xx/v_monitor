// Màn hình tổng quan vận hành: thống kê, tìm kiếm/lọc và danh sách thiết bị.
// Widget chỉ trình bày DashboardState; toàn bộ dữ liệu và trạng thái do Cubit cung cấp.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/device_query_filter.dart';
import 'dashboard_cubit.dart';
import 'dashboard_state.dart';
import 'widgets/device_list_panel.dart';
// ignore: unused_import
import 'widgets/stats_overview.dart';

// Route Dashboard tạo DashboardCubit từ các repository dùng chung và tải snapshot ban đầu.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    // BlocProvider sở hữu Cubit trong phạm vi route; repository tiếp tục cung cấp
    // REST, WebSocket và geocoding cho Cubit.
    return BlocProvider(
      create: (context) => DashboardCubit(
        deviceRepo: context.read<DeviceRepository>(),
        geocodingRepo: context.read<GeocodingRepository>(),
        settingsRepo: context.read<SettingsRepository>(),
      )..loadDashboard(),
      child: const _DashboardView(),
    );
  }
}

// Chọn trạng thái loading/error/nội dung và chuyển desktop/mobile theo chiều rộng.
class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    // DashboardState là nguồn duy nhất cho danh sách, bộ lọc, số đếm và địa chỉ.
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        final appColors = context.appColors;
        if (state.isLoading) {
          return Scaffold(
            backgroundColor: appColors.surfaceSubtle,
            body: Center(
              child: CircularProgressIndicator(color: appColors.primary),
            ),
          );
        }

        if (state.error != null) {
          return _ErrorView(error: state.error!);
        }

        return Scaffold(
          backgroundColor: appColors.surfaceSubtle,
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

/// Desktop: cột thống kê bên trái và lưới thiết bị bên phải.
// Bố cục desktop chia sidebar thống kê/bộ lọc và vùng lưới thiết bị rộng bên phải.
class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.state});
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
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
          // Khung phải chứa danh sách thiết bị chính.
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: appColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: appColors.borderSoft, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: appColors.shadow.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thanh trên: tiêu đề/số lượng bên trái, tìm kiếm/làm mới bên phải.
                  Row(
                    children: [
                      // Title & Count Badge
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Danh sách thiết bị',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: appColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: appColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: appColors.border,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '$visibleCount/${state.totalDevices}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: appColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Thanh tìm kiếm thiết bị dạng gọn.
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
                  // Thanh lọc trạng thái dạng nút phân đoạn.
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

/// Di động: nội dung cuộn dọc dưới AppBar.
// Bố cục mobile xếp tìm kiếm, lọc, thống kê và danh sách theo chiều dọc có cuộn.
class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.state});
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final visibleCount = DeviceQueryFilter.filter(
      state.devices,
      query: state.searchQuery,
      statusFilter: state.statusFilter,
    ).length;

    return Scaffold(
      backgroundColor: appColors.surfaceSubtle,
      appBar: AppBar(
        backgroundColor: appColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(
          'Dashboard',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: appColors.textPrimary,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Icon(Icons.refresh_rounded, color: appColors.textSecondary),
              tooltip: 'Tải lại',
              onPressed: () => context.read<DashboardCubit>().loadDashboard(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Tìm kiếm và làm mới trong cùng một hàng gọn.
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
          // Padding(
          //   padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          //   child: StatsOverview(state: state),
          // ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                Text(
                  '$visibleCount/${state.totalDevices} thiết bị hiển thị',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: appColors.divider),
          // Danh sách thiết bị sau khi áp dụng tìm kiếm và bộ lọc.
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

// Nút tải lại snapshot REST; cập nhật realtime vẫn được DashboardCubit lắng nghe riêng.
class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: appColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appColors.border, width: 1),
      ),
      child: Material(
        color: AppPalette.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: Icon(
              Icons.refresh_rounded,
              color: appColors.textSecondary,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

// Ô tìm kiếm điều khiển DashboardState.searchQuery nhưng giữ FocusNode/controller cục bộ.
class _SearchBar extends StatefulWidget {
  const _SearchBar({required this.initialValue});
  final String initialValue;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  // Đồng bộ controller khi query đổi từ bên ngoài và chỉ dùng focus để đổi viền hiển thị.
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
    final appColors = context.appColors;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: _isFocused ? appColors.surface : appColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isFocused ? appColors.primary : appColors.border,
          width: 1,
        ),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: appColors.primary.withValues(alpha: 0.12),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 6),
            child: Icon(
              Icons.search_rounded,
              size: 16,
              color: appColors.textMuted,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: TextStyle(
                fontSize: 13,
                color: appColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Tìm thiết bị, biển số, mã...',
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: appColors.textMuted,
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
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: appColors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Thanh lọc trạng thái dùng chung cho các danh sách thiết bị của Dashboard.
// Thanh lọc trạng thái dùng các số đếm đã được DashboardCubit tính bằng DeviceStatusResolver.
class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.selected, this.state});

  final DeviceFilter selected;
  final DashboardState? state;

  int _countFor(DeviceFilter filter) {
    // Ánh xạ từng lựa chọn UI tới đúng bộ đếm trong DashboardState.
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
    final appColors = context.appColors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: appColors.surfaceMuted,
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
                    color: isSelected
                        ? appColors.surface
                        : AppPalette.transparent,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: appColors.shadow.withValues(alpha: 0.05),
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
                              ? appColors.primary
                              : appColors.textSecondary,
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
                                ? appColors.primary.withValues(alpha: 0.12)
                                : appColors.border,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? appColors.primary
                                  : appColors.textSecondary,
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

// Model trình bày nội bộ của một chip lọc, không chứa dữ liệu thiết bị.
class _FilterOption {
  const _FilterOption(this.filter, this.label);

  final DeviceFilter filter;
  final String label;
}

/// Danh sách thống kê dọc nhỏ gọn cho panel trái trên desktop.
// Khối thống kê desktop hiển thị tổng/online/offline/chuyển động từ DashboardState.
// ignore: unused_element
class _SidebarStats extends StatelessWidget {
  const _SidebarStats({required this.state});
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final items = [
      _StatRow(
        label: 'Trực tuyến',
        value: state.onlineCount,
        color: appColors.success,
        icon: Icons.wifi_rounded,
      ),
      _StatRow(
        label: 'Ngoại tuyến',
        value: state.offlineCount,
        color: appColors.offline,
        icon: Icons.wifi_off_rounded,
      ),
      _StatRow(
        label: 'Di chuyển',
        value: state.movingCount,
        color: appColors.primary,
        icon: Icons.navigation_rounded,
      ),
      _StatRow(
        label: 'Đang dừng',
        value: state.stoppedCount,
        color: appColors.warning,
        icon: Icons.pause_circle_rounded,
      ),
      _StatRow(
        label: 'Mất tín hiệu',
        value: state.staleCount,
        color: appColors.danger,
        icon: Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
      ),
      _StatRow(
        label: 'Cần kiểm tra',
        value: state.attentionCount,
        color: appColors.orange,
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
              color: appColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: appColors.borderSoft, width: 1),
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
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: appColors.textPrimary,
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

// Dữ liệu trình bày cho một hàng thống kê trong sidebar.
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

// Chú giải màu trạng thái giúp đọc thẻ thiết bị; màu lấy từ AppThemeColors.
// ignore: unused_element
class _SidebarLegend extends StatelessWidget {
  const _SidebarLegend();

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trạng thái',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: appColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _LegendItem(color: appColors.success, label: 'Trực tuyến'),
        const SizedBox(height: 4),
        _LegendItem(color: appColors.offline, label: 'Ngoại tuyến'),
        const SizedBox(height: 4),
        _LegendItem(color: appColors.primary, label: 'Di chuyển'),
        const SizedBox(height: 4),
        _LegendItem(color: appColors.warning, label: 'Đang dừng'),
        const SizedBox(height: 4),
        _LegendItem(color: appColors.danger, label: 'Mất tín hiệu'),
        const SizedBox(height: 4),
        _LegendItem(
          color: appColors.orange,
          isWarning: true,
          label: 'Cần kiểm tra',
        ),
      ],
    );
  }
}

// Một mục chú giải gồm chấm màu và nhãn, tự co để không cắt chữ.
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
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: context.appColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// ─── Error view ──────────────────────────────────────────────────────────────
// Trạng thái lỗi toàn trang hiển thị thông báo đã chuẩn hóa và cho phép gọi tải lại.
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    return Scaffold(
      backgroundColor: appColors.surfaceSubtle,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: appColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: appColors.borderSoft, width: 1),
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
              Text(
                'Không thể kết nối backend',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: appColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                error,
                style: TextStyle(fontSize: 13, color: appColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: appColors.primary,
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
