import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/map_tile_providers.dart';
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
import '../journey_history/journey_history_cubit.dart';
import '../journey_history/journey_history_state.dart';
import '../journey_history/widgets/custom_gap_dialog.dart';
import '../journey_history/widgets/history_map_layers.dart';
import '../journey_history/widgets/point_info_popup.dart';

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
          length: 3,
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
                    color: _refPrimaryBlue,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: _refPrimaryBlue.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    DeviceIcon.iconFor(device.deviceType),
                    color: Colors.white,
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
                          color: _refText,
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
                          color: _refMuted,
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
                labelColor: _refPrimaryBlue,
                unselectedLabelColor: _refMuted,
                dividerColor: Colors.transparent,
                indicatorColor: _refPrimaryBlue,
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
          const Divider(height: 1, color: _refBorder),
        ],
      ),
    );
  }
}

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
          side: const BorderSide(color: _refBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          foregroundColor: _refPrimaryBlue,
        ),
        child: Icon(
          Icons.arrow_back_rounded,
          size: compact ? 18 : 20,
          color: _refPrimaryBlue,
        ),
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
      icon: Icon(icon, size: 16, color: _refPrimaryBlue),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: _refPrimaryBlue,
        backgroundColor: _refSurface,
        side: BorderSide(color: _refPrimaryBlue.withValues(alpha: 0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
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
    final cubitState = state ?? context.watch<DeviceDetailCubit>().state;
    final cubit = context.read<DeviceDetailCubit>();

    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );
    final latestLocation = locations.isNotEmpty ? locations.first : null;
    final journey = _JourneySnapshot.from(locations);
    final altitudeM = device.currentAltitudeM ?? latestLocation?.altitudeM;
    final accuracyM = latestLocation?.accuracyM;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isWide = width >= 900;
        final horizontalPadding = width < 600 ? 12.0 : 22.0;
        final topHeight = isWide
            ? (width >= 1280 ? 460.0 : 430.0)
            : width >= 600
            ? 400.0
            : 340.0;
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
        final deviceInfoRows = _deviceInfoRows(context, status: status);
        final journeyRows = _journeyRows(journey, locations);
        final canShareLocation = MapLauncherService.isValidCoordinate(
          device.latitude,
          device.longitude,
        );
        final maxCardRows = [
          locationRows.length,
          deviceInfoRows.length,
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
            footer: canShareLocation
                ? Align(
                    alignment: Alignment.centerRight,
                    child: _ShareLocationCompactButton(device: device),
                  )
                : null,
            footerDivider: true,
            children: locationRows,
          ),
          _SectionCard(
            title: 'Thông tin thiết bị',
            icon: Icons.memory_rounded,
            iconColor: const Color(0xFF2563EB),
            footer: Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 14,
                  color: status.connectivity == ConnectivityStatus.online
                      ? _refOnline
                      : _refMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Trạng thái: ${device.statusLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _refMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            footerDivider: true,
            children: deviceInfoRows,
          ),
          _SectionCard(
            title: 'Hành trình hiện tại',
            icon: Icons.route_rounded,
            iconColor: const Color(0xFFEA580C),
            footer: Center(
              child: TextButton.icon(
                onPressed: () => DefaultTabController.of(context).animateTo(1),
                label: const Text('Xem chi tiết hành trình'),
                icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                iconAlignment: IconAlignment.end,
                style: TextButton.styleFrom(
                  foregroundColor: _refPrimaryBlue,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            footerDivider: true,
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
                  _OverviewTimeRangeFilterBar(
                    selectedRange: cubitState.timeRange,
                    rangeFrom: cubitState.rangeFrom,
                    rangeTo: cubitState.rangeTo,
                    isLoading: cubitState.isRangeLoading,
                    onSelectRange: (range) => cubit.setTimeRange(range),
                    onPickCustomRange: () => _pickCustomRange(context),
                  ),
                  const SizedBox(height: 12),
                  if (isWide)
                    SizedBox(
                      height: topHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 62,
                            child: _MapOverviewCard(
                              map: _MapWidget(
                                device: device,
                                locations: locations,
                              ),
                              strip: _SummaryStrip(
                                device: device,
                                status: status,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 38,
                            child: _CurrentSummaryPanel(
                              device: device,
                              status: status,
                              journey: journey,
                              address: address,
                              timeRangeLabel: cubitState.timeRange.label,
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
                      journey: journey,
                      address: address,
                      compact: true,
                      timeRangeLabel: cubitState.timeRange.label,
                    ),
                  ],
                  if (!isWide) ...[
                    const SizedBox(height: 12),
                    _SummaryStrip(device: device, status: status),
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

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 1)),
        end: now,
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: _refPrimaryBlue,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && context.mounted) {
      final from = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
        0,
        0,
        0,
      );
      final to = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
      );
      context.read<DeviceDetailCubit>().setTimeRange(
        OverviewTimeRange.custom,
        customFrom: from,
        customTo: to,
      );
    }
  }

  double _sectionCardExtent(int columns, int maxRows) {
    if (columns <= 1) return 0.0;
    final minExtent = columns == 3 ? 340.0 : 350.0;
    final maxExtent = columns == 3 ? 390.0 : 410.0;
    final estimatedExtent = 115.0 + (maxRows * 35.0);
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
          value: 'Chưa có dữ liệu vị trí',
          icon: Icons.location_off_rounded,
          iconColor: _refMuted,
        ),
      ];
    }

    return [
      if (_hasText(address)) _AddressInfoBlock(address: address!.trim()),
      _InfoRow(
        label: 'Tọa độ GPS',
        value: DeviceFormatters.coordinatePair(
          device.latitude,
          device.longitude,
        ),
        icon: Icons.my_location_rounded,
        iconColor: const Color(0xFF0D9488),
        maxLines: 1,
      ),
      _InfoRow(
        label: 'Độ cao',
        value: altitudeM != null ? '${altitudeM.toStringAsFixed(1)} m' : '--',
        icon: Icons.height_rounded,
        iconColor: const Color(0xFF6366F1),
      ),
      _InfoRow(
        label: 'Độ chính xác',
        value: accuracyM != null ? '±${accuracyM.toStringAsFixed(0)} m' : '--',
        icon: Icons.gps_fixed_rounded,
        iconColor: const Color(0xFF16A34A),
      ),
      _InfoRow(
        label: 'Vệ tinh',
        value: latestLocation?.satelliteCount != null
            ? '${latestLocation!.satelliteCount} vệ tinh'
            : '--',
        icon: Icons.satellite_alt_rounded,
        iconColor: const Color(0xFF0284C7),
      ),
      _InfoRow(
        label: 'Thời điểm',
        value: DeviceFormatters.dateTime(
          latestLocation?.measuredAt ?? device.lastSeenAt,
        ),
        valueColor: status.freshness == DataFreshnessStatus.fresh
            ? null
            : theme.colorScheme.error,
        icon: Icons.schedule_rounded,
        iconColor: const Color(0xFFEA580C),
        maxLines: 1,
      ),
    ];
  }

  List<Widget> _deviceInfoRows(
    BuildContext context, {
    required ResolvedDeviceStatus status,
  }) {
    final modelManufacturer = [
      device.model,
      device.manufacturer,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');

    return [
      _InfoRow(
        label: 'Tên thiết bị',
        value: DeviceFormatters.displayName(device),
        icon: Icons.badge_rounded,
        iconColor: const Color(0xFF2563EB),
      ),
      _InfoRow(
        label: 'Mã thiết bị',
        value: device.deviceCode,
        icon: Icons.qr_code_2_rounded,
        iconColor: const Color(0xFF475569),
      ),
      _InfoRow(
        label: 'Loại phương tiện',
        value: DeviceFormatters.deviceTypeLabel(device.deviceType),
        icon: Icons.category_rounded,
        iconColor: const Color(0xFF0D9488),
      ),
      _InfoRow(
        label: 'Model / Hãng',
        value: modelManufacturer.isNotEmpty ? modelManufacturer : '--',
        icon: Icons.precision_manufacturing_rounded,
        iconColor: const Color(0xFF7C3AED),
      ),
      _InfoRow(
        label: 'Số Serial',
        value: device.serialNumber ?? '--',
        icon: Icons.tag_rounded,
        iconColor: const Color(0xFF6366F1),
      ),
      _InfoRow(
        label: 'Firmware',
        value: device.firmwareVersion ?? '--',
        icon: Icons.system_update_alt_rounded,
        iconColor: const Color(0xFF0284C7),
      ),
    ];
  }

  List<Widget> _journeyRows(
    _JourneySnapshot journey,
    List<LocationModel> locations,
  ) {
    final startedTime = journey.startedAt != null
        ? DeviceFormatters.dateTime(journey.startedAt)
        : '--';
    final latestTime = journey.endedAt != null
        ? DeviceFormatters.dateTime(journey.endedAt)
        : (locations.isNotEmpty
              ? DeviceFormatters.dateTime(locations.first.measuredAt)
              : '--');
    final movingText = journey.movingDurationS != null
        ? DeviceFormatters.secondsDuration(journey.movingDurationS)
        : '--';
    final stoppedText = journey.stoppedDurationS != null
        ? DeviceFormatters.secondsDuration(journey.stoppedDurationS)
        : '--';
    final avgSpeedText = journey.avgSpeedMps != null
        ? DeviceFormatters.speedMps(journey.avgSpeedMps)
        : '--';
    final maxSpeedText = journey.maxSpeedMps != null
        ? DeviceFormatters.speedMps(journey.maxSpeedMps)
        : '--';

    return [
      _InfoRow(
        label: 'Quãng đường',
        value: journey.distanceM != null
            ? DeviceFormatters.distance(journey.distanceM)
            : '--',
        icon: Icons.route_rounded,
        iconColor: const Color(0xFFEA580C),
      ),
      _InfoRow(
        label: 'Bắt đầu',
        value: startedTime,
        icon: Icons.play_circle_outline_rounded,
        iconColor: const Color(0xFF16A34A),
      ),
      _InfoRow(
        label: 'Cập nhật cuối',
        value: latestTime,
        icon: Icons.flag_outlined,
        iconColor: const Color(0xFFDC2626),
      ),
      _InfoRow(
        label: 'Chạy / Dừng',
        value: '$movingText / $stoppedText',
        icon: Icons.timer_outlined,
        iconColor: const Color(0xFF2563EB),
      ),
      _InfoRow(
        label: 'Vận tốc TB / Max',
        value: '$avgSpeedText / $maxSpeedText',
        icon: Icons.speed_rounded,
        iconColor: const Color(0xFF7C3AED),
      ),
      _InfoRow(
        label: 'Điểm GPS',
        value: journey.sampleCount > 0 ? '${journey.sampleCount} điểm' : '--',
        icon: Icons.scatter_plot_rounded,
        iconColor: const Color(0xFF0D9488),
      ),
    ];
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
  const _SummaryStrip({required this.device, required this.status});

  final DeviceModel device;
  final ResolvedDeviceStatus status;

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
          color: const Color(0xFFF0FDFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCCFBF1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Center(
                child: Icon(
                  Icons.location_on_rounded,
                  size: 13,
                  color: Color(0xFF0D9488),
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
                      color: const Color(0xFF0F172A),
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
                        color: const Color(0xFF64748B),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
    this.iconColor,
    this.maxLines = 1,
  });
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;
  final Color? iconColor;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveIconColor = iconColor ?? _refPrimaryBlue;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 240;
        final labelWidth = (constraints.maxWidth * 0.38)
            .clamp(92.0, 130.0)
            .toDouble();

        final labelWidget = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: effectiveIconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Center(
                  child: Icon(icon, size: 12, color: effectiveIconColor),
                ),
              ),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                  height: 1.15,
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
            fontWeight: FontWeight.w700,
            color: valueColor ?? const Color(0xFF0F172A),
            fontSize: 12.5,
            height: 1.2,
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
                    Padding(
                      padding: const EdgeInsets.only(left: 29),
                      child: valueWidget,
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(width: labelWidth, child: labelWidget),
                    const SizedBox(width: 8),
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
    this.footer,
    this.footerDivider = true,
  });
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;
  final Widget? footer;
  final bool footerDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: _refSurface,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _refBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasBoundedHeight = constraints.hasBoundedHeight;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: hasBoundedHeight
                ? MainAxisSize.max
                : MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: iconColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: iconColor,
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
              if (footer != null) ...[
                if (hasBoundedHeight)
                  const Spacer()
                else
                  const SizedBox(height: 2),
                if (footerDivider) const Divider(height: 1, color: _refBorder),
                SizedBox(
                  height: 43,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: footer,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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

// ─── Overview Time Range Filter Bar ──────────────────────────────────────────

class _OverviewTimeRangeFilterBar extends StatelessWidget {
  const _OverviewTimeRangeFilterBar({
    required this.selectedRange,
    required this.rangeFrom,
    required this.rangeTo,
    required this.isLoading,
    required this.onSelectRange,
    required this.onPickCustomRange,
  });

  final OverviewTimeRange selectedRange;
  final DateTime? rangeFrom;
  final DateTime? rangeTo;
  final bool isLoading;
  final ValueChanged<OverviewTimeRange> onSelectRange;
  final VoidCallback onPickCustomRange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bannerText = _formatRangeBanner(selectedRange, rangeFrom, rangeTo);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _refSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _refBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chips = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: OverviewTimeRange.values.map((range) {
                final isSelected = selectedRange == range;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      if (range == OverviewTimeRange.custom) {
                        onPickCustomRange();
                      } else {
                        onSelectRange(range);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _refPrimaryBlue.withValues(alpha: 0.1)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? _refPrimaryBlue
                              : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.2 : 1.0,
                        ),
                      ),
                      child: Text(
                        range.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? _refPrimaryBlue
                              : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );

          final banner = ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  size: 14,
                  color: _refPrimaryBlue,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    bannerText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF334155),
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isLoading) ...[
                  const SizedBox(width: 6),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _refPrimaryBlue,
                    ),
                  ),
                ],
              ],
            ),
          );

          return Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              chips,
              banner,
            ],
          );
        },
      ),
    );
  }

  static String _formatRangeBanner(
    OverviewTimeRange range,
    DateTime? from,
    DateTime? to,
  ) {
    final now = DateTime.now();
    final timeFmt = DateFormat('HH:mm');
    final dateFmt = DateFormat('dd/MM/yyyy');
    final shortDateFmt = DateFormat('dd/MM HH:mm');
    final fullDateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

    switch (range) {
      case OverviewTimeRange.today:
        final dateStr = dateFmt.format(now);
        final toStr = to != null ? timeFmt.format(to) : timeFmt.format(now);
        return 'Hôm nay, $dateStr • 00:00 – $toStr';
      case OverviewTimeRange.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        final dateStr = dateFmt.format(yesterday);
        return 'Hôm qua, $dateStr • 00:00 – 23:59';
      case OverviewTimeRange.last24h:
        final fromStr = from != null ? shortDateFmt.format(from) : '--';
        final toStr = to != null ? shortDateFmt.format(to) : '--';
        return '24 giờ qua • $fromStr – $toStr';
      case OverviewTimeRange.last7d:
        final fromStr = from != null ? dateFmt.format(from) : '--';
        final toStr = to != null ? dateFmt.format(to) : '--';
        return '7 ngày qua • $fromStr – $toStr';
      case OverviewTimeRange.custom:
        final fromStr = from != null ? fullDateTimeFmt.format(from) : '--';
        final toStr = to != null ? fullDateTimeFmt.format(to) : '--';
        return 'Tùy chỉnh • $fromStr – $toStr';
    }
  }
}

