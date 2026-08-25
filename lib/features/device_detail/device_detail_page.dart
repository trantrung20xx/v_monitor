// Toàn bộ giao diện chi tiết thiết bị: tổng quan, bản đồ, thông số, sự kiện và hành trình.
// Các widget con chỉ định dạng dữ liệu thật từ DeviceDetailState và dùng theme tập trung.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/map_tile_providers.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/widgets/app_menu.dart';
import '../../core/widgets/device_icon.dart';
import '../../core/utils/map_launcher_service.dart';
import '../../core/utils/device_formatters.dart';
import '../../data/models/device_model.dart';
import '../../data/models/device_event_model.dart';
import '../../data/models/location_model.dart';
import '../../domain/entities/device_status_resolver.dart';
import '../../domain/entities/gps_validator.dart';
import '../../domain/entities/route_segment.dart';
import 'device_detail_cubit.dart';

import '../../data/repositories/device_repository.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../data/repositories/tracking_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../journey_history/journey_history_cubit.dart';
import '../journey_history/journey_history_state.dart';
import '../journey_history/widgets/custom_date_time_range_dialog.dart';
import '../journey_history/widgets/custom_gap_dialog.dart';
import '../journey_history/widgets/history_map_layers.dart';
import '../journey_history/widgets/point_info_popup.dart';
import '../settings/settings_cubit.dart';

/// Màn hình chi tiết phục vụ tổng quan, hành trình và sự kiện của thiết bị.
/// `deviceId` đến từ route; repository tải hồ sơ, vị trí và sự kiện theo đúng id này.
class DeviceDetailPage extends StatelessWidget {
  const DeviceDetailPage({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    // Route sở hữu DeviceDetailCubit; Cubit bắt đầu tải dữ liệu ngay khi được tạo và
    // tự đóng subscription khi BlocProvider rời khỏi cây widget.
    return BlocProvider(
      create: (context) {
        return DeviceDetailCubit(
          deviceId: deviceId,
          deviceRepo: context.read<DeviceRepository>(),
          trackingRepo: context.read<TrackingRepository>(),
          geocodingRepo: context.read<GeocodingRepository>(),
        );
      },
      child: const _DeviceDetailView(),
    );
  }
}

// Vỏ màn hình chọn loading/error/nội dung và giữ ba tab dùng chung một snapshot thiết bị.
class _DeviceDetailView extends StatelessWidget {
  const _DeviceDetailView();

  @override
  Widget build(BuildContext context) {
    // DeviceDetailState là nguồn dữ liệu của header và tab Tổng quan/Sự kiện.
    // JourneyTab tạo Cubit hành trình riêng vì có máy trạng thái phát lại độc lập.
    return BlocBuilder<DeviceDetailCubit, DeviceDetailState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state.error != null || state.device == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(state.error ?? 'Không tìm thấy thiết bị')),
          );
        }

        final device = state.device!;

        // Trạng thái header được resolve từ latest state thật và ngưỡng runtime.
        final status = DeviceStatusResolver.resolve(
          isOnline: device.isOnline,
          lastSeenAt: device.lastSeenAt,
          latestMeasuredAt: device.latestMeasuredAt,
          currentSpeedMps: device.currentSpeedMps,
          baseStatus: device.status,
        );

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            backgroundColor: context.appColors.surfaceRaised,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _DeviceDetailHeader(
                    device: device,
                    status: status,
                    onRefresh: () => context.read<DeviceDetailCubit>().load(),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _OverviewTab(
                          device: device,
                          locations: state.locations,
                          address: state.address,
                          events: state.events,
                          state: state,
                        ),
                        _JourneyTab(device: device, locations: state.locations),
                        _EventsTab(events: state.events),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Tab 1: tổng quan và bản đồ.

// Header cố định hiển thị quay lại, tên/mã, trạng thái và thao tác làm mới/chia sẻ.
class _DeviceDetailHeader extends StatelessWidget {
  const _DeviceDetailHeader({
    required this.device,
    required this.status,
    required this.onRefresh,
  });

  final DeviceModel device;
  final ResolvedDeviceStatus status;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;
    final statusText = status.connectivity == ConnectivityStatus.online
        ? 'Trực tuyến'
        : 'Ngoại tuyến';
    final statusColor = status.connectivity == ConnectivityStatus.online
        ? context.appColors.success
        : context.appColors.textSecondary;

    return Container(
      color: context.appColors.surface,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 20,
              compact ? 10 : 14,
              compact ? 12 : 20,
              0,
            ),
            child: Row(
              children: [
                _BackSquareButton(
                  compact: compact,
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    if (navigator.canPop()) {
                      navigator.pop();
                    } else {
                      context.goNamed('dashboard');
                    }
                  },
                ),
                SizedBox(width: compact ? 10 : 14),
                Container(
                  width: compact ? 34 : 38,
                  height: compact ? 34 : 38,
                  decoration: BoxDecoration(
                    color: context.appColors.primary,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: context.appColors.primary.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    DeviceIcon.iconFor(device.deviceType),
                    color: AppPalette.onAccent,
                    size: compact ? 18 : 20,
                  ),
                ),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DeviceFormatters.displayName(device),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 15 : 17,
                          fontWeight: FontWeight.w700,
                          color: context.appColors.textPrimary,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${device.deviceCode}  ·  ${DeviceFormatters.deviceTypeLabel(device.deviceType)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 11.5 : 12.5,
                          fontWeight: FontWeight.w400,
                          color: context.appColors.textSecondary,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...[
                  _HeaderStatusText(label: statusText, color: statusColor),
                  const SizedBox(width: 16),
                  _HeaderActionButton(
                    icon: Icons.refresh_rounded,
                    label: 'Làm mới',
                    onPressed: onRefresh,
                  ),
                ] else
                  IconButton(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: 'Làm mới',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: context.appColors.primary,
                unselectedLabelColor: context.appColors.textSecondary,
                dividerColor: AppPalette.transparent,
                indicatorColor: context.appColors.primary,
                indicatorWeight: 2.5,
                indicatorSize: TabBarIndicatorSize.tab,
                labelPadding: EdgeInsets.symmetric(
                  horizontal: compact ? 14 : 20,
                ),
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  Tab(height: compact ? 34 : 36, text: 'Tổng quan'),
                  Tab(height: compact ? 34 : 36, text: 'Hành trình'),
                  Tab(height: compact ? 34 : 36, text: 'Sự kiện'),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: context.appColors.borderSoft),
        ],
      ),
    );
  }
}

// Nút quay lại dạng vuông giữ vùng chạm đủ lớn và màu theo theme.
class _BackSquareButton extends StatelessWidget {
  const _BackSquareButton({required this.onPressed, this.compact = false});

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 34.0 : 38.0;
    return SizedBox(
      width: size,
      height: size,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: BorderSide(color: context.appColors.borderSoft),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          foregroundColor: context.appColors.primary,
        ),
        child: Icon(
          Icons.arrow_back_rounded,
          size: compact ? 18 : 20,
          color: context.appColors.primary,
        ),
      ),
    );
  }
}

// Nhãn trạng thái lấy từ ResolvedDeviceStatus, không tự suy luận trong widget.
class _HeaderStatusText extends StatelessWidget {
  const _HeaderStatusText({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle_rounded, size: 8, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// Nút thao tác header dùng chung icon/tooltip để hàng tiêu đề vẫn gọn.
class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: context.appColors.primary),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.appColors.primary,
        backgroundColor: context.appColors.surface,
        side: BorderSide(
          color: context.appColors.primary.withValues(alpha: 0.35),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

bool _hasText(String? value) => value?.trim().isNotEmpty == true;

// Tab Tổng quan ghép tóm tắt, bản đồ vị trí mới nhất, thông tin trực tiếp,
// chỉ số vận hành và hoạt động gần đây từ DeviceDetailState.
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.device,
    required this.locations,
    this.address,
    required this.events,
    this.state,
  });
  final DeviceModel device;
  final List<LocationModel> locations;
  final String? address;
  final List<DeviceEventModel> events;
  final DeviceDetailState? state;

  @override
  Widget build(BuildContext context) {
    // `device` chứa hồ sơ/latest state; `locations/events/address` do Cubit tải từ
    // REST/geocoding. Layout responsive chỉ đổi cách xếp các khối.
    final cubitState = state ?? context.watch<DeviceDetailCubit>().state;
    final cubit = context.read<DeviceDetailCubit>();

    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      latestMeasuredAt: device.latestMeasuredAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );
    final latestLocation = locations.isNotEmpty ? locations.first : null;
    final journey = _JourneySnapshot.from(locations);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isWide = width >= 960;
        final horizontalPadding = width < 600 ? 12.0 : 20.0;
        final mobileMapHeight = width >= 600 ? 380.0 : 320.0;

        return SingleChildScrollView(
          padding: EdgeInsets.all(horizontalPadding),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Khung chọn mốc thời gian (giữ nguyên ở đầu)
                  _OverviewTimeRangeFilterBar(
                    selectedRange: cubitState.timeRange,
                    rangeFrom: cubitState.rangeFrom,
                    rangeTo: cubitState.rangeTo,
                    isLoading: cubitState.isRangeLoading,
                    onSelectRange: (range) => cubit.setTimeRange(range),
                    onCustomRangePressed: () => _pickCustomRange(context),
                    onRefresh: () => cubit.setTimeRange(cubitState.timeRange),
                  ),
                  const SizedBox(height: 14),

                  // 2. Vùng trung tâm: Bên trái Bản đồ, Bên phải các khung thông tin trạng thái & chỉ số
                  // Chiều cao bản đồ tự động khớp theo đúng chiều cao tự nhiên của khung bên phải
                  if (isWide)
                    _AdaptiveOverviewRow(
                      spacing: 14,
                      leftFlex: 57,
                      rightFlex: 43,
                      left: _MapOverviewCard(
                        map: _MapWidget(device: device, locations: locations),
                        strip: _SummaryStrip(device: device, status: status),
                      ),
                      right: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _OverviewLiveLocationCard(
                            device: device,
                            status: status,
                            latestLocation: latestLocation,
                            address: address,
                          ),
                          const SizedBox(height: 12),
                          _OverviewMetricsDashboard(
                            journey: journey,
                            timeRangeLabel: cubitState.timeRange.label,
                          ),
                        ],
                      ),
                    )
                  else ...[
                    // Bố cục cho điện thoại và máy tính bảng nhỏ.
                    SizedBox(
                      height: mobileMapHeight,
                      child: _MapSurface(
                        child: _MapWidget(device: device, locations: locations),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _OverviewLiveLocationCard(
                      device: device,
                      status: status,
                      latestLocation: latestLocation,
                      address: address,
                      compact: true,
                    ),
                    const SizedBox(height: 12),
                    _SummaryStrip(device: device, status: status),
                    const SizedBox(height: 12),
                    _OverviewMetricsDashboard(
                      journey: journey,
                      timeRangeLabel: cubitState.timeRange.label,
                    ),
                  ],
                  const SizedBox(height: 16),

                  // 3. Khung hoạt động gần đây (ở dưới cùng)
                  _RecentActivityCard(
                    events: events,
                    device: device,
                    status: status,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickCustomRange(BuildContext context) async {
    // Khoảng tùy chỉnh được chuyển về Cubit để tải dữ liệu thật theo mốc đã chọn.
    final cubit = context.read<DeviceDetailCubit>();
    final cubitState = cubit.state;
    final now = DateTime.now();
    final defaultFrom =
        cubitState.rangeFrom ?? DateTime(now.year, now.month, now.day, 0, 0, 0);
    final defaultTo = cubitState.rangeTo ?? now;

    final result = await showCustomDateTimeRangeDialog(
      context,
      initialFrom: defaultFrom,
      initialTo: defaultTo,
    );
    if (result != null && context.mounted) {
      cubit.setTimeRange(
        OverviewTimeRange.custom,
        customFrom: result.start,
        customTo: result.end,
      );
    }
  }
}

// Dải tóm tắt ngang ở đầu tab, có thể cuộn khi các chỉ số không vừa chiều rộng.
class _SummaryStrip extends StatefulWidget {
  const _SummaryStrip({required this.device, required this.status});

  final DeviceModel device;
  final ResolvedDeviceStatus status;

  @override
  State<_SummaryStrip> createState() => _SummaryStripState();
}

class _SummaryStripState extends State<_SummaryStrip> {
  // ScrollController chỉ phục vụ dải pill và được hủy cùng widget.
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final status = widget.status;
    final theme = Theme.of(context);

    final pills = [
      _SummaryPill(
        icon: status.connectivity == ConnectivityStatus.online
            ? Icons.circle_rounded
            : Icons.circle_outlined,
        label: status.connectivity == ConnectivityStatus.online
            ? 'Trực tuyến'
            : 'Ngoại tuyến',
        color: status.color,
        primary: true,
      ),
      if (status.movement != MovementStatus.unknown)
        _SummaryPill(
          icon: status.movement == MovementStatus.moving
              ? Icons.near_me_rounded
              : Icons.pause_circle_rounded,
          label: status.movement == MovementStatus.moving
              ? 'Đang di chuyển'
              : 'Đang dừng',
          color: status.movement == MovementStatus.moving
              ? context.appColors.primaryStrong
              : context.appColors.warning,
        ),
      _SummaryPill(
        icon: status.freshness == DataFreshnessStatus.fresh
            ? Icons.gps_fixed_rounded
            : Icons.gps_not_fixed_rounded,
        label: DeviceFormatters.gpsFreshness(
          status,
          device.latestMeasuredAt ?? device.lastSeenAt,
        ),
        color: status.freshness == DataFreshnessStatus.fresh
            ? context.appColors.success
            : theme.colorScheme.error,
        subtle: status.freshness == DataFreshnessStatus.unknown,
      ),
    ];
    return Container(
      padding: EdgeInsets.zero,
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: false,
        trackVisibility: false,
        thickness: 2,
        radius: const Radius.circular(4),
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
          child: Row(
            children: [
              for (var index = 0; index < pills.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                pills[index],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Một pill tóm tắt icon/nhãn/giá trị; dữ liệu đã được format ở widget cha.
class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.icon,
    required this.label,
    required this.color,
    this.subtle = false,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool subtle;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = subtle ? theme.colorScheme.onSurfaceVariant : color;
    final background = subtle
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.58)
        : color.withValues(alpha: primary ? 0.12 : 0.08);

    return Tooltip(
      message: label,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: primary ? 180 : 220,
          minHeight: 28,
        ),
        padding: EdgeInsets.symmetric(horizontal: primary ? 8 : 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: color.withValues(alpha: primary ? 0.28 : 0.16),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (primary)
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(child: Icon(icon, size: 11, color: color)),
              )
            else
              Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: primary ? color : foreground,
                  fontWeight: primary ? FontWeight.w800 : FontWeight.w700,
                  fontSize: 12,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Khối địa chỉ ưu tiên geocoding; khi chưa có vẫn hiển thị tọa độ thật.
class _AddressInfoBlock extends StatelessWidget {
  const _AddressInfoBlock({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = _addressLines(address);

    return Tooltip(
      message: address,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: context.appColors.tealSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.appColors.tealBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: context.appColors.teal.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Center(
                child: Icon(
                  Icons.location_on_rounded,
                  size: 13,
                  color: context.appColors.teal,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lines.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      height: 1.15,
                    ),
                  ),
                  if (lines.$2.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      lines.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.appColors.textSecondary,
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                        height: 1.15,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String, String) _addressLines(String rawAddress) {
    final parts = rawAddress
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length <= 1) return (rawAddress, '');
    if (parts.length == 2) return (parts.first, parts.last);

    final firstLine = parts.take(2).join(', ');
    final secondLine = parts.skip(2).join(', ');
    return (firstLine, secondLine);
  }
}

/// Widget chia 2 cột (Trái: Bản đồ, Phải: Thông tin) trong đó chiều cao của Bản đồ (trái)
/// tự động co giãn đúng chiều cao tự nhiên của cụm thông tin bên phải trong một lượt bố trí.
// Layout hai khối tùy biến: đặt cạnh nhau khi đủ rộng và xếp dọc khi không đủ,
// bảo đảm nội dung không bị overflow theo chiều ngang.
class _AdaptiveOverviewRow extends MultiChildRenderObjectWidget {
  _AdaptiveOverviewRow({
    required this.spacing,
    required this.leftFlex,
    required this.rightFlex,
    required Widget left,
    required Widget right,
  }) : super(children: [left, right]);

  final double spacing;
  final int leftFlex;
  final int rightFlex;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderAdaptiveOverviewRow(spacing, leftFlex, rightFlex);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderAdaptiveOverviewRow renderObject,
  ) {
    renderObject
      ..spacing = spacing
      ..leftFlex = leftFlex
      ..rightFlex = rightFlex;
  }
}

// ParentData lưu offset của từng con để render object bố trí và hit-test chính xác.
class _AdaptiveOverviewRowParentData
    extends ContainerBoxParentData<RenderBox> {}

// RenderBox tự đo và đặt hai con vì Row/Flex thường không đáp ứng được yêu cầu
// chuyển ngang/dọc theo kích thước nội dung thực tế của hai card.
class _RenderAdaptiveOverviewRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AdaptiveOverviewRowParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _AdaptiveOverviewRowParentData
        > {
  _RenderAdaptiveOverviewRow(this._spacing, this._leftFlex, this._rightFlex);

  double _spacing;
  double get spacing => _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  int _leftFlex;
  int get leftFlex => _leftFlex;
  set leftFlex(int value) {
    if (_leftFlex == value) return;
    _leftFlex = value;
    markNeedsLayout();
  }

  int _rightFlex;
  int get rightFlex => _rightFlex;
  set rightFlex(int value) {
    if (_rightFlex == value) return;
    _rightFlex = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AdaptiveOverviewRowParentData) {
      child.parentData = _AdaptiveOverviewRowParentData();
    }
  }

  @override
  void performLayout() {
    // Thử bố cục ngang theo flex; khi không đủ chỗ, đo lại theo toàn chiều rộng và
    // đặt hai con thành cột để tránh cắt nội dung.
    final leftChild = firstChild;
    final rightChild = leftChild != null ? childAfter(leftChild) : null;

    if (leftChild == null || rightChild == null) {
      size = constraints.biggest;
      return;
    }

    final totalWidth = constraints.maxWidth;
    final totalFlex = leftFlex + rightFlex;
    final availableWidth = (totalWidth - spacing).clamp(0.0, double.infinity);
    final leftWidth = (availableWidth * leftFlex / totalFlex).floorToDouble();
    final rightWidth = availableWidth - leftWidth;

    // 1. Tính toán kích thước tự nhiên của cột bên phải trước
    rightChild.layout(
      BoxConstraints(
        minWidth: rightWidth,
        maxWidth: rightWidth,
        minHeight: 0,
        maxHeight: double.infinity,
      ),
      parentUsesSize: true,
    );

    final naturalHeight = rightChild.size.height;

    // 2. Định kích thước bản đồ bên trái bằng chính xác chiều cao tự nhiên của bên phải
    leftChild.layout(
      BoxConstraints.tightFor(width: leftWidth, height: naturalHeight),
      parentUsesSize: true,
    );

    // 3. Định vị trí cho 2 cột
    final leftParentData =
        leftChild.parentData! as _AdaptiveOverviewRowParentData;
    leftParentData.offset = Offset.zero;

    final rightParentData =
        rightChild.parentData! as _AdaptiveOverviewRowParentData;
    rightParentData.offset = Offset(leftWidth + spacing, 0);

    size = Size(totalWidth, naturalHeight);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }
}

// Card bản đồ nhỏ của Tổng quan, nhận tọa độ đã xác nhận từ DeviceModel.
class _MapOverviewCard extends StatelessWidget {
  const _MapOverviewCard({required this.map, required this.strip});

  final Widget map;
  final Widget strip;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _referenceCardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(child: map),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: context.appColors.surface,
              border: Border(
                top: BorderSide(color: context.appColors.borderSoft),
              ),
            ),
            child: strip,
          ),
        ],
      ),
    );
  }
}

