import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/widgets/device_icon.dart';
import '../../core/utils/map_launcher_service.dart';
import '../../core/utils/device_formatters.dart';
import '../../data/models/device_model.dart';
import '../../data/models/device_event_model.dart';
import '../../data/models/location_model.dart';
import '../../data/models/assignment_model.dart';
import '../../data/models/usage_session_model.dart';
import '../../domain/entities/device_status_resolver.dart';
import 'device_detail_cubit.dart';

import '../../data/repositories/device_repository.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../data/repositories/tracking_repository.dart';

/// Chi tiết thiết bị — tracking dashboard cho Overview/Journey/Usage/Event.
class DeviceDetailPage extends StatelessWidget {
  const DeviceDetailPage({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
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

class _DeviceDetailView extends StatelessWidget {
  const _DeviceDetailView();

  @override
  Widget build(BuildContext context) {
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

        final status = DeviceStatusResolver.resolve(
          isOnline: device.isOnline,
          lastSeenAt: device.lastSeenAt,
          currentSpeedMps: device.currentSpeedMps,
          baseStatus: device.status,
        );

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            backgroundColor: _refBackground,
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
                          usages: state.usages,
                          events: state.events,
                        ),
                        _JourneyTab(
                          device: device,
                          locations: state.locations,
                          usages: state.usages,
                        ),
                        _UsageHistoryTab(
                          usages: state.usages,
                          assignments: state.assignments,
                        ),
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

// ─── Tab 1: Overview + Map ────────────────────────────────────────────────────

const _refBackground = Color(0xFFF7F9FC);
const _refSurface = Color(0xFFFFFFFF);
const _refPrimaryBlue = Color(0xFF1677FF);
const _refText = Color(0xFF111827);
const _refMuted = Color(0xFF667085);
const _refBorder = Color(0xFFE5EAF2);
const _refOnline = Color(0xFF16A34A);
const _refAmber = Color(0xFFD97706);

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
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;
    final statusText = status.connectivity == ConnectivityStatus.online
        ? 'Trực tuyến'
        : 'Ngoại tuyến';
    final statusColor = status.connectivity == ConnectivityStatus.online
        ? _refOnline
        : _refMuted;

    return Container(
      color: _refSurface,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 24,
              compact ? 12 : 20,
              compact ? 14 : 24,
              0,
            ),
            child: Row(
              children: [
                _BackSquareButton(
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    if (navigator.canPop()) {
                      navigator.pop();
                    } else {
                      context.goNamed('dashboard');
                    }
                  },
                ),
                const SizedBox(width: 20),
                Container(
                  width: compact ? 44 : 54,
                  height: compact ? 44 : 54,
                  decoration: BoxDecoration(
                    color: _refPrimaryBlue,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _refPrimaryBlue.withValues(alpha: 0.24),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(
                    DeviceIcon.iconFor(device.deviceType),
                    color: Colors.white,
                    size: compact ? 24 : 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DeviceFormatters.displayName(device),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: _refText,
                          fontWeight: FontWeight.w800,
                          height: 1.08,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${device.deviceCode}  ·  ${DeviceFormatters.deviceTypeLabel(device.deviceType)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _refMuted,
                          fontWeight: FontWeight.w500,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...[
                  _HeaderStatusText(label: statusText, color: statusColor),
                  const SizedBox(width: 24),
                  _HeaderActionButton(
                    icon: Icons.refresh_rounded,
                    label: 'Làm mới',
                    onPressed: onRefresh,
                  ),
                ] else
                  IconButton(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Làm mới',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: _refPrimaryBlue,
                unselectedLabelColor: _refMuted,
                dividerColor: Colors.transparent,
                indicatorColor: _refPrimaryBlue,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.tab,
                labelPadding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 28,
                ),
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                tabs: const [
                  Tab(height: 48, text: 'Tổng quan'),
                  Tab(height: 48, text: 'Hành trình'),
                  Tab(height: 48, text: 'Lịch sử sử dụng'),
                  Tab(height: 48, text: 'Sự kiện'),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: _refBorder),
        ],
      ),
    );
  }
}

class _BackSquareButton extends StatelessWidget {
  const _BackSquareButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: const BorderSide(color: _refBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          foregroundColor: _refMuted,
        ),
        child: const Icon(Icons.arrow_back_rounded, size: 24),
      ),
    );
  }
}

class _HeaderStatusText extends StatelessWidget {
  const _HeaderStatusText({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle_rounded, size: 9, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

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
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: _refText,
        backgroundColor: _refSurface,
        side: const BorderSide(color: _refBorder),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        textStyle: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

bool _hasText(String? value) => value?.trim().isNotEmpty == true;

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.device,
    required this.locations,
    this.address,
    required this.usages,
    required this.events,
  });
  final DeviceModel device;
  final List<LocationModel> locations;
  final String? address;
  final List<UsageSessionModel> usages;
  final List<DeviceEventModel> events;

  @override
  Widget build(BuildContext context) {
    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );
    final latestUsage = usages.isNotEmpty ? usages.first : null;
    final latestLocation = locations.isNotEmpty ? locations.first : null;
    final journey = _JourneySnapshot.from(locations, latestUsage);
    final altitudeM = device.currentAltitudeM ?? latestLocation?.altitudeM;
    final accuracyM = latestLocation?.accuracyM;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isWide = width >= 900;
        final horizontalPadding = width < 600 ? 12.0 : 22.0;
        final topHeight = isWide
            ? (width >= 1280 ? 374.0 : 350.0)
            : width >= 600
            ? 320.0
            : 260.0;
        final columns = width >= 1020
            ? 3
            : width >= 680
            ? 2
            : 1;
        final locationRows = _locationRows(
          context,
          status: status,
          latestLocation: latestLocation,
          altitudeM: altitudeM,
          accuracyM: accuracyM,
        );
        final usageRows = _usageRows(context, status, latestUsage);
        final journeyRows = _journeyRows(context, journey);
        final maxCardRows = [
          locationRows.length,
          usageRows.length,
          journeyRows.length,
        ].fold<int>(0, (current, count) => count > current ? count : current);
        final cardExtent = _sectionCardExtent(columns, maxCardRows);