class _CurrentSummaryPanel extends StatelessWidget {
  const _CurrentSummaryPanel({
    required this.device,
    required this.status,
    required this.journey,
    this.address,
    this.compact = false,
    this.timeRangeLabel,
  });

  final DeviceModel device;
  final ResolvedDeviceStatus status;
  final _JourneySnapshot journey;
  final String? address;
  final bool compact;
  final String? timeRangeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final speed = DeviceFormatters.speed(device, status);
    final heading = DeviceFormatters.heading(device.currentHeadingDeg);
    final altitudeText = device.currentAltitudeM != null
        ? '${device.currentAltitudeM!.toStringAsFixed(1)} m'
        : '--';
    final distanceText = journey.distanceM != null
        ? DeviceFormatters.distance(journey.distanceM)
        : '--';
    final movingDurationText = journey.movingDurationS != null
        ? DeviceFormatters.secondsDuration(journey.movingDurationS)
        : '--';
    final stoppedDurationText = journey.stoppedDurationS != null
        ? DeviceFormatters.secondsDuration(journey.stoppedDurationS)
        : '--';

    final isMoving = status.movement == MovementStatus.moving;
    final isStopped = status.movement == MovementStatus.stopped;
    final movementStatusLabel = isMoving
        ? 'Đang di chuyển'
        : (isStopped ? 'Đang dừng' : 'Không xác định');
    final movementStatusColor = isMoving
        ? _refOnline
        : (isStopped ? _refAmber : _refMuted);