// Vỏ bề mặt bản đồ giữ bo góc/clip và trạng thái thiếu tọa độ thống nhất.
class _MapSurface extends StatelessWidget {
  const _MapSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _referenceCardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

BoxDecoration _referenceCardDecoration(BuildContext context) {
  return BoxDecoration(
    color: context.appColors.surface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: context.appColors.borderSoft),
    boxShadow: [
      BoxShadow(
        color: context.appColors.shadow.withValues(alpha: 0.035),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

// Thanh lọc khoảng thời gian ở trang tổng quan.

// Thanh chọn khoảng dữ liệu cho các chỉ số; callback yêu cầu Cubit tải lại.
class _OverviewTimeRangeFilterBar extends StatelessWidget {
  const _OverviewTimeRangeFilterBar({
    required this.selectedRange,
    required this.rangeFrom,
    required this.rangeTo,
    required this.isLoading,
    required this.onSelectRange,
    required this.onCustomRangePressed,
    required this.onRefresh,
  });

  final OverviewTimeRange selectedRange;
  final DateTime? rangeFrom;
  final DateTime? rangeTo;
  final bool isLoading;
  final ValueChanged<OverviewTimeRange> onSelectRange;
  final VoidCallback onCustomRangePressed;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final dtFormat = DateFormat('dd/MM/yyyy HH:mm');
    final from = rangeFrom ?? DateTime.now();
    final to = rangeTo ?? DateTime.now();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.borderSoft),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 860;

          final timeBox = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: InkWell(
              onTap: onCustomRangePressed,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: context.appColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.appColors.borderSoft),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Từ ',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.appColors.textSecondary,
                      ),
                    ),
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 13,
                      color: context.appColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      dtFormat.format(from),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: context.appColors.textPrimary,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 12,
                        color: context.appColors.textSecondary,
                      ),
                    ),
                    Text(
                      'Đến ',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.appColors.textSecondary,
                      ),
                    ),
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 13,
                      color: context.appColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      dtFormat.format(to),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: context.appColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          final chips = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: OverviewTimeRange.values.map((range) {
                final isSelected = selectedRange == range;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () {
                      if (range == OverviewTimeRange.custom) {
                        onCustomRangePressed();
                      } else {
                        onSelectRange(range);
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? context.appColors.primary.withValues(alpha: 0.1)
                            : context.appColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? context.appColors.primary
                              : context.appColors.border,
                          width: isSelected ? 1.2 : 1.0,
                        ),
                      ),
                      child: Text(
                        range.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? context.appColors.primary
                              : context.appColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );

          final reloadButton = FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: isLoading ? null : onRefresh,
            icon: isLoading
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppPalette.onAccent,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 15),
            label: const Text(
              'Tải lại',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          );

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Nhóm A: Khoảng thời gian
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Khoảng thời gian',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.appColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    timeBox,
                  ],
                ),
                const SizedBox(width: 16),
                SizedBox(
                  height: 38,
                  child: VerticalDivider(
                    width: 1,
                    color: context.appColors.borderSoft,
                  ),
                ),
                const SizedBox(width: 16),

                // Nhóm B: Khoảng nhanh
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Khoảng nhanh',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      chips,
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  height: 38,
                  child: VerticalDivider(
                    width: 1,
                    color: context.appColors.borderSoft,
                  ),
                ),
                const SizedBox(width: 16),

                // Nhóm C: Tải lại
                reloadButton,
              ],
            );
          }

          // Bố cục khi màn hình điện thoại hoặc máy tính bảng bị hẹp.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              timeBox,
              const SizedBox(height: 10),
              chips,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: reloadButton),
            ],
          );
        },
      ),
    );
  }
}

// Card vị trí hiện tại hiển thị địa chỉ, tọa độ, mốc đo/nhận và thao tác bản đồ.
class _OverviewLiveLocationCard extends StatelessWidget {
  const _OverviewLiveLocationCard({
    required this.device,
    required this.status,
    required this.latestLocation,
    this.address,
    this.compact = false,
  });

  final DeviceModel device;
  final ResolvedDeviceStatus status;
  final LocationModel? latestLocation;
  final String? address;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final speed = DeviceFormatters.speed(device, status);
    final isMoving = status.movement == MovementStatus.moving;
    final isStopped = status.movement == MovementStatus.stopped;
    final movementStatusLabel = isMoving
        ? 'Đang di chuyển'
        : (isStopped ? 'Đang dừng' : 'Không xác định');
    final movementStatusColor = isMoving
        ? context.appColors.success
        : (isStopped
              ? context.appColors.warning
              : context.appColors.textSecondary);

    final cardTitle = status.freshness == DataFreshnessStatus.stale
        ? 'Vị trí gần nhất'
        : 'Vị trí hiện tại';
    final lastUpdatedTime = DeviceFormatters.dateTime(
      latestLocation?.measuredAt ??
          device.latestMeasuredAt ??
          device.lastSeenAt,
    );

    return Card(
      elevation: 0,
      color: context.appColors.surface,
      shadowColor: context.appColors.shadow.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: context.appColors.borderSoft),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTightlyBounded =
              constraints.hasBoundedHeight && constraints.maxHeight > 260;
          final panelPadding = compact ? 10.0 : 12.0;

          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: isTightlyBounded
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.start,
            mainAxisSize: isTightlyBounded
                ? MainAxisSize.max
                : MainAxisSize.min,
            children: [
              // Phần đầu: tiêu đề vị trí và nút xem thông số kỹ thuật.
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: context.appColors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.location_on_rounded,
                      size: 16,
                      color: context.appColors.teal,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showDeviceTechnicalInfoModal(
                      context,
                      device: device,
                      latestLocation: latestLocation,
                      status: status,
                    ),
                    icon: const Icon(Icons.info_outline_rounded, size: 18),
                    color: context.appColors.primary,
                    tooltip: 'Thông tin thiết bị',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ],
              ),
              if (!isTightlyBounded) const SizedBox(height: 10),

              // 2. Speed & Movement Highlight Banner
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: context.appColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.appColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: context.appColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.speed_rounded,
                        size: 18,
                        color: context.appColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TỐC ĐỘ HIỆN TẠI',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: context.appColors.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            speed,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: context.appColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: movementStatusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        movementStatusLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: movementStatusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isTightlyBounded) const SizedBox(height: 10),

              // 3. Address / Coordinates Detail
              if (_hasText(address)) ...[
                _AddressInfoBlock(address: address!.trim()),
                if (!isTightlyBounded) const SizedBox(height: 6),
              ],

              // 4. Coordinates & Last Updated timestamp
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: context.appColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.appColors.borderSoft),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.my_location_rounded,
                          size: 14,
                          color: context.appColors.teal,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Tọa độ GPS:',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: context.appColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            DeviceFormatters.coordinatePair(
                              device.latitude,
                              device.longitude,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: context.appColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 14,
                          color: context.appColors.orange,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Thời điểm:',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: context.appColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            lastUpdatedTime,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  status.freshness == DataFreshnessStatus.fresh
                                  ? context.appColors.textPrimary
                                  : theme.colorScheme.error,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isTightlyBounded) const SizedBox(height: 12),

              // Phần thao tác cuối: chia sẻ vị trí và mở hành trình.
              Row(
                children: [
                  Expanded(child: _ShareLocationInlineButton(device: device)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          DefaultTabController.of(context).animateTo(1),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.appColors.primary,
                        side: BorderSide(color: context.appColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.timeline_rounded, size: 16),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Xem hành trình',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: context.appColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          return Padding(
            padding: EdgeInsets.all(panelPadding),
            child: isTightlyBounded
                ? content
                : SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: content,
                  ),
          );
        },
      ),
    );
  }
}

// ─── Metrics Dashboard (4 Core Statistic Cards) ──────────────────────────────

// Lưới chỉ số tính từ DeviceModel và mẫu lịch sử trong khoảng đang chọn.
class _OverviewMetricsDashboard extends StatelessWidget {
  const _OverviewMetricsDashboard({required this.journey, this.timeRangeLabel});

  final _JourneySnapshot journey;
  final String? timeRangeLabel;