        final cards = [
          _SectionCard(
            title: status.freshness == DataFreshnessStatus.stale
                ? 'Vị trí gần nhất'
                : 'Vị trí hiện tại',
            icon: Icons.location_on_rounded,
            iconColor: const Color(0xFF0D9488),
            children: locationRows,
          ),
          _SectionCard(
            title: 'Phiên sử dụng',
            icon: Icons.assignment_ind_rounded,
            iconColor: const Color(0xFF2563EB),
            children: usageRows,
          ),
          _SectionCard(
            title: 'Hành trình hiện tại',
            icon: Icons.route_rounded,
            iconColor: const Color(0xFF7C3AED),
            children: journeyRows,
          ),
        ];

        return SingleChildScrollView(
          padding: EdgeInsets.all(horizontalPadding),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isWide)
                    SizedBox(
                      height: topHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 65,
                            child: _MapOverviewCard(
                              map: _MapWidget(
                                device: device,
                                locations: locations,
                              ),
                              strip: _SummaryStrip(
                                device: device,
                                status: status,
                                latestUsage: latestUsage,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 35,
                            child: _CurrentSummaryPanel(
                              device: device,
                              status: status,
                              latestUsage: latestUsage,
                              journey: journey,
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    SizedBox(
                      height: topHeight,
                      child: _MapSurface(
                        child: _MapWidget(device: device, locations: locations),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _CurrentSummaryPanel(
                      device: device,
                      status: status,
                      latestUsage: latestUsage,
                      journey: journey,
                      compact: true,
                    ),
                  ],
                  if (!isWide) ...[
                    const SizedBox(height: 12),
                    _SummaryStrip(
                      device: device,
                      status: status,
                      latestUsage: latestUsage,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _AdaptiveSectionGrid(
                    columns: columns,
                    spacing: 12,
                    itemExtent: cardExtent,
                    children: cards,
                  ),
                  const SizedBox(height: 14),
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

  double _sectionCardExtent(int columns, int maxRows) {
    if (columns <= 1) return 0.0;
    final minExtent = columns == 3 ? 252.0 : 268.0;
    final maxExtent = columns == 3 ? 292.0 : 316.0;
    final estimatedExtent = 104.0 + (maxRows * 25.0);
    return estimatedExtent.clamp(minExtent, maxExtent).toDouble();
  }

  List<Widget> _locationRows(
    BuildContext context, {
    required ResolvedDeviceStatus status,
    required LocationModel? latestLocation,
    required double? altitudeM,
    required double? accuracyM,
  }) {
    final theme = Theme.of(context);
    if (device.latitude == null || device.longitude == null) {
      return const [
        _InfoRow(
          label: 'Tọa độ',
          value: 'Chưa có dữ liệu',
          icon: Icons.location_off_rounded,
        ),
      ];
    }

    return [
      if (_hasText(address))
        _InfoRow(
          label: 'Địa chỉ',
          value: address!.trim(),
          icon: Icons.location_city_rounded,
          maxLines: 2,
        ),
      _InfoRow(
        label: 'GPS',
        value: DeviceFormatters.coordinatePair(
          device.latitude,
          device.longitude,
        ),
        icon: Icons.my_location_rounded,
        maxLines: 2,
      ),
      if (altitudeM != null)
        _InfoRow(
          label: 'Độ cao',
          value: '${altitudeM.toStringAsFixed(1)} m',
          icon: Icons.height_rounded,
        ),
      if (accuracyM != null)
        _InfoRow(
          label: 'Độ chính xác',
          value: '±${accuracyM.toStringAsFixed(0)} m',
          icon: Icons.gps_fixed_rounded,
        ),
      _InfoRow(
        label: 'Cập nhật',
        value: DeviceFormatters.gpsFreshness(status, device.lastSeenAt),
        valueColor: status.freshness == DataFreshnessStatus.fresh
            ? null
            : theme.colorScheme.error,
        icon: Icons.schedule_rounded,
      ),
      Align(
        alignment: Alignment.centerRight,
        child: _ShareLocationCompactButton(device: device),
      ),
    ];
  }

  List<Widget> _usageRows(
    BuildContext context,
    ResolvedDeviceStatus status,
    UsageSessionModel? latestUsage,
  ) {
    final theme = Theme.of(context);
    final hasPerson = device.currentPersonName?.trim().isNotEmpty == true;
    final movingWithoutUser =
        status.movement == MovementStatus.moving &&
        !hasPerson &&
        latestUsage == null;

    if (latestUsage == null) {
      return [
        _InfoRow(
          label: 'Trạng thái',
          value: 'Chưa có phiên sử dụng',
          valueColor: theme.colorScheme.outline,
          icon: Icons.person_off_rounded,
        ),
        if (movingWithoutUser)
          const _AttentionNote(
            text: 'Thiết bị đang di chuyển nhưng chưa xác định người sử dụng',
          ),
      ];
    }

    final personName = latestUsage.personName?.trim().isNotEmpty == true
        ? latestUsage.personName!.trim()
        : device.currentPersonName?.trim().isNotEmpty == true
        ? device.currentPersonName!.trim()
        : 'Chưa xác định';

    return [
      _InfoRow(
        label: 'Người dùng',
        value: personName,
        icon: Icons.person_rounded,
        maxLines: 2,
      ),
      if (latestUsage.personCode?.trim().isNotEmpty == true)
        _InfoRow(
          label: 'Mã',
          value: latestUsage.personCode!.trim(),
          icon: Icons.badge_rounded,
        ),
      _InfoRow(
        label: 'Bắt đầu',
        value: DateFormat(
          'HH:mm dd/MM',
        ).format(latestUsage.startedAt.toLocal()),
        icon: Icons.play_circle_rounded,
      ),
      _InfoRow(
        label: 'Thời lượng',
        value: DeviceFormatters.duration(
          latestUsage.startedAt,
          latestUsage.endedAt,
        ),
        icon: Icons.timer_rounded,
      ),
      _InfoRow(
        label: 'Trạng thái',
        value: DeviceFormatters.usageStatus(latestUsage),
        icon: Icons.assignment_turned_in_rounded,
      ),
      Align(
        alignment: Alignment.center,
        child: TextButton.icon(
          onPressed: () => DefaultTabController.of(context).animateTo(2),
          label: const Text('Xem lịch sử sử dụng'),
          icon: const Icon(Icons.arrow_forward_rounded, size: 16),
          iconAlignment: IconAlignment.end,
        ),
      ),
    ];
  }

  List<Widget> _journeyRows(BuildContext context, _JourneySnapshot journey) {
    final rows = <Widget>[];
    if (journey.distanceM != null) {
      rows.add(
        _InfoRow(
          label: 'Quãng đường',
          value: DeviceFormatters.distance(journey.distanceM),
          icon: Icons.route_rounded,
        ),
      );
    }
    if (journey.movingDurationS != null) {
      rows.add(
        _InfoRow(
          label: 'Di chuyển',
          value: DeviceFormatters.secondsDuration(journey.movingDurationS),
          icon: Icons.navigation_rounded,
        ),
      );
    }
    if (journey.stoppedDurationS != null) {
      rows.add(
        _InfoRow(
          label: 'Dừng',
          value: DeviceFormatters.secondsDuration(journey.stoppedDurationS),
          icon: Icons.pause_circle_rounded,
        ),
      );
    }
    if (journey.avgSpeedMps != null) {
      rows.add(
        _InfoRow(
          label: 'Tốc độ TB',
          value: DeviceFormatters.speedMps(journey.avgSpeedMps),
          icon: Icons.speed_rounded,
        ),
      );
    }
    if (journey.maxSpeedMps != null) {
      rows.add(
        _InfoRow(
          label: 'Tốc độ lớn nhất',
          value: DeviceFormatters.speedMps(journey.maxSpeedMps),
          icon: Icons.flash_on_rounded,
        ),
      );
    }
    if (journey.startedAt != null) {
      rows.add(
        _InfoRow(
          label: 'Bắt đầu',
          value: DateFormat('HH:mm dd/MM').format(journey.startedAt!.toLocal()),
          icon: Icons.flag_rounded,
        ),
      );
    }

    if (rows.isEmpty) {
      return const [
        _InfoRow(
          label: 'Dữ liệu',
          value: 'Chưa đủ dữ liệu hành trình',
          icon: Icons.route_outlined,
        ),
      ];
    }

    rows.add(
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => DefaultTabController.of(context).animateTo(1),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('Xem hành trình'),
        ),
      ),
    );
    return rows;
  }
}

// ─── Shared detail info row ───────────────────────────────────────────────────

class _AdaptiveSectionGrid extends StatelessWidget {
  const _AdaptiveSectionGrid({
    required this.columns,
    required this.children,
    required this.itemExtent,
    this.spacing = 12,
  });

  final int columns;
  final List<Widget> children;
  final double itemExtent;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (columns <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _withVerticalSpacing(children),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: children.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        mainAxisExtent: itemExtent,
      ),
      itemBuilder: (context, index) => children[index],
    );
  }

  List<Widget> _withVerticalSpacing(List<Widget> items) {
    if (items.isEmpty) return items;
    return [
      for (var index = 0; index < items.length; index++) ...[
        if (index > 0) SizedBox(height: spacing),
        items[index],
      ],
    ];
  }
}

class _SummaryStrip extends StatefulWidget {
  const _SummaryStrip({
    required this.device,
    required this.status,
    required this.latestUsage,
  });

  final DeviceModel device;
  final ResolvedDeviceStatus status;
  final UsageSessionModel? latestUsage;

  @override
  State<_SummaryStrip> createState() => _SummaryStripState();
}

class _SummaryStripState extends State<_SummaryStrip> {
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
    final latestUsage = widget.latestUsage;
    final theme = Theme.of(context);
    final hasPerson = device.currentPersonName?.trim().isNotEmpty ?? false;
    final hasActiveUsage =
        latestUsage != null &&
        (latestUsage.endedAt == null || latestUsage.status == 'ACTIVE');

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
              ? const Color(0xFF2563EB)
              : const Color(0xFFD97706),
        ),
      _SummaryPill(
        icon: status.freshness == DataFreshnessStatus.fresh
            ? Icons.gps_fixed_rounded
            : Icons.gps_not_fixed_rounded,
        label: DeviceFormatters.gpsFreshness(status, device.lastSeenAt),
        color: status.freshness == DataFreshnessStatus.fresh
            ? const Color(0xFF16A34A)
            : theme.colorScheme.error,
        subtle: status.freshness == DataFreshnessStatus.unknown,
      ),
      _SummaryPill(
        icon: hasPerson ? Icons.person_rounded : Icons.warning_amber_rounded,
        label: hasPerson
            ? device.currentPersonName!.trim()
            : hasActiveUsage
            ? 'Đang có phiên sử dụng'
            : 'Chưa có người sử dụng',
        color: hasPerson ? theme.colorScheme.primary : const Color(0xFFEA580C),
        emphasized: !hasPerson,
      ),
    ];
    return Container(
      padding: EdgeInsets.zero,
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: false,
        trackVisibility: false,
        thickness: 2,
        radius: const Radius.circular(999),
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

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.icon,
    required this.label,
    required this.color,
    this.subtle = false,
    this.primary = false,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool subtle;
  final bool primary;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = subtle ? theme.colorScheme.onSurfaceVariant : color;
    final background = subtle
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.58)
        : color.withValues(alpha: primary ? 0.13 : 0.1);

    return Tooltip(
      message: label,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: primary ? 178 : 210,
          minHeight: primary ? 34 : 30,
        ),
        padding: EdgeInsets.fromLTRB(
          primary ? 6 : 10,
          primary ? 4 : 6,
          primary ? 12 : 10,
          primary ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: primary || emphasized
              ? Border.all(color: color.withValues(alpha: 0.16))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (primary)
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 14, color: color),
              )
            else
              Icon(icon, size: 13, color: foreground),
            SizedBox(width: primary ? 8 : 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: primary ? color : foreground,
                  fontWeight: primary ? FontWeight.w800 : FontWeight.w700,
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
    this.maxLines = 1,
  });
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 280;
        final labelWidth = constraints.maxWidth < 360 ? 116.0 : 134.0;
        final labelWidget = Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: theme.colorScheme.outline),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
        final valueWidget = Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor ?? theme.colorScheme.onSurface,
          ),
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    labelWidget,
                    const SizedBox(height: 2),
                    valueWidget,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: labelWidth, child: labelWidget),
                    const SizedBox(width: 12),
                    Expanded(child: valueWidget),
                  ],
                ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: _refSurface,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _refBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ─── Map Widget ───────────────────────────────────────────────────────────────