    return Card(
      elevation: 0,
      color: _refSurface,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _refBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTightlyBounded =
              constraints.hasBoundedHeight && constraints.maxHeight > 260;
          final panelPadding = compact ? 12.0 : 16.0;

          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: isTightlyBounded
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.start,
            mainAxisSize: isTightlyBounded
                ? MainAxisSize.max
                : MainAxisSize.min,
            children: [
              // 1. Header (Title)
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _refPrimaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: _refPrimaryBlue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Thông số vận hành',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: _refText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (!isTightlyBounded) const SizedBox(height: 12),

              // 2. Telemetry Tiles (3 rows x 2 columns)
              // Row 1: Tốc độ & Hướng di chuyển
              Row(
                children: [
                  Expanded(
                    child: _TelemetryMetricTile(
                      icon: Icons.speed_rounded,
                      iconColor: const Color(0xFF2563EB),
                      label: 'TỐC ĐỘ HIỆN TẠI',
                      value: speed,
                      subValue: movementStatusLabel,
                      subValueColor: movementStatusColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TelemetryMetricTile(
                      icon: Icons.explore_rounded,
                      iconColor: const Color(0xFF7C3AED),
                      label: 'HƯỚNG DI CHUYỂN',
                      value: heading,
                      subValue: device.currentHeadingDeg != null
                          ? 'Góc ${device.currentHeadingDeg!.toStringAsFixed(0)}°'
                          : null,
                    ),
                  ),
                ],
              ),
              if (!isTightlyBounded) const SizedBox(height: 10),

              // Row 2: Độ cao & Quãng đường
              Row(
                children: [
                  Expanded(
                    child: _TelemetryMetricTile(
                      icon: Icons.height_rounded,
                      iconColor: const Color(0xFF0D9488),
                      label: 'ĐỘ CAO',
                      value: altitudeText,
                      subValue: 'So với mực nước biển',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TelemetryMetricTile(
                      icon: Icons.route_rounded,
                      iconColor: const Color(0xFFEA580C),
                      label: 'QUÃNG ĐƯỜNG',
                      value: distanceText,
                      subValue: timeRangeLabel != null
                          ? 'Trong $timeRangeLabel'
                          : 'Hành trình ghi nhận',
                    ),
                  ),
                ],
              ),
              if (!isTightlyBounded) const SizedBox(height: 10),

              // Row 3: Thời gian di chuyển & Thời gian dừng
              Row(
                children: [
                  Expanded(
                    child: _TelemetryMetricTile(
                      icon: Icons.timer_outlined,
                      iconColor: const Color(0xFF16A34A),
                      label: 'THỜI GIAN CHẠY',
                      value: movingDurationText,
                      subValue: 'Thời gian di chuyển',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TelemetryMetricTile(
                      icon: Icons.pause_circle_outline_rounded,
                      iconColor: const Color(0xFFD97706),
                      label: 'THỜI GIAN DỪNG',
                      value: stoppedDurationText,
                      subValue: 'Thời gian dừng đỗ',
                    ),
                  ),
                ],
              ),
              if (!isTightlyBounded) const SizedBox(height: 12),

              // 3. Action Footer (Chia sẻ vị trí & Xem hành trình)
              Row(
                children: [
                  Expanded(child: _ShareLocationInlineButton(device: device)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          DefaultTabController.of(context).animateTo(1),
                      icon: const Icon(Icons.timeline_rounded, size: 16),
                      label: const Text('Xem hành trình'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _refPrimaryBlue,
                        side: const BorderSide(color: _refPrimaryBlue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
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

class _TelemetryMetricTile extends StatelessWidget {
  const _TelemetryMetricTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.subValue,
    this.subValueColor,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? subValue;
  final Color? subValueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _refMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: _refText,
              fontWeight: FontWeight.w800,
              fontSize: 14.5,
              height: 1.15,
            ),
          ),
          if (subValue != null) ...[
            const SizedBox(height: 2),
            Text(
              subValue!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: subValueColor ?? _refMuted,
                fontWeight: subValueColor != null
                    ? FontWeight.w700
                    : FontWeight.w500,
                fontSize: 10.5,
                height: 1.1,
              ),
            ),
          ],
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
                      DefaultTabController.of(context).animateTo(2),
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
              color: _eventAccent(event.eventType),
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
    List<LocationModel> locations, {
    Duration gapThreshold = const Duration(minutes: 5),
    double movingThresholdMps = 0.5,
  }) {
    if (locations.isEmpty) return const _JourneySnapshot();

    // 1. Sanitize GPS outliers & invalid coordinates
    final validSamples = GpsValidator.sanitizeSamples(locations);
    if (validSamples.isEmpty) return const _JourneySnapshot();

    // 2. Split into segments using standard gap threshold
    final segments = RouteSegment.splitIntoSegments(
      validSamples,
      gapThreshold: gapThreshold,
      movingThresholdMps: movingThresholdMps,
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

class _MapWidget extends StatefulWidget {
  const _MapWidget({required this.device, required this.locations});
  final DeviceModel device;
  final List<LocationModel> locations;

  @override
  State<_MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<_MapWidget> {
  static const _initialZoom = 15.0;
  static const _minZoom = 5.0;
  static const _maxZoom = 18.0;
  static const _zoomStep = 1.0;
  static const _fallbackCenter = LatLng(21.0285, 105.8542);

  final MapController _mapController = MapController();
  late LatLng _targetCenter;
  var _zoom = _initialZoom;
  var _mapReady = false;
  var _isSatellite = false;

  @override
  void initState() {
    super.initState();
    _targetCenter = _resolveCenter();
  }

  @override
  void didUpdateWidget(covariant _MapWidget oldWidget) {
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
    final hasPosition =
        widget.device.latitude != null && widget.device.longitude != null;
    final status = DeviceStatusResolver.resolve(
      isOnline: widget.device.isOnline,
      lastSeenAt: widget.device.lastSeenAt,
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
            color: const Color(0xFFEFF5F8),
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
                    _isSatellite ? AppMapType.satellite : AppMapType.standard,
                  ),
                  userAgentPackageName: 'com.vmonitor.app',
                  minZoom: _minZoom,
                  maxZoom: _maxZoom,
                  maxNativeZoom: MapTileProviders.getMaxZoom(
                    _isSatellite ? AppMapType.satellite : AppMapType.standard,
                  ),
                  tileProvider: NetworkTileProvider(silenceExceptions: true),
                  errorImage: MemoryImage(TileProvider.transparentImage),
                ),
                if (hasPosition || widget.locations.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _targetCenter,
                        width: 58,
                        height: 66,
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
                  setState(() => _isSatellite = !_isSatellite),
              isSatellite: _isSatellite,
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
    if (status.connectivity == ConnectivityStatus.offline) return Colors.grey;
    if (status.freshness == DataFreshnessStatus.stale) return Colors.redAccent;
    if (status.movement == MovementStatus.moving) {
      return const Color(0xFF2563EB);
    }
    return const Color(0xFF16A34A);
  }
}

class _DeviceMapMarker extends StatelessWidget {
  const _DeviceMapMarker({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 66,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 34,
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.28),
                      blurRadius: 16,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.32),
                  blurRadius: 18,
                  spreadRadius: 3,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }
}

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
          decoration: _mapControlDecoration(),
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
          decoration: _mapControlDecoration(),
          child: _MapControlButton(
            icon: isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
            tooltip: isSatellite
                ? 'Chuyển sang bản đồ đường phố'
                : 'Chuyển sang bản đồ vệ tinh',
            iconColor: _refPrimaryBlue,
            onPressed: onToggleMapType,
          ),
        ),
      ],
    );
  }

  BoxDecoration _mapControlDecoration() {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _refBorder),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 4)),
      ],
    );
  }
}

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
          icon: Icon(icon, size: 18, color: _refPrimaryBlue),
        ),
      ),
    );
  }
}