  @override
  Widget build(BuildContext context) {
    final distanceStr = journey.distanceM != null
        ? DeviceFormatters.distance(journey.distanceM)
        : '--';
    final movingStr = journey.movingDurationS != null
        ? DeviceFormatters.secondsDuration(journey.movingDurationS)
        : '--';
    final stoppedStr = journey.stoppedDurationS != null
        ? DeviceFormatters.secondsDuration(journey.stoppedDurationS)
        : '--';
    final avgSpeedStr = journey.avgSpeedMps != null
        ? DeviceFormatters.speedMps(journey.avgSpeedMps)
        : '--';
    final maxSpeedStr = journey.maxSpeedMps != null
        ? DeviceFormatters.speedMps(journey.maxSpeedMps)
        : '--';
    final startedStr = journey.startedAt != null
        ? _formatMetricDateTime(journey.startedAt)
        : '--';
    final endedStr = journey.endedAt != null
        ? _formatMetricDateTime(journey.endedAt)
        : (journey.startedAt != null
              ? _formatMetricDateTime(journey.startedAt)
              : '--');

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100 ? 4 : (width >= 280 ? 2 : 1);
        const spacing = 10.0;

        final cards = [
          _MetricDashboardCard(
            title: 'TỔNG QUÃNG ĐƯỜNG',
            icon: Icons.route_rounded,
            iconColor: context.appColors.orange,
            accentBg: context.appColors.orangeSoft,
            primaryValue: distanceStr,
            primaryLabel: timeRangeLabel != null
                ? 'Trong $timeRangeLabel'
                : 'Khoảng thời gian đã chọn',
            extraInfo: journey.sampleCount > 0
                ? '${journey.sampleCount} điểm GPS'
                : null,
          ),
          _MetricDashboardCard(
            title: 'THỜI GIAN HOẠT ĐỘNG',
            icon: Icons.timer_outlined,
            iconColor: context.appColors.success,
            accentBg: context.appColors.successSoft,
            labelWidth: 42.0,
            dualRows: [
              (
                icon: Icons.play_arrow_rounded,
                label: 'Chạy:',
                value: movingStr,
                color: context.appColors.success,
              ),
              (
                icon: Icons.pause_rounded,
                label: 'Dừng:',
                value: stoppedStr,
                color: context.appColors.warning,
              ),
            ],
          ),
          _MetricDashboardCard(
            title: 'VẬN TỐC HÀNH TRÌNH',
            icon: Icons.speed_rounded,
            iconColor: context.appColors.primaryStrong,
            accentBg: context.appColors.primarySoft,
            labelWidth: 66.0,
            dualRows: [
              (
                icon: Icons.trending_flat_rounded,
                label: 'Trung bình:',
                value: avgSpeedStr,
                color: context.appColors.primaryStrong,
              ),
              (
                icon: Icons.flash_on_rounded,
                label: 'Tối đa:',
                value: maxSpeedStr,
                color: context.appColors.danger,
              ),
            ],
          ),
          _MetricDashboardCard(
            title: 'KHUNG THỜI GIAN',
            icon: Icons.calendar_today_rounded,
            iconColor: context.appColors.purple,
            accentBg: context.appColors.purpleSoft,
            labelWidth: 56.0,
            dualRows: [
              (
                icon: Icons.play_circle_outline_rounded,
                label: 'Bắt đầu:',
                value: startedStr,
                color: context.appColors.purple,
              ),
              (
                icon: Icons.flag_outlined,
                label: 'Kết thúc:',
                value: endedStr,
                color: context.appColors.textSecondary,
              ),
            ],
          ),
        ];

        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: spacing),
                cards[i],
              ],
            ],
          );
        }

        if (columns == 2) {
          final isBounded = constraints.hasBoundedHeight;
          final row1 = Row(
            crossAxisAlignment: isBounded
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.start,
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: spacing),
              Expanded(child: cards[1]),
            ],
          );
          final row2 = Row(
            crossAxisAlignment: isBounded
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.start,
            children: [
              Expanded(child: cards[2]),
              const SizedBox(width: spacing),
              Expanded(child: cards[3]),
            ],
          );

          if (isBounded) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: row1),
                const SizedBox(height: spacing),
                Expanded(child: row2),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              row1,
              const SizedBox(height: spacing),
              row2,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: spacing),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  static String _formatMetricDateTime(DateTime? dt) {
    if (dt == null) return '--';
    final local = dt.toLocal();
    final now = DateTime.now();
    if (local.year == now.year) {
      return DateFormat('dd/MM HH:mm').format(local);
    }
    return DateFormat('dd/MM/yy HH:mm').format(local);
  }
}