class _MapOverviewCard extends StatelessWidget {
  const _MapOverviewCard({required this.map, required this.strip});

  final Widget map;
  final Widget strip;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _referenceCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(child: map),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: _refSurface,
              border: Border(top: BorderSide(color: _refBorder)),
            ),
            child: strip,
          ),
        ],
      ),
    );
  }
}

class _MapSurface extends StatelessWidget {
  const _MapSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _referenceCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

BoxDecoration _referenceCardDecoration() {
  return BoxDecoration(
    color: _refSurface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: _refBorder),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.035),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

class _CurrentSummaryPanel extends StatelessWidget {
  const _CurrentSummaryPanel({
    required this.device,
    required this.status,
    required this.latestUsage,
    required this.journey,
    this.compact = false,
  });

  final DeviceModel device;
  final ResolvedDeviceStatus status;
  final UsageSessionModel? latestUsage;
  final _JourneySnapshot journey;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPerson = device.currentPersonName?.trim().isNotEmpty == true;
    final personName = latestUsage?.personName?.trim().isNotEmpty == true
        ? latestUsage!.personName!.trim()
        : hasPerson
        ? device.currentPersonName!.trim()
        : 'Chưa xác định người sử dụng';
    final usageLine = latestUsage == null
        ? 'Chưa có phiên sử dụng'
        : latestUsage!.endedAt == null || latestUsage!.status == 'ACTIVE'
        ? 'Đang sử dụng · ${DeviceFormatters.duration(latestUsage!.startedAt, latestUsage!.endedAt)}'
        : 'Phiên gần nhất · ${DeviceFormatters.duration(latestUsage!.startedAt, latestUsage!.endedAt)}';
    final movementColor = _movementColor(status, theme);
    final speed = DeviceFormatters.speed(device, status);
    final movingWithoutUser =
        status.movement == MovementStatus.moving &&
        !hasPerson &&
        latestUsage == null;
    final gpsLabel = DeviceFormatters.gpsFreshness(status, device.lastSeenAt);
    final gpsColor = status.freshness == DataFreshnessStatus.fresh
        ? _refOnline
        : theme.colorScheme.error;
    final startText = latestUsage == null
        ? '--'
        : DateFormat('HH:mm').format(latestUsage!.startedAt.toLocal());
    final durationText = latestUsage == null
        ? '--'
        : DeviceFormatters.duration(
            latestUsage!.startedAt,
            latestUsage!.endedAt,
          );
    final updateText = DeviceFormatters.lastSeen(device.lastSeenAt);