// ─── Tab 2: Journey (Hành trình GPS & Replay — Reference Design) ─────────────

class _JourneyTab extends StatefulWidget {
  const _JourneyTab({required this.device, required this.locations});

  final DeviceModel device;
  final List<LocationModel> locations;

  @override
  State<_JourneyTab> createState() => _JourneyTabState();
}

class _JourneyTabState extends State<_JourneyTab> {
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
    return BlocProvider.value(
      value: _cubit,
      child: BlocConsumer<JourneyHistoryCubit, JourneyHistoryState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: Colors.redAccent,
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
                          // ─── TẦNG 1: Filter / Time Range Panel ───────────────
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
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // CỘT TRÁI (~77%): Map + Playback + Current Info
                                Expanded(
                                  flex: 77,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // 1. Map Card
                                      _JourneyMapCard(
                                        state: state,
                                        height: 380,
                                        onPointSelected: (pt) =>
                                            _cubit.selectPoint(pt),
                                      ),
                                      const SizedBox(height: 10),

                                      // 2. Playback Card
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

                                      // 3. Current Info Card
                                      _JourneyCurrentInfoCard(state: state),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // CỘT PHẢI (~23%): Vertical Timeline
                                Expanded(
                                  flex: 23,
                                  child: _JourneyTimelineCard(
                                    state: state,
                                    height:
                                        596, // Cân đối hoàn hảo với tổng chiều cao cột trái
                                    onSelectSample: (s) {
                                      _cubit.seekToTime(s.measuredAt);
                                      _cubit.selectPoint(s);
                                    },
                                  ),
                                ),
                              ],
                            )
                          else
                            // Layout xếp tầng dọc cho Mobile / Tablet
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
    var tempFrom = _fromTime;
    var tempTo = _toTime;