// Một thẻ chỉ số gồm icon, giá trị, đơn vị và mô tả; lưới cha quyết định số cột.
class _MetricDashboardCard extends StatelessWidget {
  const _MetricDashboardCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.accentBg,
    this.primaryValue,
    this.primaryLabel,
    this.extraInfo,
    this.dualRows,
    this.labelWidth,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final Color accentBg;
  final String? primaryValue;
  final String? primaryLabel;
  final String? extraInfo;
  final List<({IconData icon, String label, String value, Color color})>?
  dualRows;
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveLabelWidth =
        labelWidth ??
        (dualRows != null && dualRows!.any((r) => r.label.length > 8)
            ? 66.0
            : (dualRows != null && dualRows!.any((r) => r.label.length > 5)
                  ? 56.0
                  : 42.0));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.borderSoft),
        boxShadow: [
          BoxShadow(
            color: context.appColors.shadow.withValues(alpha: 0.025),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, cardConstraints) {
          final isBounded = cardConstraints.hasBoundedHeight;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: isBounded
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.start,
            mainAxisSize: isBounded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              // Phần đầu: biểu tượng, tiêu đề và thông tin bổ sung.
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: accentBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, size: 13, color: iconColor),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: context.appColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  if (extraInfo != null) ...[
                    const SizedBox(width: 4),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.appColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          extraInfo!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: context.appColors.textSecondary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (!isBounded) const SizedBox(height: 8),

              // Nội dung: một giá trị lớn hoặc hai hàng giá trị.
              if (primaryValue != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      primaryValue!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                        height: 1.15,
                      ),
                    ),
                    if (primaryLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        primaryLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.appColors.textSecondary,
                          fontWeight: FontWeight.w500,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ] else if (dualRows != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < dualRows!.length; i++) ...[
                      if (i > 0) const SizedBox(height: 5),
                      Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: Center(
                              child: Icon(
                                dualRows![i].icon,
                                size: 13,
                                color: dualRows![i].color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          SizedBox(
                            width: effectiveLabelWidth,
                            child: Text(
                              dualRows![i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: context.appColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              dualRows![i].value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: context.appColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// Khối thông tin kỹ thuật của thiết bị.

// Modal gom hồ sơ thiết bị và latest state thật; bottom sheet cuộn giữ nội dung dài
// không làm thay đổi bố cục trang chi tiết chính.
void _showDeviceTechnicalInfoModal(
  BuildContext context, {
  required DeviceModel device,
  required LocationModel? latestLocation,
  required ResolvedDeviceStatus status,
}) {
  final modelManufacturer = [
    device.model,
    device.manufacturer,
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');

  final altitudeM = device.currentAltitudeM ?? latestLocation?.altitudeM;
  final accuracyM = latestLocation?.accuracyM;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppPalette.transparent,
    builder: (modalContext) {
      final theme = Theme.of(modalContext);
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(modalContext).size.height * 0.85,
          maxWidth: 680,
        ),
        margin: const EdgeInsets.only(top: 40),
        decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: context.appColors.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Phần đầu hộp thoại.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: context.appColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.memory_rounded,
                      size: 18,
                      color: context.appColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Thông số kỹ thuật thiết bị',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: context.appColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DeviceFormatters.displayName(device),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: context.appColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(modalContext).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Đóng',
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.appColors.borderSoft),

            // Nội dung có thể cuộn.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Nhóm 1: thông tin phần cứng.
                    _buildTechSectionTitle(
                      context: context,
                      icon: Icons.devices_other_rounded,
                      title: 'Thông tin phần cứng',
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: context.appColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.appColors.border),
                      ),
                      child: Column(
                        children: [
                          _buildTechRow(
                            context,
                            'Tên thiết bị',
                            DeviceFormatters.displayName(device),
                          ),
                          _buildTechRow(
                            context,
                            'Mã định danh',
                            device.deviceCode,
                          ),
                          _buildTechRow(
                            context,
                            'Loại phương tiện',
                            DeviceFormatters.deviceTypeLabel(device.deviceType),
                          ),
                          _buildTechRow(
                            context,
                            'Model / Hãng',
                            modelManufacturer.isNotEmpty
                                ? modelManufacturer
                                : '--',
                          ),
                          _buildTechRow(
                            context,
                            'Số Serial / IMEI',
                            device.serialNumber ?? '--',
                          ),
                          _buildTechRow(
                            context,
                            'Phiên bản Firmware',
                            device.firmwareVersion ?? '--',
                          ),
                          // Mức pin lấy từ trạng thái mới nhất của chính thiết bị.
                          // Giá trị chưa được thiết bị gửi sẽ hiển thị "--" thay vì 0%.
                          _buildTechRow(
                            context,
                            'Pin thiết bị',
                            DeviceFormatters.batteryPct(device.batteryPct),
                          ),
                          _buildTechRow(
                            context,
                            'Trạng thái',
                            device.statusLabel,
                            valueColor:
                                status.connectivity == ConnectivityStatus.online
                                ? context.appColors.success
                                : context.appColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Nhóm 2: vị trí và cảm biến GPS.
                    _buildTechSectionTitle(
                      context: context,
                      icon: Icons.satellite_alt_rounded,
                      title: 'Thông số GPS & Vệ tinh',
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: context.appColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.appColors.border),
                      ),
                      child: Column(
                        children: [
                          _buildTechRow(
                            context,
                            'Tọa độ GPS',
                            DeviceFormatters.coordinatePair(
                              device.latitude,
                              device.longitude,
                            ),
                          ),
                          _buildTechRow(
                            context,
                            'Độ cao',
                            altitudeM != null
                                ? '${altitudeM.toStringAsFixed(1)} m'
                                : '--',
                          ),
                          _buildTechRow(
                            context,
                            'Độ chính xác vệ tinh',
                            accuracyM != null
                                ? '±${accuracyM.toStringAsFixed(0)} m'
                                : '--',
                          ),
                          _buildTechRow(
                            context,
                            'Số lượng vệ tinh',
                            latestLocation?.satelliteCount != null
                                ? '${latestLocation!.satelliteCount} vệ tinh'
                                : '--',
                          ),
                          _buildTechRow(
                            context,
                            'Thời điểm GPS',
                            DeviceFormatters.dateTime(
                              latestLocation?.measuredAt ??
                                  device.latestMeasuredAt ??
                                  device.lastSeenAt,
                            ),
                          ),
                        ],
                      ),
                    ),
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

// Tiêu đề phân nhóm icon + text trong modal thông tin kỹ thuật.
Widget _buildTechSectionTitle({
  required BuildContext context,
  required IconData icon,
  required String title,
}) {
  return Row(
    children: [
      Icon(icon, size: 16, color: context.appColors.primary),
      const SizedBox(width: 8),
      Text(
        title,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          color: context.appColors.textPrimary,
        ),
      ),
    ],
  );
}

// Một hàng label/value trong modal; Expanded cho phép giá trị dài tự xuống dòng.
Widget _buildTechRow(
  BuildContext context,
  String label,
  String value, {
  Color? valueColor,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.appColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: valueColor ?? context.appColors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

// Card hoạt động gần đây hiển thị DeviceEventModel mới nhất do backend sinh.
class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({
    required this.events,
    required this.device,
    required this.status,
  });

  final List<DeviceEventModel> events;
  final DeviceModel device;
  final ResolvedDeviceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recentEvents = events.take(5).toList();

    return Card(
      elevation: 0,
      color: context.appColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: context.appColors.borderSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.timeline_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hoạt động gần đây',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      DefaultTabController.of(context).animateTo(2),
                  child: const Text('Xem tất cả'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (recentEvents.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_busy_rounded,
                      size: 16,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Chưa có hoạt động gần đây',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 760) {
                    const spacing = 12.0;
                    final columns = constraints.maxWidth >= 1120 ? 4 : 2;
                    final itemWidth =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                        columns;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: 6,
                      children: [
                        for (final event in recentEvents.take(4))
                          SizedBox(
                            width: itemWidth,
                            child: _RecentActivityRow(
                              event: event,
                              compact: true,
                            ),
                          ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      for (final event in recentEvents)
                        _RecentActivityRow(event: event),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// Một sự kiện gần đây gồm màu theo loại, mô tả và thời điểm thật từ server.
class _RecentActivityRow extends StatelessWidget {
  const _RecentActivityRow({required this.event, this.compact = false});

  final DeviceEventModel event;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = event.source?.trim();
    final metaText = source == null || source.isEmpty
        ? DeviceFormatters.dateTime(event.occurredAt)
        : '${DeviceFormatters.dateTime(event.occurredAt)} · $source';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Icon(
              Icons.circle_rounded,
              size: 12,
              color: _eventAccent(event.eventType, context.appColors),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DeviceFormatters.eventLabel(event),
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  metaText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _eventAccent(String type, AppThemeColors colors) {
  // Ánh xạ loại sự kiện sang màu ngữ nghĩa của theme, không hard-code mã màu.
  switch (type) {
    case 'MOVEMENT_STOPPED':
    case 'IDLE':
      return colors.warning;
    case 'MOVEMENT_STARTED':
    case 'MOVING':
      return colors.primary;
    case 'ONLINE':
    case 'GPS_RESTORED':
      return colors.success;
    default:
      return colors.textSecondary;
  }
}

// Kết quả tổng hợp nội bộ cho phần Tổng quan: quãng đường, tốc độ và thời lượng
// được tính từ LocationModel hợp lệ trong khoảng đang chọn.
class _JourneySnapshot {
  const _JourneySnapshot({
    this.distanceM,
    this.movingDurationS,
    this.stoppedDurationS,
    this.avgSpeedMps,
    this.maxSpeedMps,
    this.startedAt,
    this.endedAt,
    this.sampleCount = 0,
  });

  final double? distanceM;
  final int? movingDurationS;
  final int? stoppedDurationS;
  final double? avgSpeedMps;
  final double? maxSpeedMps;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int sampleCount;

  bool get hasData =>
      distanceM != null ||
      movingDurationS != null ||
      stoppedDurationS != null ||
      avgSpeedMps != null ||
      maxSpeedMps != null ||
      startedAt != null;

  static _JourneySnapshot from(
    List<LocationModel> locations, {
    Duration gapThreshold = const Duration(minutes: 5),
    double? movingThresholdMps,
  }) {
    if (locations.isEmpty) return const _JourneySnapshot();

    // 1. Loại tọa độ sai và các điểm GPS nhảy bất thường.
    final validSamples = GpsValidator.sanitizeSamples(locations);
    if (validSamples.isEmpty) return const _JourneySnapshot();

    // 2. Chia thành các đoạn bằng ngưỡng mất dữ liệu đang áp dụng cho hệ thống.
    final segments = RouteSegment.splitIntoSegments(
      validSamples,
      gapThreshold: gapThreshold,
      movingThresholdMps:
          movingThresholdMps ?? DeviceStatusResolver.movingThresholdMps,
    );

    var totalDistance = 0.0;
    var totalMoving = 0;
    var totalStopped = 0;
    double? maxSpeed;
    var speedSum = 0.0;
    var speedCount = 0;

    for (final segment in segments) {
      totalDistance += segment.distanceM;
      totalMoving += segment.movingDurationS;
      totalStopped += segment.stoppedDurationS;
      if (segment.maxSpeedMps != null) {
        if (maxSpeed == null || segment.maxSpeedMps! > maxSpeed) {
          maxSpeed = segment.maxSpeedMps;
        }
      }
      if (segment.avgSpeedMps != null) {
        speedSum += segment.avgSpeedMps! * segment.sampleCount;
        speedCount += segment.sampleCount;
      }
    }

    final avgSpeed = speedCount > 0 ? (speedSum / speedCount) : null;
    final sorted = List<LocationModel>.from(validSamples)
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));

    return _JourneySnapshot(
      distanceM: totalDistance > 0 ? totalDistance : null,
      movingDurationS: totalMoving > 0 ? totalMoving : null,
      stoppedDurationS: totalStopped > 0 ? totalStopped : null,
      avgSpeedMps: avgSpeed,
      maxSpeedMps: maxSpeed,
      startedAt: sorted.isEmpty ? null : sorted.first.measuredAt,
      endedAt: sorted.length < 2 ? null : sorted.last.measuredAt,
      sampleCount: validSamples.length,
    );
  }
}

// Bản đồ vị trí hiện tại dùng trong Tổng quan, nhận DeviceModel đã có tọa độ/latest state.
class _MapWidget extends StatefulWidget {
  const _MapWidget({required this.device, required this.locations});
  final DeviceModel device;
  final List<LocationModel> locations;

  @override
  State<_MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<_MapWidget> {
  // Camera và zoom là state trình bày; fallback center chỉ dùng khi chưa có tọa độ.
  static const _initialZoom = 15.0;
  static const _minZoom = 5.0;
  static const _maxZoom = 18.0;
  static const _zoomStep = 1.0;
  static const _fallbackCenter = LatLng(21.0285, 105.8542);

  final MapController _mapController = MapController();
  late LatLng _targetCenter;
  var _zoom = _initialZoom;
  var _mapReady = false;

  @override
  void initState() {
    super.initState();
    _targetCenter = _resolveCenter();
  }

  @override
  void didUpdateWidget(covariant _MapWidget oldWidget) {
    // Khi vị trí thiết bị đổi từ realtime, camera chỉ cập nhật theo quy tắc hiện có
    // và không tạo lại MapController.
    super.didUpdateWidget(oldWidget);
    final nextCenter = _resolveCenter();
    if (!_samePoint(nextCenter, _targetCenter)) {
      _targetCenter = nextCenter;
      if (_mapReady) {
        _mapController.move(_targetCenter, _zoom, id: 'device-update');
      }
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tile lấy theo SettingsCubit, marker lấy từ device/status; lớp điều khiển nổi
    // nằm trên FlutterMap trong cùng Stack.
    final mapType = context.watch<SettingsCubit>().state.userSettings.mapType;
    final isSatellite = mapType == AppMapType.satellite;
    final hasPosition =
        widget.device.latitude != null && widget.device.longitude != null;
    final status = DeviceStatusResolver.resolve(
      isOnline: widget.device.isOnline,
      lastSeenAt: widget.device.lastSeenAt,
      latestMeasuredAt: widget.device.latestMeasuredAt,
      currentSpeedMps: widget.device.currentSpeedMps,
      baseStatus: widget.device.status,
    );
    if (!hasPosition && widget.locations.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_off_rounded,
                size: 36,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 8),
              Text(
                'Chưa có dữ liệu vị trí',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: context.appColors.mapBackground,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _targetCenter,
                initialZoom: _zoom,
                minZoom: _minZoom,
                maxZoom: _maxZoom,
                onMapReady: () {
                  _mapReady = true;
                  _mapController.move(_targetCenter, _zoom, id: 'map-ready');
                },
                onPositionChanged: (camera, hasGesture) {
                  if (!mounted || camera.zoom == _zoom) return;
                  setState(() => _zoom = camera.zoom);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: MapTileProviders.getUrl(
                    isSatellite ? AppMapType.satellite : AppMapType.standard,
                  ),
                  userAgentPackageName: 'com.vmonitor.app',
                  minZoom: _minZoom,
                  maxZoom: _maxZoom,
                  maxNativeZoom: MapTileProviders.getMaxZoom(
                    isSatellite ? AppMapType.satellite : AppMapType.standard,
                  ),
                  tileProvider: NetworkTileProvider(silenceExceptions: true),
                  errorImage: MemoryImage(TileProvider.transparentImage),
                ),
                if (hasPosition || widget.locations.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _targetCenter,
                        width: 44,
                        height: 50,
                        alignment: Alignment.topCenter,
                        child: _DeviceMapMarker(
                          icon: DeviceIcon.iconFor(widget.device.deviceType),
                          color: _markerColor(status),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          top: 0,
          bottom: 0,
          child: Center(
            child: _MapControls(
              onZoomIn: () => _zoomBy(_zoomStep),
              onZoomOut: () => _zoomBy(-_zoomStep),
              onCenter: _centerOnTarget,
              onToggleMapType: () =>
                  context.read<SettingsCubit>().updateMapType(
                    isSatellite ? AppMapType.standard : AppMapType.satellite,
                  ),
              isSatellite: isSatellite,
            ),
          ),
        ),
      ],
    );
  }

  LatLng _resolveCenter() {
    if (widget.device.latitude != null && widget.device.longitude != null) {
      return LatLng(widget.device.latitude!, widget.device.longitude!);
    }
    if (widget.locations.isNotEmpty) {
      final latest = widget.locations.first;
      return LatLng(latest.latitude, latest.longitude);
    }
    return _fallbackCenter;
  }

  bool _samePoint(LatLng a, LatLng b) {
    return a.latitude == b.latitude && a.longitude == b.longitude;
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    final camera = _mapController.camera;
    final nextZoom = (camera.zoom + delta).clamp(_minZoom, _maxZoom).toDouble();
    _zoom = nextZoom;
    _mapController.move(camera.center, nextZoom, id: 'map-zoom');
  }

  void _centerOnTarget() {
    if (!_mapReady) return;
    _mapController.move(_targetCenter, _zoom, id: 'map-center-device');
  }

  Color _markerColor(ResolvedDeviceStatus status) {
    if (status.connectivity == ConnectivityStatus.offline) {
      return context.appColors.offline;
    }
    if (status.freshness == DataFreshnessStatus.stale) {
      return context.appColors.danger;
    }
    if (status.movement == MovementStatus.moving) {
      return context.appColors.primaryStrong;
    }
    return context.appColors.success;
  }
}

// Marker vị trí hiện tại hiển thị icon loại thiết bị và hướng nếu có dữ liệu heading.
class _DeviceMapMarker extends StatelessWidget {
  const _DeviceMapMarker({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('overview-device-marker'),
      width: 44,
      height: 50,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 28,
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppPalette.onAccent, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.28),
                      blurRadius: 12,
                      spreadRadius: 1,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: AppPalette.onAccent, width: 3),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.32),
                  blurRadius: 12,
                  spreadRadius: 2,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(icon, color: AppPalette.onAccent, size: 18),
          ),
        ],
      ),
    );
  }
}

// Cụm zoom/căn giữa/đổi tile cho bản đồ Tổng quan.
class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onCenter,
    required this.onToggleMapType,
    required this.isSatellite,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCenter;
  final VoidCallback onToggleMapType;
  final bool isSatellite;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cụm 1: Phóng to, thu nhỏ, căn giữa thiết bị
        DecoratedBox(
          decoration: _mapControlDecoration(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MapControlButton(
                icon: Icons.add_rounded,
                tooltip: 'Phóng to bản đồ',
                onPressed: onZoomIn,
              ),
              const SizedBox(width: 34, child: Divider(height: 1)),
              _MapControlButton(
                icon: Icons.remove_rounded,
                tooltip: 'Thu nhỏ bản đồ',
                onPressed: onZoomOut,
              ),
              const SizedBox(width: 34, child: Divider(height: 1)),
              _MapControlButton(
                icon: Icons.my_location_rounded,
                tooltip: 'Căn giữa thiết bị',
                onPressed: onCenter,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Cụm 2: Chuyển đổi mode bản đồ riêng biệt
        DecoratedBox(
          decoration: _mapControlDecoration(context),
          child: _MapControlButton(
            icon: isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
            tooltip: isSatellite
                ? 'Chuyển sang bản đồ đường phố'
                : 'Chuyển sang bản đồ vệ tinh',
            iconColor: context.appColors.primary,
            onPressed: onToggleMapType,
          ),
        ),
      ],
    );
  }

  BoxDecoration _mapControlDecoration(BuildContext context) {
    return BoxDecoration(
      color: context.appColors.surface.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.appColors.borderSoft),
      boxShadow: [
        BoxShadow(
          color: context.appColors.shadow.withValues(alpha: 0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}

// Nút điều khiển bản đồ có tooltip và vùng chạm đồng nhất.
class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 34,
        height: 34,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          splashRadius: 18,
          icon: Icon(icon, size: 18, color: context.appColors.primary),
        ),
      ),
    );
  }
}

// Tab 2: hành trình GPS và phát lại.

// Tab Hành trình sở hữu JourneyHistoryCubit để tải khoảng thời gian, tính đoạn đường
// và điều khiển playback độc lập với tab Tổng quan.
class _JourneyTab extends StatefulWidget {
  const _JourneyTab({required this.device, required this.locations});

  final DeviceModel device;
  final List<LocationModel> locations;

  @override
  State<_JourneyTab> createState() => _JourneyTabState();
}

class _JourneyTabState extends State<_JourneyTab> {
  // Chỉ số preset là state UI; dữ liệu lịch sử và con trỏ playback nằm trong Cubit.
  late JourneyHistoryCubit _cubit;
  late DateTime _fromTime;
  late DateTime _toTime;
  int _rangePresetIndex =
      0; // 0: Hôm nay, 1: Hôm qua, 2: 24h qua, 3: 7 ngày, 4: Tùy chọn

  @override
  void initState() {
    super.initState();
    _cubit = JourneyHistoryCubit(
      trackingRepo: context.read<TrackingRepository>(),
      deviceRepo: context.read<DeviceRepository>(),
      settingsRepo: context.read<SettingsRepository>(),
    );
    _cubit.selectDevice(widget.device);

    final now = DateTime.now();
    _fromTime = DateTime(now.year, now.month, now.day, 0, 0, 0);
    _toTime = now;

    _fetchHistory();
  }

  @override
  void didUpdateWidget(covariant _JourneyTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _cubit.selectDevice(widget.device);
      _fetchHistory();
    }
  }

  void _fetchHistory() {
    // Gửi device id và khoảng đang chọn tới Cubit; repository gọi endpoint range thật.
    _cubit.loadHistory(
      deviceId: widget.device.id,
      from: _fromTime,
      to: _toTime,
    );
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // BlocBuilder dựng panel lọc, số liệu, bản đồ phát lại và timeline từ cùng
    // JourneyHistoryState để các khối luôn đồng bộ một mốc playback.
    return BlocProvider.value(
      value: _cubit,
      child: BlocConsumer<JourneyHistoryCubit, JourneyHistoryState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: context.appColors.danger,
              ),
            );
          }
        },
        builder: (context, state) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final padding = width < 720 ? 12.0 : 20.0;
              final isDesktop = width >= 1100;
              const desktopMainPanelHeight = 596.0;

              return ListView(
                padding: EdgeInsets.all(padding),
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Tầng 1: bảng lọc khoảng thời gian.
                          _JourneyFilterPanel(
                            fromTime: _fromTime,
                            toTime: _toTime,
                            presetIndex: _rangePresetIndex,
                            gapThreshold: state.gapThreshold,
                            isLoading: state.isLoading,
                            onPresetSelected: _onPresetSelected,
                            onCustomRangePressed: () =>
                                _openCustomDateTimeRangePicker(context),
                            onGapChanged: (gap) => _cubit.setGapThreshold(gap),
                            onRefresh: _fetchHistory,
                          ),
                          const SizedBox(height: 12),

                          // ─── TẦNG 2: Metric Cards (KPI hành trình) ───────────
                          _JourneyMetricsRow(state: state),
                          const SizedBox(height: 12),

                          // ─── TẦNG 3: Vùng Vận Hành Chính (Main Area) ─────────
                          if (isDesktop)
                            SizedBox(
                              height: desktopMainPanelHeight,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Cột trái: bản đồ tự co, phát lại và dữ liệu mốc hiện tại.
                                  Expanded(
                                    flex: 77,
                                    child: Column(
                                      key: const Key(
                                        'journey-desktop-left-panel',
                                      ),
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // 1. Map nhận toàn bộ chiều cao còn lại.
                                        Expanded(
                                          child: _JourneyMapCard(
                                            state: state,
                                            onPointSelected: (pt) =>
                                                _cubit.selectPoint(pt),
                                          ),
                                        ),
                                        const SizedBox(height: 10),

                                        // Thẻ điều khiển phát lại.
                                        _JourneyPlaybackCard(
                                          state: state,
                                          onPlay: () => _cubit.play(),
                                          onPause: () => _cubit.pause(),
                                          onResume: () => _cubit.resume(),
                                          onReset: () => _cubit.reset(),
                                          onStepBackward30s: _stepBackward30s,
                                          onStepBackward60s: _stepBackward60s,
                                          onStepForward30s: _stepForward30s,
                                          onStepForward60s: _stepForward60s,
                                          onSeekProgress: (p) =>
                                              _cubit.seekToProgress(p),
                                          onSpeedChanged: (s) =>
                                              _cubit.setPlaybackSpeed(s),
                                          onFollowChanged: (f) =>
                                              _cubit.toggleFollowCamera(f),
                                        ),
                                        const SizedBox(height: 10),

                                        // Thẻ dữ liệu tại mốc hiện tại.
                                        _JourneyCurrentInfoCard(state: state),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // CỘT PHẢI (~23%): dòng thời gian dọc.
                                  Expanded(
                                    flex: 23,
                                    child: _JourneyTimelineCard(
                                      key: const Key('journey-timeline-card'),
                                      state: state,
                                      onSelectSample: (s) {
                                        _cubit.seekToTime(s.measuredAt);
                                        _cubit.selectPoint(s);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            // Bố cục xếp dọc trên điện thoại và máy tính bảng.
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _JourneyMapCard(
                                  state: state,
                                  height: width < 600 ? 280 : 330,
                                  onPointSelected: (pt) =>
                                      _cubit.selectPoint(pt),
                                ),
                                const SizedBox(height: 10),
                                _JourneyPlaybackCard(
                                  state: state,
                                  onPlay: () => _cubit.play(),
                                  onPause: () => _cubit.pause(),
                                  onResume: () => _cubit.resume(),
                                  onReset: () => _cubit.reset(),
                                  onStepBackward30s: _stepBackward30s,
                                  onStepBackward60s: _stepBackward60s,
                                  onStepForward30s: _stepForward30s,
                                  onStepForward60s: _stepForward60s,
                                  onSeekProgress: (p) =>
                                      _cubit.seekToProgress(p),
                                  onSpeedChanged: (s) =>
                                      _cubit.setPlaybackSpeed(s),
                                  onFollowChanged: (f) =>
                                      _cubit.toggleFollowCamera(f),
                                ),
                                const SizedBox(height: 10),
                                _JourneyCurrentInfoCard(state: state),
                                const SizedBox(height: 12),
                                _JourneyTimelineCard(
                                  state: state,
                                  height: 420,
                                  onSelectSample: (s) {
                                    _cubit.seekToTime(s.measuredAt);
                                    _cubit.selectPoint(s);
                                  },
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _onPresetSelected(int index) {
    // Preset chỉ đổi khoảng thời gian rồi tải lại, không lọc cục bộ mẫu cũ.
    final now = DateTime.now();
    setState(() {
      _rangePresetIndex = index;
      if (index == 0) {
        // Hôm nay
        _fromTime = DateTime(now.year, now.month, now.day, 0, 0, 0);
        _toTime = now;
      } else if (index == 1) {
        // Hôm qua
        final yesterday = now.subtract(const Duration(days: 1));
        _fromTime = DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
          0,
          0,
          0,
        );
        _toTime = DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
          23,
          59,
          59,
        );
      } else if (index == 2) {
        // 24h qua
        _fromTime = now.subtract(const Duration(hours: 24));
        _toTime = now;
      } else if (index == 3) {
        // 7 ngày qua
        _fromTime = now.subtract(const Duration(days: 7));
        _toTime = now;
      }
    });
    _fetchHistory();
  }

  void _stepBackward30s() {
    _cubit.stepBackward(const Duration(seconds: 30));
  }

  void _stepBackward60s() {
    _cubit.stepBackward(const Duration(seconds: 60));
  }

  void _stepForward30s() {
    _cubit.stepForward(const Duration(seconds: 30));
  }

  void _stepForward60s() {
    _cubit.stepForward(const Duration(seconds: 60));
  }

  Future<void> _openCustomDateTimeRangePicker(BuildContext context) async {
    // Dialog trả mốc bắt đầu/kết thúc rõ ràng; chỉ tải khi người dùng xác nhận.
    final result = await showCustomDateTimeRangeDialog(
      context,
      initialFrom: _fromTime,
      initialTo: _toTime,
    );

    if (result != null) {
      setState(() {
        _rangePresetIndex = 4;
        _fromTime = result.start;
        _toTime = result.end;
      });
      _fetchHistory();
    }
  }
}

// Tầng 1: bảng lọc thời gian.

// Panel chọn khoảng thời gian, gap tách đoạn và thao tác tải lại hành trình.
class _JourneyFilterPanel extends StatelessWidget {
  const _JourneyFilterPanel({
    required this.fromTime,
    required this.toTime,
    required this.presetIndex,
    required this.gapThreshold,
    required this.isLoading,
    required this.onPresetSelected,
    required this.onCustomRangePressed,
    required this.onGapChanged,
    required this.onRefresh,
  });

  final DateTime fromTime;
  final DateTime toTime;
  final int presetIndex;
  final Duration gapThreshold;
  final bool isLoading;
  final ValueChanged<int> onPresetSelected;
  final VoidCallback onCustomRangePressed;
  final ValueChanged<Duration> onGapChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final dtFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.borderSoft),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 960;

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Nhóm A: Khoảng thời gian
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Khoảng thời gian',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.appColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    InkWell(
                      onTap: onCustomRangePressed,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: context.appColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: context.appColors.borderSoft,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Từ ',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: context.appColors.textSecondary,
                              ),
                            ),
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 13,
                              color: context.appColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dtFormat.format(fromTime),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: context.appColors.textPrimary,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 12,
                                color: context.appColors.textSecondary,
                              ),
                            ),
                            Text(
                              'Đến ',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: context.appColors.textSecondary,
                              ),
                            ),
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 13,
                              color: context.appColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dtFormat.format(toTime),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: context.appColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                SizedBox(
                  height: 38,
                  child: VerticalDivider(
                    width: 1,
                    color: context.appColors.borderSoft,
                  ),
                ),
                const SizedBox(width: 16),

                // Nhóm B: Khoảng nhanh
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Khoảng nhanh',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildQuickChip(context, 'Hôm nay', 0),
                            const SizedBox(width: 6),
                            _buildQuickChip(context, 'Hôm qua', 1),
                            const SizedBox(width: 6),
                            _buildQuickChip(context, '24h qua', 2),
                            const SizedBox(width: 6),
                            _buildQuickChip(context, '7 ngày', 3),
                            const SizedBox(width: 6),
                            _buildQuickChip(
                              context,
                              'Tùy chọn',
                              4,
                              onTap: onCustomRangePressed,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  height: 38,
                  child: VerticalDivider(
                    width: 1,
                    color: context.appColors.borderSoft,
                  ),
                ),
                const SizedBox(width: 16),

                // Nhóm C: Ngắt quãng + Tải lại
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ngắt quãng',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.appColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildGapDropdown(context),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: context.appColors.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: isLoading ? null : onRefresh,
                          icon: isLoading
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppPalette.onAccent,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 15),
                          label: const Text(
                            'Tải lại',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            );
          }

          // Bố cục nhỏ gọn khi màn hình hẹp.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mốc thời gian
              InkWell(
                onTap: onCustomRangePressed,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: context.appColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.appColors.borderSoft),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 14,
                        color: context.appColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${dtFormat.format(fromTime)}  →  ${dtFormat.format(toTime)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: context.appColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Các lựa chọn nhanh dạng chip.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickChip(context, 'Hôm nay', 0),
                    const SizedBox(width: 6),
                    _buildQuickChip(context, 'Hôm qua', 1),
                    const SizedBox(width: 6),
                    _buildQuickChip(context, '24h qua', 2),
                    const SizedBox(width: 6),
                    _buildQuickChip(context, '7 ngày', 3),
                    const SizedBox(width: 6),
                    _buildQuickChip(
                      context,
                      'Tùy chọn',
                      4,
                      onTap: onCustomRangePressed,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Ngắt quãng + Tải lại
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Ngắt quãng: ',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                      _buildGapDropdown(context),
                    ],
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: context.appColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: isLoading ? null : onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text(
                      'Tải lại',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGapDropdown(BuildContext context) {
    const standardMinutes = [1, 5, 15, 30, 60];
    final currentMinutes = gapThreshold.inMinutes;
    final isCustom = !standardMinutes.contains(currentMinutes);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: context.appColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.appColors.borderSoft),
      ),
      child: DropdownButton<int>(
        value: currentMinutes,
        isDense: true,
        borderRadius: AppMenuStyle.borderRadius,
        dropdownColor: AppMenuStyle.surfaceColor(context),
        menuMaxHeight: AppMenuStyle.dropdownMaxHeight(context),
        underline: const SizedBox.shrink(),
        icon: Icon(
          Icons.arrow_drop_down_rounded,
          size: 18,
          color: context.appColors.textPrimary,
        ),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: context.appColors.textPrimary,
        ),
        items: [
          const DropdownMenuItem(value: 1, child: Text('1 phút')),
          const DropdownMenuItem(value: 5, child: Text('5 phút')),
          const DropdownMenuItem(value: 15, child: Text('15 phút')),
          const DropdownMenuItem(value: 30, child: Text('30 phút')),
          const DropdownMenuItem(value: 60, child: Text('1 giờ')),
          if (isCustom)
            DropdownMenuItem(
              value: currentMinutes,
              child: Text('${formatGapDuration(gapThreshold)} (Tùy chỉnh)'),
            ),
          DropdownMenuItem(
            value: -1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 14,
                  color: context.appColors.primary,
                ),
                SizedBox(width: 4),
                Text('Tùy chỉnh'),
              ],
            ),
          ),
        ],
        onChanged: (v) async {
          if (v == null) return;
          if (v == -1) {
            final customGap = await showCustomGapThresholdDialog(
              context,
              initialDuration: gapThreshold,
            );
            if (customGap != null) {
              onGapChanged(customGap);
            }
          } else {
            onGapChanged(Duration(minutes: v));
          }
        },
      ),
    );
  }

  Widget _buildQuickChip(
    BuildContext context,
    String label,
    int index, {
    VoidCallback? onTap,
  }) {
    final isSelected = presetIndex == index;

    return InkWell(
      onTap: onTap ?? () => onPresetSelected(index),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? context.appColors.primarySoft
              : context.appColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? context.appColors.primary
                : context.appColors.borderSoft,
            width: isSelected ? 1.2 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? context.appColors.primary
                : context.appColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─── TẦNG 2: Hàng Thẻ KPI Chỉ Số Hành Trình ──────────────────────────────────

// Dải số liệu hành trình đọc trực tiếp tổng hợp trong JourneyHistoryState.
class _JourneyMetricsRow extends StatelessWidget {
  const _JourneyMetricsRow({required this.state});

  final JourneyHistoryState state;

  @override
  Widget build(BuildContext context) {
    final parkCount = HistoryMapLayers.extractStopAndParkPoints(
      state.validSamples,
    ).where((stop) => stop.isPark).length;

    final metrics = [
      _MetricItemData(
        icon: Icons.route_rounded,
        label: 'Tổng quãng đường',
        value: DeviceFormatters.distance(state.totalDistanceM),
        tintColor: context.appColors.primarySoft,
        iconColor: context.appColors.primary,
      ),
      _MetricItemData(
        icon: Icons.navigation_rounded,
        label: 'Thời gian di chuyển',
        value: DeviceFormatters.secondsDuration(state.movingDurationS),
        tintColor: context.appColors.successSoft,
        iconColor: context.appColors.success,
      ),
      _MetricItemData(
        icon: Icons.pause_circle_rounded,
        label: 'Thời gian dừng',
        value: DeviceFormatters.secondsDuration(state.stoppedDurationS),
        tintColor: context.appColors.warningSoft,
        iconColor: context.appColors.warning,
      ),
      _MetricItemData(
        icon: Icons.speed_rounded,
        label: 'Tốc độ tối đa',
        value: DeviceFormatters.speedMps(state.maxSpeedMps),
        tintColor: context.appColors.dangerSoft,
        iconColor: context.appColors.dangerStrong,
      ),
      _MetricItemData(
        icon: Icons.trending_up_rounded,
        label: 'Tốc độ trung bình',
        value: DeviceFormatters.speedMps(state.avgSpeedMps),
        tintColor: context.appColors.indigoSoft,
        iconColor: context.appColors.indigo,
      ),
      _MetricItemData(
        icon: Icons.local_parking_rounded,
        label: 'Số lần đỗ xe',
        value: '$parkCount lần',
        tintColor: context.appColors.orangeSoft,
        iconColor: context.appColors.orange,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final count = width >= 1100
            ? 6
            : width >= 720
            ? 3
            : 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            mainAxisExtent: 72,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: metrics.length,
          itemBuilder: (context, index) {
            final item = metrics[index];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.appColors.borderSoft),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: item.tintColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(item.icon, size: 18, color: item.iconColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: context.appColors.textSecondary,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: context.appColors.textPrimary,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// Model trình bày của một ô số liệu hành trình.
class _MetricItemData {
  final IconData icon;
  final String label;
  final String value;
  final Color tintColor;
  final Color iconColor;

  const _MetricItemData({
    required this.icon,
    required this.label,
    required this.value,
    required this.tintColor,
    required this.iconColor,
  });
}

// Tầng 3.1: thẻ bản đồ.

// Card bản đồ hành trình truyền samples, segments và điểm playback tới lớp bản đồ.
class _JourneyMapCard extends StatelessWidget {
  const _JourneyMapCard({
    required this.state,
    required this.onPointSelected,
    this.height,
  });

  final JourneyHistoryState state;
  final double? height;
  final ValueChanged<LocationModel?> onPointSelected;

  @override
  Widget build(BuildContext context) {
    final selectedPoint = state.selectedPoint;
    final selectedStop = selectedPoint == null
        ? null
        : HistoryMapLayers.findStopPoint(state.validSamples, selectedPoint);

    return Container(
      key: const Key('journey-map-card-surface'),
      height: height,
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Bản đồ chính
          _DeviceJourneyMapView(state: state, onPointSelected: onPointSelected),

          // Thẻ chi tiết điểm GPS khi bấm chọn.
          if (selectedPoint != null)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Align(
                alignment: Alignment.topRight,
                child: PointInfoPopup(
                  point: selectedPoint,
                  stopPoint: selectedStop,
                  resolveAddress: context
                      .read<GeocodingRepository>()
                      .reverseAddress,
                  onClose: () => onPointSelected(null),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Tầng 3.2: thẻ điều khiển phát lại.

// Bộ điều khiển phát lại hiển thị tiến độ, tốc độ phát, play/pause và bước thời gian;
// mọi callback thay đổi máy trạng thái JourneyHistoryCubit.
class _JourneyPlaybackCard extends StatelessWidget {
  const _JourneyPlaybackCard({
    required this.state,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onReset,
    required this.onStepBackward30s,
    required this.onStepBackward60s,
    required this.onStepForward30s,
    required this.onStepForward60s,
    required this.onSeekProgress,
    required this.onSpeedChanged,
    required this.onFollowChanged,
  });

  final JourneyHistoryState state;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onReset;
  final VoidCallback onStepBackward30s;
  final VoidCallback onStepBackward60s;
  final VoidCallback onStepForward30s;
  final VoidCallback onStepForward60s;
  final ValueChanged<double> onSeekProgress;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<bool> onFollowChanged;

  @override
  Widget build(BuildContext context) {
    final hasSamples = state.validSamples.length >= 2;
    final timeFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
    final shortTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

    final currentTimeStr = state.currentReplayTime != null
        ? timeFormat.format(state.currentReplayTime!.toLocal())
        : (state.validSamples.isNotEmpty
              ? timeFormat.format(state.validSamples.first.measuredAt.toLocal())
              : '--/--/---- --:--:--');

    final startTimeStr = hasSamples
        ? shortTimeFormat.format(state.validSamples.first.measuredAt.toLocal())
        : '--/--/---- --:--';
    final endTimeStr = hasSamples
        ? shortTimeFormat.format(state.validSamples.last.measuredAt.toLocal())
        : '--/--/---- --:--';

    final speedStr = DeviceFormatters.speedMps(state.currentSpeedMps ?? 0);

    final statusLabel = state.isCompleted
        ? 'Kết thúc'
        : (state.isPlaying
              ? 'Đang di chuyển ($speedStr)'
              : (state.isPaused ? 'Tạm dừng ($speedStr)' : 'Sẵn sàng'));

    final statusColor = state.isCompleted
        ? context.appColors.dangerStrong
        : (state.isPlaying
              ? context.appColors.success
              : context.appColors.textSecondary);

    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 680;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 16,
        vertical: isCompact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.borderSoft),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isCompact) ...[
            // Desktop: một hàng gồm vùng trái, giữa và phải.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // LEFT: Thời gian & Trạng thái
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentTimeStr,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.appColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle_rounded,
                            size: 7,
                            color: statusColor,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Ở giữa: nút phát, tạm dừng và tua theo bước 60/30 giây.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.fast_rewind_rounded, size: 22),
                      tooltip: 'Lùi 60 giây (1 phút)',
                      visualDensity: VisualDensity.compact,
                      onPressed: hasSamples ? onStepBackward60s : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.replay_30_rounded, size: 22),
                      tooltip: 'Lùi 30 giây',
                      visualDensity: VisualDensity.compact,
                      onPressed: hasSamples ? onStepBackward30s : null,
                    ),
                    const SizedBox(width: 2),
                    // Nút phát hình tròn là thao tác chính.
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: hasSamples
                            ? context.appColors.primary
                            : context.appColors.textDisabled,
                        shape: BoxShape.circle,
                        boxShadow: hasSamples
                            ? [
                                BoxShadow(
                                  color: context.appColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: IconButton(
                        icon: Icon(
                          state.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 24,
                          color: AppPalette.onAccent,
                        ),
                        onPressed: !hasSamples
                            ? null
                            : state.isPlaying
                            ? onPause
                            : (state.isPaused ? onResume : onPlay),
                      ),
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      icon: const Icon(Icons.forward_30_rounded, size: 22),
                      tooltip: 'Tiến 30 giây',
                      visualDensity: VisualDensity.compact,
                      onPressed: hasSamples ? onStepForward30s : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.fast_forward_rounded, size: 22),
                      tooltip: 'Tiến 60 giây (1 phút)',
                      visualDensity: VisualDensity.compact,
                      onPressed: hasSamples ? onStepForward60s : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.replay_rounded, size: 20),
                      tooltip: 'Bắt đầu lại',
                      visualDensity: VisualDensity.compact,
                      onPressed: hasSamples ? onReset : null,
                    ),
                  ],
                ),

                // Bên phải: tốc độ phát và công tắc theo dõi xe.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Danh sách chọn tốc độ phát.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.appColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: context.appColors.borderSoft),
                      ),
                      child: DropdownButton<double>(
                        value: state.playbackSpeed,
                        borderRadius: AppMenuStyle.borderRadius,
                        dropdownColor: AppMenuStyle.surfaceColor(context),
                        menuMaxHeight: AppMenuStyle.dropdownMaxHeight(context),
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: context.appColors.textPrimary,
                        ),
                        items: const [
                          DropdownMenuItem(value: 0.5, child: Text('0.5x')),
                          DropdownMenuItem(value: 1.0, child: Text('1x')),
                          DropdownMenuItem(value: 2.0, child: Text('2x')),
                          DropdownMenuItem(value: 4.0, child: Text('4x')),
                          DropdownMenuItem(value: 8.0, child: Text('8x')),
                          DropdownMenuItem(value: 16.0, child: Text('16x')),
                        ],
                        onChanged: (v) {
                          if (v != null) onSpeedChanged(v);
                        },
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Công tắc camera tự bám theo thiết bị.
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => onFollowChanged(!state.followCamera),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: state.followCamera
                              ? context.appColors.primarySoft
                              : context.appColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: state.followCamera
                                ? context.appColors.primary
                                : context.appColors.borderSoft,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.my_location_rounded,
                              size: 14,
                              color: state.followCamera
                                  ? context.appColors.primary
                                  : context.appColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Theo dõi xe',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: state.followCamera
                                    ? context.appColors.primary
                                    : context.appColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ] else ...[
            // ── MOBILE LAYOUT: Split into clean, uncrowded rows ──
            // Hàng 1 trên di động: thời gian/trạng thái và tốc độ/theo dõi.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentTimeStr,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: context.appColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle_rounded,
                            size: 6.5,
                            color: statusColor,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: context.appColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: context.appColors.borderSoft),
                      ),
                      child: DropdownButton<double>(
                        value: state.playbackSpeed,
                        borderRadius: AppMenuStyle.borderRadius,
                        dropdownColor: AppMenuStyle.surfaceColor(context),
                        menuMaxHeight: AppMenuStyle.dropdownMaxHeight(context),
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.appColors.textPrimary,
                        ),
                        items: const [
                          DropdownMenuItem(value: 0.5, child: Text('0.5x')),
                          DropdownMenuItem(value: 1.0, child: Text('1x')),
                          DropdownMenuItem(value: 2.0, child: Text('2x')),
                          DropdownMenuItem(value: 4.0, child: Text('4x')),
                          DropdownMenuItem(value: 8.0, child: Text('8x')),
                          DropdownMenuItem(value: 16.0, child: Text('16x')),
                        ],
                        onChanged: (v) {
                          if (v != null) onSpeedChanged(v);
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => onFollowChanged(!state.followCamera),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: state.followCamera
                              ? context.appColors.primarySoft
                              : context.appColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: state.followCamera
                                ? context.appColors.primary
                                : context.appColors.borderSoft,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.my_location_rounded,
                              size: 13,
                              color: state.followCamera
                                  ? context.appColors.primary
                                  : context.appColors.textSecondary,
                            ),
                            if (width >= 360) ...[
                              const SizedBox(width: 3),
                              Text(
                                'Theo dõi',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: state.followCamera
                                      ? context.appColors.primary
                                      : context.appColors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Hàng 2 trên di động: cụm nút phát, tua và chuyển bước căn giữa.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_rounded, size: 19),
                  tooltip: 'Bắt đầu lại',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: hasSamples ? onReset : null,
                ),
                const SizedBox(width: 2),
                IconButton(
                  icon: const Icon(Icons.fast_rewind_rounded, size: 20),
                  tooltip: 'Lùi 60 giây (1 phút)',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: hasSamples ? onStepBackward60s : null,
                ),
                IconButton(
                  icon: const Icon(Icons.replay_30_rounded, size: 20),
                  tooltip: 'Lùi 30 giây',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: hasSamples ? onStepBackward30s : null,
                ),
                const SizedBox(width: 4),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: hasSamples
                        ? context.appColors.primary
                        : context.appColors.textDisabled,
                    shape: BoxShape.circle,
                    boxShadow: hasSamples
                        ? [
                            BoxShadow(
                              color: context.appColors.primary.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      state.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 22,
                      color: AppPalette.onAccent,
                    ),
                    onPressed: !hasSamples
                        ? null
                        : state.isPlaying
                        ? onPause
                        : (state.isPaused ? onResume : onPlay),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.forward_30_rounded, size: 20),
                  tooltip: 'Tiến 30 giây',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: hasSamples ? onStepForward30s : null,
                ),
                IconButton(
                  icon: const Icon(Icons.fast_forward_rounded, size: 20),
                  tooltip: 'Tiến 60 giây (1 phút)',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: hasSamples ? onStepForward60s : null,
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),

          // ── HÀNG CUỐI: thanh trượt dòng thời gian ─────────────
          Row(
            children: [
              Text(
                startTimeStr,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: context.appColors.textSecondary,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.5,
                    activeTrackColor: context.appColors.primary,
                    inactiveTrackColor: context.appColors.border,
                    thumbColor: context.appColors.primary,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6.5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                  ),
                  child: Slider(
                    value: state.playbackProgress,
                    onChanged: hasSamples ? onSeekProgress : null,
                  ),
                ),
              ),
              Text(
                endTimeStr,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: context.appColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Tầng 3.3: bảng dữ liệu tại mốc hiện tại.

// Card thông tin tại con trỏ playback: thời gian, tốc độ, hướng, tọa độ và quãng đường.
class _JourneyCurrentInfoCard extends StatelessWidget {
  const _JourneyCurrentInfoCard({required this.state});

  final JourneyHistoryState state;

  @override
  Widget build(BuildContext context) {
    final sample =
        state.currentSampleIndex >= 0 &&
            state.currentSampleIndex < state.validSamples.length
        ? state.validSamples[state.currentSampleIndex]
        : (state.validSamples.isNotEmpty ? state.validSamples.first : null);
    final position =
        state.currentPosition ??
        (sample != null ? LatLng(sample.latitude, sample.longitude) : null);
    final gpsPositionText = position != null
        ? DeviceFormatters.coordinates(position.latitude, position.longitude)
        : '--';
    final gpsDetails = <String>[
      if (sample?.accuracyM != null)
        'Sai số ±${sample!.accuracyM!.toStringAsFixed(0)} m',
      if (sample?.altitudeM != null)
        'Độ cao ${sample!.altitudeM!.toStringAsFixed(1)} m',
    ];
    final gpsDetailsText = gpsDetails.isEmpty
        ? 'Hệ tọa độ WGS84'
        : gpsDetails.join(' · ');
    final speedStr = DeviceFormatters.speedMps(state.currentSpeedMps);
    final currDistStr = DeviceFormatters.distance(state.currentDistanceM);
    final totalDistStr = DeviceFormatters.distance(state.totalDistanceM);
    final distanceProgressStr = '$currDistStr / $totalDistStr';
    final hasSpeed = state.currentSpeedMps != null;
    final isMoving =
        hasSpeed &&
        state.currentSpeedMps! > DeviceStatusResolver.movingThresholdMps;
    final movementLabel = !hasSpeed
        ? 'Không rõ'
        : isMoving
        ? 'Đang di chuyển'
        : 'Đang dừng';
    final movementColor = !hasSpeed
        ? context.appColors.textSecondary
        : isMoving
        ? context.appColors.success
        : context.appColors.warning;

    final timeStr = state.currentReplayTime != null
        ? DateFormat(
            'dd/MM/yyyy HH:mm:ss',
          ).format(state.currentReplayTime!.toLocal())
        : '--';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.borderSoft),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 780;

          if (isWide) {
            return Row(
              children: [
                // 1. Vị trí GPS
                Expanded(
                  flex: 34,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Vị trí GPS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        gpsPositionText,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: context.appColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        gpsDetailsText,
                        style: TextStyle(
                          fontSize: 10,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 34,
                  child: VerticalDivider(
                    width: 20,
                    color: context.appColors.borderSoft,
                  ),
                ),

                // 2. Tốc độ
                Expanded(
                  flex: 15,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Tốc độ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        speedStr,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: context.appColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 34,
                  child: VerticalDivider(
                    width: 20,
                    color: context.appColors.borderSoft,
                  ),
                ),

                // 3. Quãng đường đã đi / Tổng
                Expanded(
                  flex: 19,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Đã đi',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        distanceProgressStr,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.appColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 34,
                  child: VerticalDivider(
                    width: 20,
                    color: context.appColors.borderSoft,
                  ),
                ),

                // 4. Trạng thái
                Expanded(
                  flex: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Trạng thái',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle_rounded,
                            size: 7,
                            color: movementColor,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              movementLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: movementColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 34,
                  child: VerticalDivider(
                    width: 20,
                    color: context.appColors.borderSoft,
                  ),
                ),

                // 5. Thời điểm
                Expanded(
                  flex: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Thời điểm',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.appColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          // Wrap cho màn hình hẹp
          return Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vị trí GPS',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.appColors.textSecondary,
                    ),
                  ),
                  Text(
                    gpsPositionText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    gpsDetailsText,
                    style: TextStyle(
                      fontSize: 10,
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tốc độ',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.appColors.textSecondary,
                    ),
                  ),
                  Text(
                    speedStr,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đã đi',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.appColors.textSecondary,
                    ),
                  ),
                  Text(
                    distanceProgressStr,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trạng thái',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.appColors.textSecondary,
                    ),
                  ),
                  Text(
                    movementLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: movementColor,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thời điểm',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.appColors.textSecondary,
                    ),
                  ),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── TẦNG 3.4: thẻ dòng thời gian bên phải ──────────────────────────────────

// Timeline sự kiện suy ra từ các đoạn/mẫu hành trình và giải địa chỉ theo từng nút.
class _JourneyTimelineCard extends StatelessWidget {
  const _JourneyTimelineCard({
    super.key,
    required this.state,
    required this.onSelectSample,
    this.height,
  });

  final JourneyHistoryState state;
  final double? height;
  final ValueChanged<LocationModel> onSelectSample;

  @override
  Widget build(BuildContext context) {
    final timelineEvents = _buildJourneyTimelineEvents(state);
    final parkCount = timelineEvents
        .where((event) => event.type == _JourneyTimelineEventType.parked)
        .length;
    final gapCount = timelineEvents
        .where((event) => event.type == _JourneyTimelineEventType.dataRestored)
        .length;
    final locationSummary = gapCount == 0
        ? 'Vị trí được ghi nhận liên tục'
        : '$gapCount đoạn không ghi nhận được vị trí';
    final journeySummary = parkCount == 0
        ? locationSummary
        : '$parkCount điểm đỗ · $locationSummary';
    final timeFormat = DateFormat('dd/MM/yyyy · HH:mm:ss');

    return Container(
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Phần đầu dòng thời gian.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Lộ trình di chuyển',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.appColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.appColors.primarySoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${timelineEvents.length} mốc',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: context.appColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            journeySummary,
            style: TextStyle(
              fontSize: 11,
              color: context.appColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: context.appColors.borderSoft),
          const SizedBox(height: 8),

          // Danh sách dòng thời gian cuộn độc lập.
          Expanded(
            child: timelineEvents.isEmpty
                ? Center(
                    child: Text(
                      'Chưa có dữ liệu lịch trình',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: timelineEvents.length,
                    itemBuilder: (context, index) {
                      final event = timelineEvents[index];
                      final s = event.sample;
                      final isFirstEvent = index == 0;
                      final isFinalEvent = index == timelineEvents.length - 1;

                      // Màu nút mốc theo loại sự kiện.
                      final dotColor = event.color(context.appColors);
                      final titleLabel = event.title;

                      return InkWell(
                        onTap: () => onSelectSample(s),
                        borderRadius: BorderRadius.circular(6),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Đường timeline chạy xuyên chính giữa node.
                              SizedBox(
                                width: 20,
                                child: CustomPaint(
                                  painter: _JourneyTimelineRailPainter(
                                    nodeColor: dotColor,
                                    lineColor: context.appColors.border,
                                    haloColor: context.appColors.surface,
                                    drawTop: !isFirstEvent,
                                    drawBottom: !isFinalEvent,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),

                              // Nội dung của mốc.
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        timeFormat.format(
                                          s.measuredAt.toLocal(),
                                        ),
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: context.appColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            titleLabel,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              color: dotColor,
                                            ),
                                          ),
                                          Text(
                                            ' · ${event.detail}',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              color: context
                                                  .appColors
                                                  .textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      _JourneyEventAddress(sample: s),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Painter vẽ đường trục dọc nối các nút timeline; nội dung sự kiện vẫn là widget thường.
class _JourneyTimelineRailPainter extends CustomPainter {
  const _JourneyTimelineRailPainter({
    required this.nodeColor,
    required this.lineColor,
    required this.haloColor,
    required this.drawTop,
    required this.drawBottom,
  });

  final Color nodeColor;
  final Color lineColor;
  final Color haloColor;
  final bool drawTop;
  final bool drawBottom;

  @override
  void paint(Canvas canvas, Size size) {
    const nodeY = 12.0;
    final centerX = size.width / 2;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5;

    if (drawTop) {
      canvas.drawLine(Offset(centerX, 0), Offset(centerX, nodeY), linePaint);
    }
    if (drawBottom) {
      canvas.drawLine(
        Offset(centerX, nodeY),
        Offset(centerX, size.height),
        linePaint,
      );
    }

    canvas.drawCircle(Offset(centerX, nodeY), 5, Paint()..color = haloColor);
    canvas.drawCircle(Offset(centerX, nodeY), 3.5, Paint()..color = nodeColor);
  }

  @override
  bool shouldRepaint(covariant _JourneyTimelineRailPainter oldDelegate) {
    return oldDelegate.nodeColor != nodeColor ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.haloColor != haloColor ||
        oldDelegate.drawTop != drawTop ||
        oldDelegate.drawBottom != drawBottom;
  }
}

// Các loại mốc trình bày trong timeline, không phải DeviceEvent lưu ở backend.
enum _JourneyTimelineEventType { start, moving, parked, dataRestored, end }

// Model trình bày của một mốc timeline được tạo từ LocationModel/RouteSegment.
class _JourneyTimelineEvent {
  const _JourneyTimelineEvent({
    required this.sample,
    required this.type,
    required this.detail,
  });

  final LocationModel sample;
  final _JourneyTimelineEventType type;
  final String detail;

  String get title => switch (type) {
    _JourneyTimelineEventType.start => 'Bắt đầu hành trình',
    _JourneyTimelineEventType.moving => 'Mốc địa điểm',
    _JourneyTimelineEventType.parked => 'Đỗ xe',
    _JourneyTimelineEventType.dataRestored => 'Có lại dữ liệu vị trí',
    _JourneyTimelineEventType.end => 'Kết thúc hành trình',
  };

  Color color(AppThemeColors colors) => switch (type) {
    _JourneyTimelineEventType.start => colors.success,
    _JourneyTimelineEventType.moving => colors.primary,
    _JourneyTimelineEventType.parked => colors.orange,
    _JourneyTimelineEventType.dataRestored => colors.textSecondary,
    _JourneyTimelineEventType.end => colors.dangerStrong,
  };
}

List<_JourneyTimelineEvent> _buildJourneyTimelineEvents(
  JourneyHistoryState state,
) {
  // Tạo mốc bắt đầu/kết thúc, di chuyển/dừng và khôi phục dữ liệu từ samples đã
  // làm sạch; không ghi ngược các mốc suy ra này về backend.
  final samples = state.validSamples;
  if (samples.isEmpty) return const [];

  String sampleKey(LocationModel sample) {
    return '${sample.id}:${sample.measuredAt.microsecondsSinceEpoch}:'
        '${sample.latitude}:${sample.longitude}';
  }

  final eventsBySample = <String, _JourneyTimelineEvent>{};
  final first = samples.first;
  final last = samples.last;

  // Dùng đúng tập node đang hiển thị trên bản đồ để timeline và bản đồ luôn
  // khớp nhau, kể cả khi thiết bị không gửi trường tốc độ.
  for (final node in HistoryMapLayers.extractRouteNodes(samples)) {
    if (node.type != JourneyRouteNodeType.place) continue;
    final sample = node.sample;
    eventsBySample.putIfAbsent(
      sampleKey(sample),
      () => _JourneyTimelineEvent(
        sample: sample,
        type: _JourneyTimelineEventType.moving,
        detail: sample.speedMps != null
            ? DeviceFormatters.speedMps(sample.speedMps)
            : 'Mốc trên lộ trình',
      ),
    );
  }

  // Một phân đoạn mới bắt đầu nghĩa là trước đó có khoảng mất dữ liệu.
  for (var i = 1; i < state.segments.length; i++) {
    final previous = state.segments[i - 1];
    final current = state.segments[i];
    if (previous.samples.isEmpty || current.samples.isEmpty) continue;
    final restoredAt = current.samples.first;
    final gap = restoredAt.measuredAt.difference(
      previous.samples.last.measuredAt,
    );
    eventsBySample[sampleKey(restoredAt)] = _JourneyTimelineEvent(
      sample: restoredAt,
      type: _JourneyTimelineEventType.dataRestored,
      detail: 'Gián đoạn ${DeviceFormatters.secondsDuration(gap.inSeconds)}',
    );
  }

  // Điểm đỗ có ý nghĩa hơn mốc di chuyển nếu cùng rơi vào một mẫu GPS.
  for (final stop in HistoryMapLayers.extractStopAndParkPoints(samples)) {
    if (!stop.isPark) continue;
    eventsBySample[sampleKey(stop.sample)] = _JourneyTimelineEvent(
      sample: stop.sample,
      type: _JourneyTimelineEventType.parked,
      detail: stop.durationLabel,
    );
  }

  eventsBySample[sampleKey(first)] = _JourneyTimelineEvent(
    sample: first,
    type: _JourneyTimelineEventType.start,
    detail: 'Điểm xuất phát',
  );
  if (samples.length > 1) {
    eventsBySample[sampleKey(last)] = _JourneyTimelineEvent(
      sample: last,
      type: _JourneyTimelineEventType.end,
      detail: 'Điểm đến cuối cùng',
    );
  }

  final events = eventsBySample.values.toList()
    ..sort((a, b) => a.sample.measuredAt.compareTo(b.sample.measuredAt));
  return events;
}

// Thành phần giải địa chỉ bất đồng bộ cho một mốc timeline bằng GeocodingRepository.
class _JourneyEventAddress extends StatefulWidget {
  const _JourneyEventAddress({required this.sample});

  final LocationModel sample;

  @override
  State<_JourneyEventAddress> createState() => _JourneyEventAddressState();
}

class _JourneyEventAddressState extends State<_JourneyEventAddress> {
  // Future được tạo lại khi tọa độ đổi để không hiển thị địa chỉ của mốc cũ.
  late Future<String?> _addressFuture;

  @override
  void initState() {
    super.initState();
    _resolveAddress();
  }

  @override
  void didUpdateWidget(covariant _JourneyEventAddress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sample.latitude != widget.sample.latitude ||
        oldWidget.sample.longitude != widget.sample.longitude) {
      _resolveAddress();
    }
  }

  void _resolveAddress() {
    // Repository có cache/gộp request; widget chỉ giữ Future để FutureBuilder hiển thị.
    _addressFuture = context.read<GeocodingRepository>().reverseAddress(
      widget.sample.latitude,
      widget.sample.longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _addressFuture,
      builder: (context, snapshot) {
        final address = snapshot.data?.trim();
        final text = snapshot.connectionState == ConnectionState.waiting
            ? 'Đang xác định địa điểm...'
            : address != null && address.isNotEmpty
            ? address
            : DeviceFormatters.coordinates(
                widget.sample.latitude,
                widget.sample.longitude,
              );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 12,
              color: context.appColors.textSecondary,
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 9.5,
                  color: context.appColors.textSecondary,
                  height: 1.25,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// Bản đồ hành trình đầy đủ: route đã chia đoạn, marker đầu/cuối, điểm playback
// và nhãn địa chỉ được giải bất đồng bộ.
class _DeviceJourneyMapView extends StatefulWidget {
  final JourneyHistoryState state;
  final ValueChanged<LocationModel?> onPointSelected;

  const _DeviceJourneyMapView({
    required this.state,
    required this.onPointSelected,
  });

  @override
  State<_DeviceJourneyMapView> createState() => _DeviceJourneyMapViewState();
}

class _DeviceJourneyMapViewState extends State<_DeviceJourneyMapView> {
  // Version request ngăn response geocoding cũ ghi đè labels của hành trình mới;
  // camera/zoom/show labels chỉ là state hiển thị cục bộ.
  final MapController _mapController = MapController();
  final Map<String, String> _nodeAddresses = {};
  bool _mapReady = false;
  bool _didRequestInitialAddresses = false;
  int _addressRequestVersion = 0;
  double _currentZoom = 14.0;
  bool _showRouteLabels = true;
  static const LatLng _defaultCenter = LatLng(21.0285, 105.8542);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didRequestInitialAddresses) {
      _didRequestInitialAddresses = true;
      _loadNodeAddresses(widget.state.validSamples);
    }
  }

  @override
  void didUpdateWidget(covariant _DeviceJourneyMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldSamples = oldWidget.state.validSamples;
    final newSamples = widget.state.validSamples;

    if (oldSamples != newSamples && newSamples.isNotEmpty) {
      _loadNodeAddresses(newSamples);
      if (_mapReady) {
        _fitRouteBounds(newSamples);
      }
    }

    if (_mapReady &&
        widget.state.followCamera &&
        widget.state.currentPosition != null) {
      if (widget.state.isPlaying || widget.state.isCompleted) {
        _mapController.move(widget.state.currentPosition!, _currentZoom);
      }
    }
  }

  Future<void> _loadNodeAddresses(List<LocationModel> samples) async {
    // Chỉ giải địa chỉ các nút cần hiển thị; kết quả được áp dụng khi request version
    // vẫn khớp và widget còn mounted.
    final nodes = HistoryMapLayers.extractRouteNodes(samples);
    if (nodes.isEmpty) return;

    final missing = <JourneyRouteNode>[];
    final queuedKeys = <String>{};
    for (final node in nodes) {
      final key = HistoryMapLayers.routeNodeKey(node.sample);
      if (!_nodeAddresses.containsKey(key) && queuedKeys.add(key)) {
        missing.add(node);
      }
    }
    if (missing.isEmpty) return;

    final requestVersion = ++_addressRequestVersion;
    final repository = context.read<GeocodingRepository>();
    final results = await Future.wait(
      missing.map((node) async {
        final address = await repository.reverseAddress(
          node.sample.latitude,
          node.sample.longitude,
        );
        return MapEntry(HistoryMapLayers.routeNodeKey(node.sample), address);
      }),
    );
    if (!mounted || requestVersion != _addressRequestVersion) return;

    setState(() {
      for (final result in results) {
        final address = result.value?.trim();
        if (address != null && address.isNotEmpty) {
          _nodeAddresses[result.key] = address;
        }
      }
    });
  }

  void _fitRouteBounds(List<LocationModel> samples) {
    // Tính bounds từ mẫu thật rồi điều khiển camera sau khi map sẵn sàng.
    if (samples.isEmpty || !_mapReady) return;

    if (samples.length == 1) {
      _mapController.move(
        LatLng(samples.first.latitude, samples.first.longitude),
        15.0,
      );
      return;
    }

    final points = samples.map((s) => LatLng(s.latitude, s.longitude)).toList();
    final bounds = LatLngBounds.fromPoints(points);

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.only(
          left: 36,
          right: 36,
          top: 36,
          bottom: 36,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // HistoryMapLayers dựng polyline/marker từ state; lớp controls và popup nằm trên
    // Stack nhưng không thay đổi samples nguồn.
    final theme = Theme.of(context);
    final state = widget.state;
    final mapType = context.watch<SettingsCubit>().state.userSettings.mapType;
    final isSatellite = mapType == AppMapType.satellite;

    final initialCenter = state.validSamples.isNotEmpty
        ? LatLng(
            state.validSamples.first.latitude,
            state.validSamples.first.longitude,
          )
        : (state.selectedDevice?.latitude != null &&
                  state.selectedDevice?.longitude != null
              ? LatLng(
                  state.selectedDevice!.latitude!,
                  state.selectedDevice!.longitude!,
                )
              : _defaultCenter);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: _currentZoom,
            minZoom: 4,
            maxZoom: 19,
            onTap: (tapPosition, point) => widget.onPointSelected(null),
            onMapReady: () {
              _mapReady = true;
              if (state.validSamples.isNotEmpty) {
                _fitRouteBounds(state.validSamples);
                _loadNodeAddresses(state.validSamples);
              }
            },
            onPositionChanged: (camera, hasGesture) {
              if (camera.zoom != _currentZoom) {
                setState(() => _currentZoom = camera.zoom);
              }
            },
          ),
          children: [
            // Lớp tile nền bản đồ.
            TileLayer(
              urlTemplate: MapTileProviders.getUrl(
                isSatellite ? AppMapType.satellite : AppMapType.standard,
              ),
              userAgentPackageName: 'com.vmonitor.app',
              minZoom: 4,
              maxZoom: 19,
              maxNativeZoom: MapTileProviders.getMaxZoom(
                isSatellite ? AppMapType.satellite : AppMapType.standard,
              ),
              tileProvider: NetworkTileProvider(silenceExceptions: true),
              errorImage: MemoryImage(TileProvider.transparentImage),
            ),

            // Lớp đường nối thể hiện lộ trình.
            if (state.segments.isNotEmpty)
              PolylineLayer(
                polylines: [
                  ...HistoryMapLayers.buildGapPolylines(
                    segments: state.segments,
                    currentZoom: _currentZoom,
                    gapColor: context.appColors.textSecondary,
                  ),
                  ...HistoryMapLayers.buildPolylines(
                    segments: state.segments,
                    primaryColor: context.appColors.primary,
                    currentZoom: _currentZoom,
                  ),
                ],
              ),

            // Mũi tên chỉ hướng di chuyển
            if (state.segments.isNotEmpty)
              MarkerLayer(
                markers: HistoryMapLayers.buildDirectionArrows(
                  segments: state.segments,
                  currentZoom: _currentZoom,
                  arrowColor: AppPalette.onAccent,
                ),
              ),

            // Node hành trình luôn hiển thị: xuất phát, địa điểm, đỗ xe, kết thúc.
            if (state.validSamples.isNotEmpty)
              MarkerLayer(
                markers: HistoryMapLayers.buildSamplePoints(
                  validSamples: state.validSamples,
                  onPointSelected: widget.onPointSelected,
                  nodeAddresses: _nodeAddresses,
                  showLabels: _showRouteLabels,
                  colors: context.appColors,
                ),
              ),

            // Marker thiết bị tại vị trí phát lại.
            if (state.currentPosition != null &&
                (state.isPlaying || state.isPaused || state.isCompleted))
              MarkerLayer(
                markers: [
                  HistoryMapLayers.buildReplayMarker(
                    state: state,
                    theme: theme,
                  )!,
                ],
              ),
          ],
        ),

        // Zoom in/out & Satellite controls góc trái
        Positioned(
          left: 12,
          top: 12,
          child: _MapZoomControls(
            onZoomIn: () {
              if (!_mapReady) return;
              _mapController.move(
                _mapController.camera.center,
                (_currentZoom + 1).clamp(4.0, 19.0),
              );
            },
            onZoomOut: () {
              if (!_mapReady) return;
              _mapController.move(
                _mapController.camera.center,
                (_currentZoom - 1).clamp(4.0, 19.0),
              );
            },
            onFitBounds: () {
              if (state.validSamples.isNotEmpty) {
                _fitRouteBounds(state.validSamples);
              }
            },
            onToggleMapType: () => context.read<SettingsCubit>().updateMapType(
              isSatellite ? AppMapType.standard : AppMapType.satellite,
            ),
            isSatellite: isSatellite,
            onToggleLabels: () =>
                setState(() => _showRouteLabels = !_showRouteLabels),
            showLabels: _showRouteLabels,
          ),
        ),

        // Trạng thái đang tải.
        if (state.isLoading)
          Positioned.fill(
            child: Container(
              color: context.appColors.shadow.withValues(alpha: 0.15),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2.5),
                        SizedBox(width: 14),
                        Text(
                          'Đang tải dữ liệu GPS...',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Trạng thái không có dữ liệu hoặc chỉ có một điểm.
        if (!state.isLoading && state.isEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: context.appColors.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: context.appColors.shadow.withValues(alpha: 0.12),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.route_outlined,
                        size: 40,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Không có dữ liệu vị trí trong khoảng thời gian đã chọn.',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: context.appColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Hãy chọn khoảng thời gian khác hoặc kiểm tra lại thiết bị.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else if (!state.isLoading && state.hasSinglePoint)
          Positioned(
            top: 12,
            left: 60,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: context.appColors.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.appColors.borderSoft),
              ),
              child: Text(
                'Chỉ có 1 mốc vị trí trong khoảng này.',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.appColors.textPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Cụm zoom và bật/tắt nhãn tuyến đường cho bản đồ hành trình.
class _MapZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitBounds;
  final VoidCallback onToggleMapType;
  final VoidCallback onToggleLabels;
  final bool isSatellite;
  final bool showLabels;

  const _MapZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitBounds,
    required this.onToggleMapType,
    required this.onToggleLabels,
    required this.isSatellite,
    required this.showLabels,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cụm 1: Phóng to, thu nhỏ, vừa toàn bộ lộ trình
        Container(
          decoration: _boxDecoration(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: context.appColors.primary,
                ),
                tooltip: 'Phóng to',
                onPressed: onZoomIn,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 28, child: Divider(height: 1)),
              IconButton(
                icon: Icon(
                  Icons.remove_rounded,
                  size: 18,
                  color: context.appColors.primary,
                ),
                tooltip: 'Thu nhỏ',
                onPressed: onZoomOut,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 28, child: Divider(height: 1)),
              IconButton(
                icon: Icon(
                  Icons.fit_screen_rounded,
                  size: 16,
                  color: context.appColors.primary,
                ),
                tooltip: 'Vừa toàn bộ lộ trình',
                onPressed: onFitBounds,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Cụm 2: Kiểu bản đồ và bật/tắt nhãn node hành trình
        Container(
          decoration: _boxDecoration(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
                  size: 18,
                  color: context.appColors.primary,
                ),
                tooltip: isSatellite
                    ? 'Chuyển sang bản đồ đường phố'
                    : 'Chuyển sang bản đồ vệ tinh',
                onPressed: onToggleMapType,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 28, child: Divider(height: 1)),
              IconButton(
                icon: Icon(
                  showLabels ? Icons.label_off_rounded : Icons.label_rounded,
                  size: 18,
                  color: context.appColors.primary,
                ),
                tooltip: showLabels
                    ? 'Ẩn nhãn mốc hành trình'
                    : 'Hiện nhãn mốc hành trình',
                onPressed: onToggleLabels,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _boxDecoration(BuildContext context) {
    return BoxDecoration(
      color: context.appColors.surface.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.appColors.border),
      boxShadow: [
        BoxShadow(
          color: context.appColors.shadow.withValues(alpha: 0.12),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    );
  }
}

// Tab 3: sự kiện theo dòng thời gian.

// Tab Sự kiện nhận DeviceEventModel thật từ DeviceDetailState và lọc theo nhóm hiển thị.
class _EventsTab extends StatefulWidget {
  const _EventsTab({required this.events});
  final List<DeviceEventModel> events;

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  // selectedCategory chỉ lọc danh sách cục bộ; không tạo hoặc sửa sự kiện backend.
  String _selectedCategory = 'all';

  @override
  Widget build(BuildContext context) {
    // Các chip lọc nằm trên danh sách timeline cuộn; empty state xuất hiện khi không
    // có event phù hợp với nhóm đang chọn.
    final theme = Theme.of(context);
    final allEvents = widget.events;

    // Lọc sự kiện theo nhóm người dùng đang chọn.
    final filteredEvents = _selectedCategory == 'all'
        ? allEvents
        : allEvents.where((e) => e.category == _selectedCategory).toList();

    // Counts for filter pills
    final connectivityCount = allEvents
        .where((e) => e.category == 'connectivity')
        .length;
    final movementCount = allEvents
        .where((e) => e.category == 'movement')
        .length;
    final alertCount = allEvents.where((e) => e.category == 'alert').length;

    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');

    return Column(
      children: [
        // ── CATEGORY FILTER BAR ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: context.appColors.surface,
            border: Border(
              bottom: BorderSide(color: context.appColors.borderSoft, width: 1),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _EventFilterChip(
                  label: 'Tất cả',
                  count: allEvents.length,
                  isSelected: _selectedCategory == 'all',
                  onTap: () => setState(() => _selectedCategory = 'all'),
                ),
                const SizedBox(width: 8),
                _EventFilterChip(
                  label: 'Kết nối',
                  count: connectivityCount,
                  isSelected: _selectedCategory == 'connectivity',
                  onTap: () =>
                      setState(() => _selectedCategory = 'connectivity'),
                ),
                const SizedBox(width: 8),
                _EventFilterChip(
                  label: 'Di chuyển',
                  count: movementCount,
                  isSelected: _selectedCategory == 'movement',
                  onTap: () => setState(() => _selectedCategory = 'movement'),
                ),
                const SizedBox(width: 8),
                _EventFilterChip(
                  label: 'Cảnh báo & Khác',
                  count: alertCount,
                  isSelected: _selectedCategory == 'alert',
                  onTap: () => setState(() => _selectedCategory = 'alert'),
                ),
              ],
            ),
          ),
        ),

        // ── TIMELINE LIST / EMPTY STATE ──
        Expanded(
          child: filteredEvents.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: context.appColors.borderSoft.withValues(
                              alpha: 0.5,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.event_note_rounded,
                            size: 28,
                            color: context.appColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _selectedCategory == 'all'
                              ? 'Chưa có sự kiện nào'
                              : 'Không có sự kiện thuộc danh mục này',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: context.appColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Các sự kiện trạng thái và di chuyển sẽ tự động xuất hiện tại đây khi thiết bị hoạt động.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: context.appColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  itemCount: filteredEvents.length,
                  itemBuilder: (context, index) {
                    final event = filteredEvents[index];
                    final isLast = index == filteredEvents.length - 1;

                    return _EventTimelineItem(
                      event: event,
                      dateFormat: dateFormat,
                      isLast: isLast,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// Chip lọc loại sự kiện với số lượng/nhãn dễ đọc.
class _EventFilterChip extends StatelessWidget {
  const _EventFilterChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? context.appColors.primary.withValues(alpha: 0.1)
              : context.appColors.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? context.appColors.primary.withValues(alpha: 0.4)
                : context.appColors.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? context.appColors.primary
                    : context.appColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? context.appColors.primary
                    : context.appColors.textDisabled,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? AppPalette.onAccent
                      : context.appColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Một dòng timeline hiển thị loại, mô tả, nguồn và thời điểm từ DeviceEventModel.
class _EventTimelineItem extends StatelessWidget {
  const _EventTimelineItem({
    required this.event,
    required this.dateFormat,
    required this.isLast,
  });

  final DeviceEventModel event;
  final DateFormat dateFormat;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _eventColor(event.eventType, context.appColors);
    final icon = _eventIcon(event.eventType);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cột dòng thời gian.
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: context.appColors.border,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Thẻ nội dung sự kiện.
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.appColors.borderSoft),
                boxShadow: [
                  BoxShadow(
                    color: context.appColors.shadow.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          event.eventLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: context.appColors.textPrimary,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dateFormat.format(event.occurredAt.toLocal()),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.appColors.textSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (event.description != null &&
                      event.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.description!,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.appColors.textPrimary.withValues(
                          alpha: 0.8,
                        ),
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _eventIcon(String type) {
    switch (type.toUpperCase()) {
      case 'ONLINE':
        return Icons.wifi_rounded;
      case 'OFFLINE':
        return Icons.wifi_off_rounded;
      case 'MOVING':
      case 'MOVEMENT_STARTED':
        return Icons.near_me_rounded;
      case 'IDLE':
      case 'MOVEMENT_STOPPED':
        return Icons.pause_circle_rounded;
      case 'GPS_LOST':
        return Icons.signal_wifi_statusbar_connected_no_internet_4_rounded;
      case 'GPS_RESTORED':
        return Icons.gps_fixed_rounded;
      case 'GEOFENCE_EXIT':
        return Icons.fmd_bad_rounded;
      case 'ERROR':
        return Icons.error_outline_rounded;
      case 'STARTED':
        return Icons.play_circle_rounded;
      case 'STOPPED':
        return Icons.stop_circle_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  Color _eventColor(String type, AppThemeColors colors) {
    switch (type.toUpperCase()) {
      case 'ONLINE':
        return colors.success;
      case 'OFFLINE':
        return colors.textSecondary;
      case 'MOVING':
      case 'MOVEMENT_STARTED':
        return colors.primary;
      case 'IDLE':
      case 'MOVEMENT_STOPPED':
        return colors.warning;
      case 'GPS_LOST':
      case 'GEOFENCE_EXIT':
      case 'ERROR':
        return colors.danger;
      case 'GPS_RESTORED':
        return colors.success;
      default:
        return colors.textSecondary;
    }
  }
}

// ─── Share Location ───────────────────────────────────────────────────────────

// Nút chia sẻ/mở vị trí nhận tọa độ thật và chuyển lựa chọn tới MapLauncherService.
class _ShareLocationInlineButton extends StatelessWidget {
  const _ShareLocationInlineButton({required this.device});

  final DeviceModel device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLocation = MapLauncherService.isValidCoordinate(
      device.latitude,
      device.longitude,
    );

    if (!hasLocation) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.share_location_rounded, size: 16),
        label: const Text('Chia sẻ vị trí'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Chia sẻ vị trí',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 210, maxWidth: 260),
      onSelected: (value) =>
          _handleShareLocationSelection(context, device, value),
      itemBuilder: (context) => _shareLocationMenuItems(context, device),
      child: Container(
        width: double.infinity,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: context.appColors.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.share_location_rounded,
              size: 16,
              color: AppPalette.onAccent,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Chia sẻ vị trí',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppPalette.onAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<PopupMenuEntry<String>> _shareLocationMenuItems(
  BuildContext context,
  DeviceModel device,
) {
  // Tạo menu theo các nền tảng bản đồ mà MapLauncherService báo có thể mở.
  final gpsTime = device.latestMeasuredAt ?? device.lastSeenAt;
  final isStale =
      gpsTime != null &&
      DateTime.now().difference(gpsTime.toLocal()).inMinutes > 5;

  return [
    if (isStale) ...[
      PopupMenuItem<String>(
        enabled: false,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'Vị trí cũ (${DeviceFormatters.dateTime(gpsTime)})',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
      const PopupMenuDivider(),
    ],
    const PopupMenuItem<String>(
      value: 'google',
      height: 42,
      padding: EdgeInsets.zero,
      child: AppMenuItem(icon: Icons.map_rounded, label: 'Google Maps'),
    ),
    const PopupMenuItem<String>(
      value: 'apple',
      height: 42,
      padding: EdgeInsets.zero,
      child: AppMenuItem(icon: Icons.apple, label: 'Apple Maps'),
    ),
    const PopupMenuItem<String>(
      value: 'copy',
      height: 42,
      padding: EdgeInsets.zero,
      child: AppMenuItem(
        icon: Icons.content_copy_rounded,
        label: 'Copy Location',
      ),
    ),
  ];
}

Future<void> _handleShareLocationSelection(
  BuildContext context,
  DeviceModel device,
  String value,
) async {
  // Thực hiện lựa chọn qua service nền tảng và hiển thị lỗi thân thiện nếu không mở được.
  if (value == 'google') {
    final success = await MapLauncherService.openGoogleMaps(
      device.latitude,
      device.longitude,
    );
    if (!success && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Không thể mở Google Maps')));
    }
  } else if (value == 'apple') {
    final success = await MapLauncherService.openAppleMaps(
      device.latitude,
      device.longitude,
    );
    if (!success && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Không thể mở Apple Maps')));
    }
  } else if (value == 'copy') {
    try {
      await MapLauncherService.copyLocationToClipboard(
        device,
        device.latitude,
        device.longitude,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã copy vị trí')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Không thể copy vị trí')));
      }
    }
  }
}