    return Card(
      elevation: 0,
      color: _refSurface,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _refBorder),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SummaryPill(
                    icon: _movementIcon(status),
                    label: _movementLabel(status),
                    color: movementColor,
                  ),
                  _SummaryPill(
                    icon: status.freshness == DataFreshnessStatus.fresh
                        ? Icons.location_on_rounded
                        : Icons.gps_not_fixed_rounded,
                    label: gpsLabel,
                    color: gpsColor,
                  ),
                  _SummaryPill(
                    icon: hasPerson
                        ? Icons.person_rounded
                        : Icons.warning_amber_rounded,
                    label: hasPerson ? personName : 'Chưa xác định người dùng',
                    color: hasPerson ? _refAmber : _refAmber,
                    emphasized: !hasPerson,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),
              _SpeedHeadingBlock(
                speedText: speed,
                headingText: DeviceFormatters.heading(device.currentHeadingDeg),
              ),
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 12),
              _PanelLine(
                icon: hasPerson
                    ? Icons.person_rounded
                    : Icons.person_off_rounded,
                label: personName,
                value: usageLine,
                color: hasPerson
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              _SummaryMetaGrid(
                startText: startText,
                durationText: durationText,
                updateText: updateText,
              ),
              if (journey.distanceM != null) ...[
                const SizedBox(height: 10),
                _PanelMetricLine(
                  label: 'Hành trình',
                  value: DeviceFormatters.distance(journey.distanceM),
                ),
              ],
              if (movingWithoutUser) ...[
                const SizedBox(height: 12),
                const _AttentionNote(
                  text: 'Đang di chuyển nhưng chưa có người sử dụng',
                ),
              ],
              SizedBox(height: compact ? 14 : 18),
              _ShareLocationInlineButton(device: device),
            ],
          ),
        ),
      ),
    );
  }

  static String _movementLabel(ResolvedDeviceStatus status) {
    switch (status.movement) {
      case MovementStatus.moving:
        return 'Đang di chuyển';
      case MovementStatus.stopped:
        return 'Đang dừng';
      case MovementStatus.unknown:
        return 'Chưa rõ di chuyển';
    }
  }

  static IconData _movementIcon(ResolvedDeviceStatus status) {
    switch (status.movement) {
      case MovementStatus.moving:
        return Icons.near_me_rounded;
      case MovementStatus.stopped:
        return Icons.pause_circle_rounded;
      case MovementStatus.unknown:
        return Icons.help_outline_rounded;
    }
  }

  static Color _movementColor(ResolvedDeviceStatus status, ThemeData theme) {
    switch (status.movement) {
      case MovementStatus.moving:
        return _refPrimaryBlue;
      case MovementStatus.stopped:
        return _refAmber;
      case MovementStatus.unknown:
        return theme.colorScheme.outline;
    }
  }
}