    final result = await showDialog<DateTimeRange>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final dateFormat = DateFormat('dd/MM/yyyy');
            final timeFormat = DateFormat('HH:mm');
            final isValid = tempFrom.isBefore(tempTo);

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.edit_calendar_rounded,
                    size: 20,
                    color: _refPrimaryBlue,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Tùy chọn khoảng thời gian',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _refText,
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Mốc bắt đầu (Từ):',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: _refText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              side: const BorderSide(color: _refBorder),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(
                              Icons.calendar_today_rounded,
                              size: 14,
                              color: _refPrimaryBlue,
                            ),
                            label: Text(
                              dateFormat.format(tempFrom),
                              style: const TextStyle(
                                fontSize: 12,
                                color: _refText,
                              ),
                            ),
                            onPressed: () async {
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: tempFrom,
                                firstDate: DateTime(DateTime.now().year - 3),
                                lastDate: DateTime(DateTime.now().year + 1),
                              );
                              if (pickedDate != null) {
                                setDialogState(() {
                                  tempFrom = DateTime(
                                    pickedDate.year,
                                    pickedDate.month,
                                    pickedDate.day,
                                    tempFrom.hour,
                                    tempFrom.minute,
                                    tempFrom.second,
                                  );
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              side: const BorderSide(color: _refBorder),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: _refPrimaryBlue,
                            ),
                            label: Text(
                              timeFormat.format(tempFrom),
                              style: const TextStyle(
                                fontSize: 12,
                                color: _refText,
                              ),
                            ),
                            onPressed: () async {
                              final pickedTime = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(
                                  hour: tempFrom.hour,
                                  minute: tempFrom.minute,
                                ),
                              );
                              if (pickedTime != null) {
                                setDialogState(() {
                                  tempFrom = DateTime(
                                    tempFrom.year,
                                    tempFrom.month,
                                    tempFrom.day,
                                    pickedTime.hour,
                                    pickedTime.minute,
                                    0,
                                  );
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    const Text(
                      'Mốc kết thúc (Đến):',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: _refText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              side: const BorderSide(color: _refBorder),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(
                              Icons.calendar_today_rounded,
                              size: 14,
                              color: _refPrimaryBlue,
                            ),
                            label: Text(
                              dateFormat.format(tempTo),
                              style: const TextStyle(
                                fontSize: 12,
                                color: _refText,
                              ),
                            ),
                            onPressed: () async {
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: tempTo,
                                firstDate: DateTime(DateTime.now().year - 3),
                                lastDate: DateTime(DateTime.now().year + 1),
                              );
                              if (pickedDate != null) {
                                setDialogState(() {
                                  tempTo = DateTime(
                                    pickedDate.year,
                                    pickedDate.month,
                                    pickedDate.day,
                                    tempTo.hour,
                                    tempTo.minute,
                                    tempTo.second,
                                  );
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              side: const BorderSide(color: _refBorder),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: _refPrimaryBlue,
                            ),
                            label: Text(
                              timeFormat.format(tempTo),
                              style: const TextStyle(
                                fontSize: 12,
                                color: _refText,
                              ),
                            ),
                            onPressed: () async {
                              final pickedTime = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(
                                  hour: tempTo.hour,
                                  minute: tempTo.minute,
                                ),
                              );
                              if (pickedTime != null) {
                                setDialogState(() {
                                  tempTo = DateTime(
                                    tempTo.year,
                                    tempTo.month,
                                    tempTo.day,
                                    pickedTime.hour,
                                    pickedTime.minute,
                                    59,
                                  );
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (!isValid)
                      const Text(
                        'Thời gian bắt đầu phải trước thời gian kết thúc!',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _refPrimaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: isValid
                      ? () => Navigator.of(
                          dialogContext,
                        ).pop(DateTimeRange(start: tempFrom, end: tempTo))
                      : null,
                  child: const Text('Áp dụng'),
                ),
              ],
            );
          },
        );
      },
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

// ─── TẦNG 1: Panel Bộ Lọc Thời Gian ──────────────────────────────────────────

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
        color: _refSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _refBorder),
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
                    const Text(
                      'Khoảng thời gian',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _refMuted,
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
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _refBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Từ ',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: _refMuted,
                              ),
                            ),
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 13,
                              color: _refPrimaryBlue,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dtFormat.format(fromTime),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: _refText,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 12,
                                color: _refMuted,
                              ),
                            ),
                            const Text(
                              'Đến ',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: _refMuted,
                              ),
                            ),
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 13,
                              color: _refPrimaryBlue,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dtFormat.format(toTime),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: _refText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                const SizedBox(
                  height: 38,
                  child: VerticalDivider(width: 1, color: _refBorder),
                ),
                const SizedBox(width: 16),

                // Nhóm B: Khoảng nhanh
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Khoảng nhanh',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _refMuted,
                        ),
                      ),
                      const SizedBox(height: 5),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildQuickChip('Hôm nay', 0),
                            const SizedBox(width: 6),
                            _buildQuickChip('Hôm qua', 1),
                            const SizedBox(width: 6),
                            _buildQuickChip('24h qua', 2),
                            const SizedBox(width: 6),
                            _buildQuickChip('7 ngày', 3),
                            const SizedBox(width: 6),
                            _buildQuickChip(
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
                const SizedBox(
                  height: 38,
                  child: VerticalDivider(width: 1, color: _refBorder),
                ),
                const SizedBox(width: 16),

                // Nhóm C: Ngắt quãng + Tải lại
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Ngắt quãng',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _refMuted,
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
                            backgroundColor: _refPrimaryBlue,
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
                                    color: Colors.white,
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

          // Layout nhỏ gọn khi hẹp (Tablet / Mobile)
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
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _refBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 14,
                        color: _refPrimaryBlue,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${dtFormat.format(fromTime)}  →  ${dtFormat.format(toTime)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _refText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Chips nhanh
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickChip('Hôm nay', 0),
                    const SizedBox(width: 6),
                    _buildQuickChip('Hôm qua', 1),
                    const SizedBox(width: 6),
                    _buildQuickChip('24h qua', 2),
                    const SizedBox(width: 6),
                    _buildQuickChip('7 ngày', 3),
                    const SizedBox(width: 6),
                    _buildQuickChip('Tùy chọn', 4, onTap: onCustomRangePressed),
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
                      const Text(
                        'Ngắt quãng: ',
                        style: TextStyle(fontSize: 11, color: _refMuted),
                      ),
                      _buildGapDropdown(context),
                    ],
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _refPrimaryBlue,
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _refBorder),
      ),
      child: DropdownButton<int>(
        value: currentMinutes,
        isDense: true,
        underline: const SizedBox.shrink(),
        icon: const Icon(
          Icons.arrow_drop_down_rounded,
          size: 18,
          color: _refText,
        ),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: _refText,
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
          const DropdownMenuItem(
            value: -1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 14, color: _refPrimaryBlue),
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

  Widget _buildQuickChip(String label, int index, {VoidCallback? onTap}) {
    final isSelected = presetIndex == index;

    return InkWell(
      onTap: onTap ?? () => onPresetSelected(index),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEBF3FF) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? _refPrimaryBlue : _refBorder,
            width: isSelected ? 1.2 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? _refPrimaryBlue : _refMuted,
          ),
        ),
      ),
    );
  }
}

// ─── TẦNG 2: Hàng Thẻ KPI Chỉ Số Hành Trình ──────────────────────────────────

class _JourneyMetricsRow extends StatelessWidget {
  const _JourneyMetricsRow({required this.state});

  final JourneyHistoryState state;

  @override
  Widget build(BuildContext context) {
    final segmentCount = state.segments.length;
    final samplesSubtitle = segmentCount > 1 ? '($segmentCount đoạn)' : null;

    final metrics = [
      _MetricItemData(
        icon: Icons.route_rounded,
        label: 'Tổng quãng đường',
        value: DeviceFormatters.distance(state.totalDistanceM),
        tintColor: const Color(0xFFEBF3FF),
        iconColor: const Color(0xFF1677FF),
      ),
      _MetricItemData(
        icon: Icons.navigation_rounded,
        label: 'Thời gian di chuyển',
        value: DeviceFormatters.secondsDuration(state.movingDurationS),
        tintColor: const Color(0xFFECFDF5),
        iconColor: const Color(0xFF16A34A),
      ),
      _MetricItemData(
        icon: Icons.pause_circle_rounded,
        label: 'Thời gian dừng',
        value: DeviceFormatters.secondsDuration(state.stoppedDurationS),
        tintColor: const Color(0xFFFFFBEB),
        iconColor: const Color(0xFFD97706),
      ),
      _MetricItemData(
        icon: Icons.speed_rounded,
        label: 'Tốc độ tối đa',
        value: DeviceFormatters.speedMps(state.maxSpeedMps),
        tintColor: const Color(0xFFFEF2F2),
        iconColor: const Color(0xFFEF4444),
      ),
      _MetricItemData(
        icon: Icons.trending_up_rounded,
        label: 'Tốc độ trung bình',
        value: DeviceFormatters.speedMps(state.avgSpeedMps),
        tintColor: const Color(0xFFEEF2FF),
        iconColor: const Color(0xFF6366F1),
      ),
      _MetricItemData(
        icon: Icons.scatter_plot_rounded,
        label: 'Số mẫu GPS',
        value: '${state.validSamples.length}',
        subtitle: samplesSubtitle,
        tintColor: const Color(0xFFECFEFF),
        iconColor: const Color(0xFF0891B2),
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
                color: _refSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _refBorder),
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
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _refMuted,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: _refText,
                                  height: 1.1,
                                ),
                              ),
                            ),
                            if (item.subtitle != null) ...[
                              const SizedBox(width: 4),
                              Text(
                                item.subtitle!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: _refMuted,
                                ),
                              ),
                            ],
                          ],
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

class _MetricItemData {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color tintColor;
  final Color iconColor;

  const _MetricItemData({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    required this.tintColor,
    required this.iconColor,
  });
}

// ─── TẦNG 3.1: Map Card ───────────────────────────────────────────────────────

class _JourneyMapCard extends StatelessWidget {
  const _JourneyMapCard({
    required this.state,
    required this.height,
    required this.onPointSelected,
  });

  final JourneyHistoryState state;
  final double height;
  final ValueChanged<LocationModel?> onPointSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: _refSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _refBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Bản đồ chính
          _DeviceJourneyMapView(state: state, onPointSelected: onPointSelected),