class _SpeedHeadingBlock extends StatelessWidget {
  const _SpeedHeadingBlock({
    required this.speedText,
    required this.headingText,
  });

  final String speedText;
  final String headingText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = speedText.split(' ');
    final speedValue = parts.isEmpty ? speedText : parts.first;
    final speedUnit = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TỐC ĐỘ HIỆN TẠI',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _refMuted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 10),
              RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: speedValue,
                      style: theme.textTheme.displayMedium?.copyWith(
                        color: _refPrimaryBlue,
                        fontWeight: FontWeight.w800,
                        height: 0.92,
                        letterSpacing: 0,
                      ),
                    ),
                    if (speedUnit.isNotEmpty)
                      TextSpan(
                        text: ' $speedUnit',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: _refText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(width: 1, height: 88, color: _refBorder),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HƯỚNG DI CHUYỂN',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _refMuted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _refPrimaryBlue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.explore_rounded,
                      color: _refPrimaryBlue,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      headingText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _refText,
                        fontWeight: FontWeight.w700,
                        height: 1.18,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryMetaGrid extends StatelessWidget {
  const _SummaryMetaGrid({
    required this.startText,
    required this.durationText,
    required this.updateText,
  });

  final String startText;
  final String durationText;
  final String updateText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryMetaItem(
            icon: Icons.schedule_rounded,
            label: 'BẮT ĐẦU',
            value: startText,
          ),
        ),
        Container(width: 1, height: 46, color: _refBorder),
        Expanded(
          child: _SummaryMetaItem(
            icon: Icons.timer_outlined,
            label: 'THỜI LƯỢNG',
            value: durationText,
          ),
        ),
        Container(width: 1, height: 46, color: _refBorder),
        Expanded(
          child: _SummaryMetaItem(
            icon: Icons.sync_rounded,
            label: 'CẬP NHẬT',
            value: updateText,
          ),
        ),
      ],
    );
  }
}