          // Popup chi tiết điểm GPS khi bấm chọn
          if (state.selectedPoint != null)
            Positioned(
              top: 12,
              right: 12,
              child: PointInfoPopup(
                point: state.selectedPoint!,
                onClose: () => onPointSelected(null),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── TẦNG 3.2: Playback Card (Thanh điều khiển Replay) ────────────────────────

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

    final speedStr = state.currentSpeedMps != null
        ? '${(state.currentSpeedMps! * 3.6).toStringAsFixed(1)} km/h'
        : '0.0 km/h';

    final statusLabel = state.isCompleted
        ? 'Kết thúc'
        : (state.isPlaying
              ? 'Đang di chuyển ($speedStr)'
              : (state.isPaused ? 'Tạm dừng ($speedStr)' : 'Sẵn sàng'));

    final statusColor = state.isCompleted
        ? const Color(0xFFEF4444)
        : (state.isPlaying ? const Color(0xFF16A34A) : _refMuted);

    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 680;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 16,
        vertical: isCompact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: _refSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _refBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isCompact) ...[
            // ── DESKTOP LAYOUT: 1 Row with Left, Center, Right ──
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
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _refText,
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

                // CENTER: Play / Pause / Step buttons (60s & 30s)
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
                    // Primary circular play button
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: hasSamples
                            ? _refPrimaryBlue
                            : Colors.grey.shade300,
                        shape: BoxShape.circle,
                        boxShadow: hasSamples
                            ? [
                                BoxShadow(
                                  color: _refPrimaryBlue.withValues(alpha: 0.3),
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
                          color: Colors.white,
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

                // RIGHT: Tốc độ + Toggle Theo dõi xe
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dropdown tốc độ
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _refBorder),
                      ),
                      child: DropdownButton<double>(
                        value: state.playbackSpeed,
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _refText,
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

                    // Toggle Follow Camera
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
                              ? const Color(0xFFEBF3FF)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: state.followCamera
                                ? _refPrimaryBlue
                                : _refBorder,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.my_location_rounded,
                              size: 14,
                              color: state.followCamera
                                  ? _refPrimaryBlue
                                  : _refMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Theo dõi xe',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: state.followCamera
                                    ? _refPrimaryBlue
                                    : _refMuted,
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
            // Hàng 1 (Mobile): Thời gian & Trạng thái (Trái) + Tốc độ & Theo dõi (Phải)
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
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _refText,
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
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _refBorder),
                      ),
                      child: DropdownButton<double>(
                        value: state.playbackSpeed,
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _refText,
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
                              ? const Color(0xFFEBF3FF)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: state.followCamera
                                ? _refPrimaryBlue
                                : _refBorder,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.my_location_rounded,
                              size: 13,
                              color: state.followCamera
                                  ? _refPrimaryBlue
                                  : _refMuted,
                            ),
                            if (width >= 360) ...[
                              const SizedBox(width: 3),
                              Text(
                                'Theo dõi',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: state.followCamera
                                      ? _refPrimaryBlue
                                      : _refMuted,
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
            // Hàng 2 (Mobile): Cụm nút phát / tua / chuyển bước (Căn giữa)
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
                    color: hasSamples ? _refPrimaryBlue : Colors.grey.shade300,
                    shape: BoxShape.circle,
                    boxShadow: hasSamples
                        ? [
                            BoxShadow(
                              color: _refPrimaryBlue.withValues(alpha: 0.3),
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
                      color: Colors.white,
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

          // ── HÀNG CUỐI: Timeline Slider ────────────────────────
          Row(
            children: [
              Text(
                startTimeStr,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: _refMuted,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.5,
                    activeTrackColor: _refPrimaryBlue,
                    inactiveTrackColor: const Color(0xFFE2E8F0),
                    thumbColor: _refPrimaryBlue,
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
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: _refMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── TẦNG 3.3: Current Information Panel (Dữ liệu mốc hiện tại) ───────────────

class _JourneyCurrentInfoCard extends StatelessWidget {
  const _JourneyCurrentInfoCard({required this.state});

  final JourneyHistoryState state;

  @override
  Widget build(BuildContext context) {
    final sample =
        (state.currentSampleIndex >= 0 &&
            state.currentSampleIndex < state.validSamples.length)
        ? state.validSamples[state.currentSampleIndex]
        : (state.validSamples.isNotEmpty ? state.validSamples.first : null);

    final latStr = state.currentPosition != null
        ? state.currentPosition!.latitude.toStringAsFixed(6)
        : (sample != null ? sample.latitude.toStringAsFixed(6) : '--');
    final lngStr = state.currentPosition != null
        ? state.currentPosition!.longitude.toStringAsFixed(6)
        : (sample != null ? sample.longitude.toStringAsFixed(6) : '--');

    final altStr = sample?.altitudeM != null
        ? '${sample!.altitudeM!.toStringAsFixed(1)} m'
        : '--';
    final speedStr = DeviceFormatters.speedMps(state.currentSpeedMps);
    final headingStr = DeviceFormatters.heading(state.currentHeadingDeg);
    final isMoving = (state.currentSpeedMps ?? 0) >= 0.5;

    final timeStr = state.currentReplayTime != null
        ? DateFormat(
            'dd/MM/yyyy HH:mm:ss',
          ).format(state.currentReplayTime!.toLocal())
        : '--';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _refSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _refBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 780;

          if (isWide) {
            return Row(
              children: [
                // 1. Vị trí hiện tại
                Expanded(
                  flex: 36,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Vị trí hiện tại',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _refMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$latStr, $lngStr',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _refText,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Độ cao: $altStr  ·  Độ chính xác GPS: ±4 m',
                        style: const TextStyle(fontSize: 10, color: _refMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  height: 34,
                  child: VerticalDivider(width: 20, color: _refBorder),
                ),

                // 2. Tốc độ
                Expanded(
                  flex: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Tốc độ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _refMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        speedStr,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: _refText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  height: 34,
                  child: VerticalDivider(width: 20, color: _refBorder),
                ),

                // 3. Hướng
                Expanded(
                  flex: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Hướng',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _refMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        headingStr,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _refText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  height: 34,
                  child: VerticalDivider(width: 20, color: _refBorder),
                ),

                // 4. Trạng thái
                Expanded(
                  flex: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Trạng thái',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _refMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle_rounded,
                            size: 7,
                            color: isMoving
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFD97706),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isMoving ? 'Đang di chuyển' : 'Đang dừng',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isMoving
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFD97706),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  height: 34,
                  child: VerticalDivider(width: 20, color: _refBorder),
                ),

                // 5. Thời điểm
                Expanded(
                  flex: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Thời điểm',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _refMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _refText,
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
                  const Text(
                    'Vị trí hiện tại',
                    style: TextStyle(fontSize: 11, color: _refMuted),
                  ),
                  Text(
                    '$latStr, $lngStr · Độ cao: $altStr',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tốc độ',
                    style: TextStyle(fontSize: 11, color: _refMuted),
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
                  const Text(
                    'Hướng',
                    style: TextStyle(fontSize: 11, color: _refMuted),
                  ),
                  Text(
                    headingStr,
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
                  const Text(
                    'Trạng thái',
                    style: TextStyle(fontSize: 11, color: _refMuted),
                  ),
                  Text(
                    isMoving ? 'Đang di chuyển' : 'Đang dừng',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isMoving
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFD97706),
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

// ─── TẦNG 3.4: Right Timeline Card (Lịch trình chi tiết) ─────────────────────

class _JourneyTimelineCard extends StatelessWidget {
  const _JourneyTimelineCard({
    required this.state,
    required this.height,
    required this.onSelectSample,
  });

  final JourneyHistoryState state;
  final double height;
  final ValueChanged<LocationModel> onSelectSample;

  @override
  Widget build(BuildContext context) {
    final samples = state.validSamples;
    final timeFormat = DateFormat('HH:mm:ss');

    return Container(
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _refSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _refBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'Lịch trình chi tiết',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _refText,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEBF3FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${state.segments.length} đoạn',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: _refPrimaryBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${samples.length} mốc thời gian đã ghi nhận',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: _refMuted),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: _refBorder),
          const SizedBox(height: 8),

          // List timeline cuộn độc lập
          Expanded(
            child: samples.isEmpty
                ? const Center(
                    child: Text(
                      'Chưa có dữ liệu lịch trình',
                      style: TextStyle(fontSize: 12, color: _refMuted),
                    ),
                  )
                : ListView.builder(
                    itemCount: samples.length,
                    itemBuilder: (context, index) {
                      final s = samples[index];
                      final isFirst = index == 0;
                      final isLast = index == samples.length - 1;
                      final isStopped = (s.speedMps ?? 0) < 0.5;

                      // Dot color
                      final dotColor = isFirst
                          ? const Color(0xFF16A34A)
                          : (isLast
                                ? const Color(0xFFEF4444)
                                : (isStopped
                                      ? const Color(0xFFD97706)
                                      : const Color(0xFF1677FF)));

                      final titleLabel = isFirst
                          ? 'Bắt đầu'
                          : (isLast
                                ? 'Kết thúc'
                                : (isStopped ? 'Điểm dừng' : 'Di chuyển'));

                      final speedLabel = s.speedMps != null
                          ? '${(s.speedMps! * 3.6).toStringAsFixed(0)} km/h'
                          : '';

                      return InkWell(
                        onTap: () => onSelectSample(s),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Timeline vertical line + dot
                              SizedBox(
                                width: 20,
                                child: Column(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(top: 3),
                                      decoration: BoxDecoration(
                                        color: dotColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: dotColor.withValues(
                                              alpha: 0.3,
                                            ),
                                            blurRadius: 3,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!isLast)
                                      Container(
                                        width: 1.5,
                                        height: 28,
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),

                              // Content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            timeFormat.format(
                                              s.measuredAt.toLocal(),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: _refText,
                                            ),
                                          ),
                                        ),
                                        if (speedLabel.isNotEmpty &&
                                            !isFirst &&
                                            !isLast) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            speedLabel,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: _refMuted,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            titleLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              color: dotColor,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            '${s.latitude.toStringAsFixed(4)}, ${s.longitude.toStringAsFixed(4)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              color: _refMuted,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
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
  final MapController _mapController = MapController();
  bool _mapReady = false;
  double _currentZoom = 14.0;
  bool _isSatellite = false;
  static const LatLng _defaultCenter = LatLng(21.0285, 105.8542);

  @override
  void didUpdateWidget(covariant _DeviceJourneyMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_mapReady) return;

    final oldSamples = oldWidget.state.validSamples;
    final newSamples = widget.state.validSamples;

    if (oldSamples != newSamples && newSamples.isNotEmpty) {
      _fitRouteBounds(newSamples);
    }

    if (widget.state.followCamera && widget.state.currentPosition != null) {
      if (widget.state.isPlaying || widget.state.isCompleted) {
        _mapController.move(widget.state.currentPosition!, _currentZoom);
      }
    }
  }

  void _fitRouteBounds(List<LocationModel> samples) {
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
    final theme = Theme.of(context);
    final state = widget.state;

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
              }
            },
            onPositionChanged: (camera, hasGesture) {
              if (camera.zoom != _currentZoom) {
                setState(() => _currentZoom = camera.zoom);
              }
            },
          ),
          children: [
            // Map Tiles
            TileLayer(
              urlTemplate: MapTileProviders.getUrl(
                _isSatellite ? AppMapType.satellite : AppMapType.standard,
              ),
              userAgentPackageName: 'com.vmonitor.app',
              minZoom: 4,
              maxZoom: 19,
              maxNativeZoom: MapTileProviders.getMaxZoom(
                _isSatellite ? AppMapType.satellite : AppMapType.standard,
              ),
              tileProvider: NetworkTileProvider(silenceExceptions: true),
              errorImage: MemoryImage(TileProvider.transparentImage),
            ),

            // Polyline Layer cho lộ trình
            if (state.segments.isNotEmpty)
              PolylineLayer(
                polylines: HistoryMapLayers.buildPolylines(
                  segments: state.segments,
                  primaryColor: _refPrimaryBlue,
                ),
              ),

            // Mũi tên chỉ hướng di chuyển
            if (state.segments.isNotEmpty)
              MarkerLayer(
                markers: HistoryMapLayers.buildDirectionArrows(
                  segments: state.segments,
                  currentZoom: _currentZoom,
                  arrowColor: const Color(0xFF0F172A),
                ),
              ),

            // Các mốc GPS: Start, End, Waypoints chống chồng chéo Google Maps style (đầy đủ ngày tháng năm)
            if (state.validSamples.isNotEmpty)
              MarkerLayer(
                markers: HistoryMapLayers.buildSamplePoints(
                  validSamples: state.validSamples,
                  onPointSelected: widget.onPointSelected,
                  theme: theme,
                  currentZoom: _currentZoom,
                ),
              ),

            // Replay Device Marker
            if (state.currentPosition != null)
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
                _currentZoom + 1,
              );
            },
            onZoomOut: () {
              if (!_mapReady) return;
              _mapController.move(
                _mapController.camera.center,
                _currentZoom - 1,
              );
            },
            onFitBounds: () {
              if (state.validSamples.isNotEmpty) {
                _fitRouteBounds(state.validSamples);
              }
            },
            onToggleMapType: () => setState(() => _isSatellite = !_isSatellite),
            isSatellite: _isSatellite,
          ),
        ),

        // Trạng thái Loading
        if (state.isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.15),
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

        // Trạng thái Empty / 1 điểm
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
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 12),
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
                      const Text(
                        'Không có dữ liệu vị trí trong khoảng thời gian đã chọn.',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _refText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Hãy chọn khoảng thời gian khác hoặc kiểm tra lại thiết bị.',
                        style: TextStyle(fontSize: 12, color: _refMuted),
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
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _refBorder),
              ),
              child: const Text(
                'Chỉ có 1 mốc vị trí trong khoảng này.',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _refText,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MapZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitBounds;
  final VoidCallback onToggleMapType;
  final bool isSatellite;

  const _MapZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitBounds,
    required this.onToggleMapType,
    required this.isSatellite,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cụm 1: Phóng to, thu nhỏ, vừa toàn bộ lộ trình
        Container(
          decoration: _boxDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 18, color: _refPrimaryBlue),
                tooltip: 'Phóng to',
                onPressed: onZoomIn,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 28, child: Divider(height: 1)),
              IconButton(
                icon: const Icon(Icons.remove_rounded, size: 18, color: _refPrimaryBlue),
                tooltip: 'Thu nhỏ',
                onPressed: onZoomOut,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 28, child: Divider(height: 1)),
              IconButton(
                icon: const Icon(Icons.fit_screen_rounded, size: 16, color: _refPrimaryBlue),
                tooltip: 'Vừa toàn bộ lộ trình',
                onPressed: onFitBounds,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Cụm 2: Chuyển đổi mode bản đồ riêng biệt
        Container(
          decoration: _boxDecoration(),
          child: IconButton(
            icon: Icon(
              isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
              size: 18,
              color: _refPrimaryBlue,
            ),
            tooltip: isSatellite
                ? 'Chuyển sang bản đồ đường phố'
                : 'Chuyển sang bản đồ vệ tinh',
            onPressed: onToggleMapType,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
      ],
    );
  }
}

// ─── Tab 3: Events — Timeline visual ─────────────────────────────────────────

class _EventsTab extends StatefulWidget {
  const _EventsTab({required this.events});
  final List<DeviceEventModel> events;

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  String _selectedCategory = 'all';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allEvents = widget.events;

    // Filter events by selected category
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
          decoration: const BoxDecoration(
            color: _refSurface,
            border: Border(bottom: BorderSide(color: _refBorder, width: 1)),
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
                            color: _refBorder.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.event_note_rounded,
                            size: 28,
                            color: _refMuted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _selectedCategory == 'all'
                              ? 'Chưa có sự kiện nào'
                              : 'Không có sự kiện thuộc danh mục này',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: _refText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Các sự kiện trạng thái và di chuyển sẽ tự động xuất hiện tại đây khi thiết bị hoạt động.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _refMuted,
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
              ? _refPrimaryBlue.withValues(alpha: 0.1)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? _refPrimaryBlue.withValues(alpha: 0.4)
                : const Color(0xFFE2E8F0),
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
                color: isSelected ? _refPrimaryBlue : const Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected ? _refPrimaryBlue : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : const Color(0xFF334155),
                ),
              ),
            ),
          ],
        ),
      ),
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
                      color: const Color(0xFFE2E8F0),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content Card
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _refSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _refBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
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
                            color: _refText,
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
                          color: _refMuted,
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
                        color: _refText.withValues(alpha: 0.8),
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

  Color _eventColor(String type) {
    switch (type.toUpperCase()) {
      case 'ONLINE':
        return const Color(0xFF16A34A);
      case 'OFFLINE':
        return const Color(0xFF64748B);
      case 'MOVING':
      case 'MOVEMENT_STARTED':
        return const Color(0xFF1677FF);
      case 'IDLE':
      case 'MOVEMENT_STOPPED':
        return const Color(0xFFD97706);
      case 'GPS_LOST':
      case 'GEOFENCE_EXIT':
      case 'ERROR':
        return const Color(0xFFDC2626);
      case 'GPS_RESTORED':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF64748B);
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
      onSelected: (value) =>
          _handleShareLocationSelection(context, device, value),
      itemBuilder: (context) => _shareLocationMenuItems(context, device),
      child: Container(
        width: double.infinity,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _refPrimaryBlue,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.share_location_rounded,
              size: 16,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Chia sẻ vị trí',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white,
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

class _ShareLocationCompactButton extends StatelessWidget {
  const _ShareLocationCompactButton({required this.device});

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
          color: _refPrimaryBlue,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.share_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              'Chia sẻ',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
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
          'Vị trí cũ (${DeviceFormatters.dateTime(device.lastSeenAt)})',
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