class _SummaryMetaItem extends StatelessWidget {
  const _SummaryMetaItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: _refMuted),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _refMuted,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _refText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelLine extends StatelessWidget {
  const _PanelLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.18,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.18,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelMetricLine extends StatelessWidget {
  const _PanelMetricLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _AttentionNote extends StatelessWidget {
  const _AttentionNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
      color: _refSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _refBorder),
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
                      DefaultTabController.of(context).animateTo(3),
                  child: const Text('Xem tất cả'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (recentEvents.isEmpty)
              _InfoRow(
                label: 'Timeline',
                value: 'Chưa có hoạt động gần đây',
                icon: Icons.event_busy_rounded,
                valueColor: theme.colorScheme.outline,
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 760) {
                    return Row(
                      children: [
                        for (
                          var index = 0;
                          index < recentEvents.length && index < 4;
                          index++
                        ) ...[
                          if (index > 0) const SizedBox(width: 22),
                          Expanded(
                            child: _RecentActivityRow(
                              event: recentEvents[index],
                              compact: true,
                            ),
                          ),
                        ],
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

class _RecentActivityRow extends StatelessWidget {
  const _RecentActivityRow({required this.event, this.compact = false});

  final DeviceEventModel event;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.circle_rounded,
            size: 12,
            color: _eventAccent(event.eventType),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: compact ? 50 : 48,
            child: Text(
              DateFormat('HH:mm').format(event.occurredAt.toLocal()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              DeviceFormatters.eventLabel(event),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _eventAccent(String type) {
  switch (type) {
    case 'MOVEMENT_STOPPED':
    case 'IDLE':
      return _refAmber;
    case 'MOVEMENT_STARTED':
    case 'MOVING':
      return _refPrimaryBlue;
    case 'ONLINE':
    case 'GPS_RESTORED':
      return _refOnline;
    default:
      return _refMuted;
  }
}

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
    List<LocationModel> locations,
    UsageSessionModel? usage,
  ) {
    final sorted = List<LocationModel>.from(locations)
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    final distance = _distanceFromSamples(sorted);
    final durations = _durationsFromSamples(sorted);
    final speeds = sorted
        .map((sample) => sample.speedMps)
        .whereType<double>()
        .where((speed) => speed >= 0)
        .toList();
    final avgSpeed = speeds.isEmpty
        ? null
        : speeds.reduce((a, b) => a + b) / speeds.length;
    final maxSpeed = speeds.isEmpty
        ? null
        : speeds.reduce((a, b) => a > b ? a : b);

    return _JourneySnapshot(
      distanceM: usage?.distanceM ?? distance,
      movingDurationS: usage?.movingDurationS ?? durations.$1,
      stoppedDurationS: usage?.stoppedDurationS ?? durations.$2,
      avgSpeedMps: usage?.avgSpeedMps ?? avgSpeed,
      maxSpeedMps: usage?.maxSpeedMps ?? maxSpeed,
      startedAt:
          usage?.startedAt ?? (sorted.isEmpty ? null : sorted.first.measuredAt),
      endedAt:
          usage?.endedAt ?? (sorted.length < 2 ? null : sorted.last.measuredAt),
      sampleCount: sorted.length,
    );
  }

  static double? _distanceFromSamples(List<LocationModel> sorted) {
    if (sorted.length < 2) return null;
    const distance = Distance();
    var total = 0.0;
    for (var index = 1; index < sorted.length; index++) {
      total += distance.as(
        LengthUnit.Meter,
        LatLng(sorted[index - 1].latitude, sorted[index - 1].longitude),
        LatLng(sorted[index].latitude, sorted[index].longitude),
      );
    }
    return total > 0 ? total : null;
  }

  static (int?, int?) _durationsFromSamples(List<LocationModel> sorted) {
    if (sorted.length < 2) return (null, null);
    var moving = 0;
    var stopped = 0;
    for (var index = 1; index < sorted.length; index++) {
      final seconds = sorted[index].measuredAt
          .difference(sorted[index - 1].measuredAt)
          .inSeconds;
      if (seconds <= 0 || seconds > 3600) continue;
      final speed = sorted[index - 1].speedMps ?? sorted[index].speedMps;
      if (speed == null) continue;
      if (speed > DeviceStatusResolver.movingThresholdMps) {
        moving += seconds;
      } else {
        stopped += seconds;
      }
    }
    return (moving > 0 ? moving : null, stopped > 0 ? stopped : null);
  }
}

class _MapWidget extends StatelessWidget {
  const _MapWidget({required this.device, required this.locations});
  final DeviceModel device;
  final List<LocationModel> locations;

  @override
  Widget build(BuildContext context) {
    final hasPosition = device.latitude != null && device.longitude != null;
    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );
    if (!hasPosition && locations.isEmpty) {
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

    final center = hasPosition
        ? LatLng(device.latitude!, device.longitude!)
        : LatLng(locations.first.latitude, locations.first.longitude);

    final routePoints = locations
        .map((l) => LatLng(l.latitude, l.longitude))
        .toList();

    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 15),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.vmonitor.app',
        ),
        if (routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                color: const Color(0xFF2563EB).withValues(alpha: 0.7),
                strokeWidth: 3,
              ),
            ],
          ),
        if (hasPosition)
          MarkerLayer(
            markers: [
              Marker(
                point: center,
                width: 40,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: _markerColor(status),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    DeviceIcon.iconFor(device.deviceType),
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        MarkerLayer(
          markers: locations
              .where((l) => !l.isMoving)
              .map(
                (l) => Marker(
                  point: LatLng(l.latitude, l.longitude),
                  width: 12,
                  height: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706).withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Color _markerColor(ResolvedDeviceStatus status) {
    if (status.connectivity == ConnectivityStatus.offline) return Colors.grey;
    if (status.freshness == DataFreshnessStatus.stale) return Colors.redAccent;
    if (status.movement == MovementStatus.moving) {
      return const Color(0xFF2563EB);
    }
    return const Color(0xFF16A34A);
  }
}

// ─── Tab 2: Usage History (Usages + Assignments combined) ────────────────────

class _JourneyTab extends StatefulWidget {
  const _JourneyTab({
    required this.device,
    required this.locations,
    required this.usages,
  });

  final DeviceModel device;
  final List<LocationModel> locations;
  final List<UsageSessionModel> usages;

  @override
  State<_JourneyTab> createState() => _JourneyTabState();
}

class _JourneyTabState extends State<_JourneyTab> {
  int _rangeIndex = 2;
  DateTimeRange? _customRange;

  @override
  Widget build(BuildContext context) {
    final filteredLocations = _filterLocations(widget.locations);
    final usage = widget.usages.isNotEmpty ? widget.usages.first : null;
    final snapshot = _JourneySnapshot.from(filteredLocations, usage);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final padding = width < 600 ? 12.0 : 16.0;
        final mapHeight = width >= 1024
            ? 380.0
            : width >= 600
            ? 320.0
            : 250.0;

        return ListView(
          padding: EdgeInsets.all(padding),
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _JourneyRangeBar(
                      selectedIndex: _rangeIndex,
                      customRange: _customRange,
                      onSelected: _selectRange,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: mapHeight,
                      child: _MapSurface(
                        child: _MapWidget(
                          device: widget.device,
                          locations: filteredLocations,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _JourneySummaryBand(snapshot: snapshot),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: 'Danh sách hành trình',
                      icon: Icons.route_rounded,
                      iconColor: Theme.of(context).colorScheme.primary,
                      children: [
                        if (snapshot.hasData)
                          _JourneyListItem(snapshot: snapshot, usage: usage)
                        else
                          const _InfoRow(
                            label: 'Dữ liệu',
                            value: 'Chưa có hành trình trong khoảng đã chọn',
                            icon: Icons.route_outlined,
                            maxLines: 2,
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
  }

  Future<void> _selectRange(int index) async {
    if (index == 3) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 1),
        initialDateRange:
            _customRange ??
            DateTimeRange(
              start: now.subtract(const Duration(days: 7)),
              end: now,
            ),
      );
      if (picked == null) return;
      setState(() {
        _rangeIndex = index;
        _customRange = picked;
      });
      return;
    }

    setState(() => _rangeIndex = index);
  }

  List<LocationModel> _filterLocations(List<LocationModel> locations) {
    final now = DateTime.now();
    late final DateTime start;
    late final DateTime end;
    if (_rangeIndex == 0) {
      start = DateTime(now.year, now.month, now.day);
      end = start.add(const Duration(days: 1));
    } else if (_rangeIndex == 1) {
      final today = DateTime(now.year, now.month, now.day);
      start = today.subtract(const Duration(days: 1));
      end = today;
    } else if (_rangeIndex == 3 && _customRange != null) {
      start = DateTime(
        _customRange!.start.year,
        _customRange!.start.month,
        _customRange!.start.day,
      );
      end = DateTime(
        _customRange!.end.year,
        _customRange!.end.month,
        _customRange!.end.day,
      ).add(const Duration(days: 1));
    } else {
      start = now.subtract(const Duration(days: 7));
      end = now.add(const Duration(minutes: 1));
    }

    return locations.where((location) {
      final measuredAt = location.measuredAt.toLocal();
      return !measuredAt.isBefore(start) && measuredAt.isBefore(end);
    }).toList();
  }
}

class _JourneyRangeBar extends StatelessWidget {
  const _JourneyRangeBar({
    required this.selectedIndex,
    required this.customRange,
    required this.onSelected,
  });

  final int selectedIndex;
  final DateTimeRange? customRange;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final labels = [
      'Hôm nay',
      'Hôm qua',
      '7 ngày',
      customRange == null
          ? 'Tùy chọn'
          : '${DateFormat('dd/MM').format(customRange!.start)} - ${DateFormat('dd/MM').format(customRange!.end)}',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            ChoiceChip(
              avatar: Icon(
                index == 3 ? Icons.date_range_rounded : Icons.schedule_rounded,
                size: 16,
              ),
              label: Text(labels[index]),
              selected: selectedIndex == index,
              onSelected: (_) => onSelected(index),
            ),
          ],
        ],
      ),
    );
  }
}

class _JourneySummaryBand extends StatelessWidget {
  const _JourneySummaryBand({required this.snapshot});

  final _JourneySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      _JourneyMetric(
        icon: Icons.route_rounded,
        label: 'Quãng đường',
        value: DeviceFormatters.distance(snapshot.distanceM),
      ),
      _JourneyMetric(
        icon: Icons.navigation_rounded,
        label: 'Di chuyển',
        value: DeviceFormatters.secondsDuration(snapshot.movingDurationS),
      ),
      _JourneyMetric(
        icon: Icons.pause_circle_rounded,
        label: 'Dừng',
        value: DeviceFormatters.secondsDuration(snapshot.stoppedDurationS),
      ),
      _JourneyMetric(
        icon: Icons.speed_rounded,
        label: 'Tốc độ lớn nhất',
        value: DeviceFormatters.speedMps(snapshot.maxSpeedMps),
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in items)
              Container(
                constraints: const BoxConstraints(minWidth: 150, maxWidth: 240),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.45,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(item.icon, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            item.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _JourneyMetric {
  const _JourneyMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _JourneyListItem extends StatelessWidget {
  const _JourneyListItem({required this.snapshot, required this.usage});

  final _JourneySnapshot snapshot;
  final UsageSessionModel? usage;

  @override
  Widget build(BuildContext context) {
    final start = snapshot.startedAt == null
        ? '--'
        : DateFormat('HH:mm dd/MM').format(snapshot.startedAt!.toLocal());
    final end = snapshot.endedAt == null
        ? 'hiện tại'
        : DateFormat('HH:mm dd/MM').format(snapshot.endedAt!.toLocal());
    final person = usage?.personName?.trim().isNotEmpty == true
        ? usage!.personName!.trim()
        : 'Chưa xác định người sử dụng';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoRow(
          label: 'Thời gian',
          value: '$start → $end',
          icon: Icons.schedule_rounded,
          maxLines: 2,
        ),
        _InfoRow(
          label: 'Quãng đường',
          value: DeviceFormatters.distance(snapshot.distanceM),
          icon: Icons.route_rounded,
        ),
        _InfoRow(
          label: 'Người dùng',
          value: person,
          icon: Icons.person_rounded,
          maxLines: 2,
        ),
        _InfoRow(
          label: 'Mẫu GPS',
          value: '${snapshot.sampleCount} mẫu',
          icon: Icons.scatter_plot_rounded,
        ),
      ],
    );
  }
}

class _UsageHistoryTab extends StatelessWidget {
  const _UsageHistoryTab({required this.usages, required this.assignments});
  final List<UsageSessionModel> usages;
  final List<AssignmentModel> assignments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (usages.isEmpty && assignments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 48,
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Chưa có lịch sử sử dụng',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    // Build a combined timeline: active assignment on top, then usage sessions
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Active assignment section
        if (assignments.isNotEmpty) ...[
          _TimelineHeader(label: 'Phân công thiết bị'),
          const SizedBox(height: 8),
          ...assignments.map(
            (a) => _AssignmentItem(a: a, dateFormat: dateFormat),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
        ],

        // Usage sessions
        if (usages.isNotEmpty) ...[
          _TimelineHeader(label: 'Phiên sử dụng'),
          const SizedBox(height: 8),
          ...usages.map((u) => _UsageItem(u: u, dateFormat: dateFormat)),
        ],
      ],
    );
  }
}

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _AssignmentItem extends StatelessWidget {
  const _AssignmentItem({required this.a, required this.dateFormat});
  final AssignmentModel a;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = a.unassignedAt == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: isActive
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : null,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: isActive
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: Icon(
              isActive ? Icons.person_rounded : Icons.person_off_rounded,
              size: 18,
              color: isActive
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.outline,
            ),
          ),
          title: Text(
            a.personName ?? 'Người dùng',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (a.personCode != null)
                Text('Mã: ${a.personCode}', style: theme.textTheme.bodySmall),
              Text(
                'Từ: ${dateFormat.format(a.assignedAt)}',
                style: theme.textTheme.bodySmall,
              ),
              if (!isActive)
                Text(
                  'Đến: ${dateFormat.format(a.unassignedAt!)}',
                  style: theme.textTheme.bodySmall,
                ),
              if (a.notes != null)
                Text('Ghi chú: ${a.notes}', style: theme.textTheme.bodySmall),
            ],
          ),
          trailing: isActive
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Đang giữ',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _UsageItem extends StatelessWidget {
  const _UsageItem({required this.u, required this.dateFormat});
  final UsageSessionModel u;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOngoing = u.endedAt == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.play_circle_rounded,
                    size: 16,
                    color: isOngoing
                        ? const Color(0xFF16A34A)
                        : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Phiên ${dateFormat.format(u.startedAt.toLocal())}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (isOngoing)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Đang diễn ra',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF16A34A),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              // Meta grid
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  if (u.personName != null)
                    _UsageMeta(
                      icon: Icons.person_rounded,
                      text: '${u.personName} (${u.personCode})',
                    ),
                  if (u.distanceM != null)
                    _UsageMeta(
                      icon: Icons.route_rounded,
                      text: '${(u.distanceM! / 1000).toStringAsFixed(2)} km',
                    ),
                  if (u.maxSpeedMps != null)
                    _UsageMeta(
                      icon: Icons.speed_rounded,
                      text:
                          'Max ${(u.maxSpeedMps! * 3.6).toStringAsFixed(1)} km/h',
                    ),
                  if (u.movingDurationS != null)
                    _UsageMeta(
                      icon: Icons.navigation_rounded,
                      text:
                          '${(u.movingDurationS! / 60).toStringAsFixed(0)} phút di chuyển',
                    ),
                  if (u.stoppedDurationS != null)
                    _UsageMeta(
                      icon: Icons.pause_circle_rounded,
                      text:
                          '${(u.stoppedDurationS! / 60).toStringAsFixed(0)} phút dừng',
                    ),
                  if (!isOngoing && u.endedAt != null)
                    _UsageMeta(
                      icon: Icons.stop_circle_rounded,
                      text: 'Đến ${dateFormat.format(u.endedAt!.toLocal())}',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageMeta extends StatelessWidget {
  const _UsageMeta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ─── Tab 3: Events — Timeline visual ─────────────────────────────────────────

class _EventsTab extends StatelessWidget {
  const _EventsTab({required this.events});
  final List<DeviceEventModel> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_note_rounded,
              size: 48,
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Chưa có sự kiện',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final dateFormat = DateFormat('dd/MM HH:mm:ss');

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final isLast = index == events.length - 1;

        return _EventTimelineItem(
          event: event,
          dateFormat: dateFormat,
          isLast: isLast,
        );
      },
    );
  }
}

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
    final color = _eventColor(event.eventType);
    final icon = _eventIcon(event.eventType);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline column
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: theme.colorScheme.outlineVariant,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.eventLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateFormat.format(event.occurredAt.toLocal()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
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

  IconData _eventIcon(String type) {
    switch (type) {
      case 'ONLINE':
        return Icons.check_circle_rounded;
      case 'OFFLINE':
        return Icons.cancel_rounded;
      case 'MOVING':
        return Icons.navigation_rounded;
      case 'IDLE':
        return Icons.pause_circle_rounded;
      case 'ASSIGNED':
        return Icons.person_add_rounded;
      case 'UNASSIGNED':
        return Icons.person_remove_rounded;
      case 'STARTED':
        return Icons.play_circle_rounded;
      case 'STOPPED':
        return Icons.stop_circle_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  Color _eventColor(String type) {
    switch (type) {
      case 'ONLINE':
        return const Color(0xFF16A34A);
      case 'OFFLINE':
        return Colors.grey;
      case 'MOVING':
        return const Color(0xFF2563EB);
      case 'IDLE':
        return const Color(0xFFD97706);
      case 'ASSIGNED':
        return const Color(0xFF0D9488);
      case 'UNASSIGNED':
        return const Color(0xFFDC2626);
      default:
        return Colors.grey;
    }
  }
}

// ─── Share Location ───────────────────────────────────────────────────────────

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
        icon: const Icon(Icons.share_location_rounded),
        label: const Text('Chia sẻ vị trí'),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Chia sẻ vị trí',
      position: PopupMenuPosition.under,
      onSelected: (value) =>
          _handleShareLocationSelection(context, device, value),
      itemBuilder: (context) => _shareLocationMenuItems(context, device),
      child: Container(
        width: double.infinity,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.share_location_rounded,
              size: 18,
              color: theme.colorScheme.onPrimary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Chia sẻ vị trí',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareLocationCompactButton extends StatelessWidget {
  const _ShareLocationCompactButton({required this.device});

  final DeviceModel device;

  @override
  Widget build(BuildContext context) {
    final hasLocation = MapLauncherService.isValidCoordinate(
      device.latitude,
      device.longitude,
    );

    if (!hasLocation) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.share_rounded, size: 16),
        label: const Text('Chia sẻ'),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Chia sẻ vị trí',
      position: PopupMenuPosition.under,
      onSelected: (value) =>
          _handleShareLocationSelection(context, device, value),
      itemBuilder: (context) => _shareLocationMenuItems(context, device),
      child: Container(
        height: 36,
        constraints: const BoxConstraints(minWidth: 132),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _refSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _refBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.share_rounded, size: 16, color: _refPrimaryBlue),
            const SizedBox(width: 8),
            Text(
              'Chia sẻ',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: _refPrimaryBlue,
                fontWeight: FontWeight.w700,
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
  final isStale =
      device.lastSeenAt != null &&
      DateTime.now().difference(device.lastSeenAt!.toLocal()).inMinutes > 5;

  return [
    if (isStale) ...[
      PopupMenuItem<String>(
        enabled: false,
        child: Text(
          'Vị trí cũ (${DateFormat('HH:mm dd/MM').format(device.lastSeenAt!.toLocal())})',
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
      child: Row(
        children: [
          Icon(Icons.map_rounded, size: 20),
          SizedBox(width: 12),
          Text('Google Maps'),
        ],
      ),
    ),
    const PopupMenuItem<String>(
      value: 'apple',
      child: Row(
        children: [
          Icon(Icons.apple, size: 20),
          SizedBox(width: 12),
          Text('Apple Maps'),
        ],
      ),
    ),
    const PopupMenuItem<String>(
      value: 'copy',
      child: Row(
        children: [
          Icon(Icons.content_copy_rounded, size: 20),
          SizedBox(width: 12),
          Text('Copy Location'),
        ],
      ),
    ),
  ];
}

Future<void> _handleShareLocationSelection(
  BuildContext context,
  DeviceModel device,
  String value,
) async {
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
