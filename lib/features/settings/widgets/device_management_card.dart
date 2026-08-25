import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/device_formatters.dart';
import '../../../data/models/device_model.dart';
import '../../../data/models/mqtt_device_sighting_model.dart';
import '../settings_cubit.dart';

enum _DevicePermissionFilter { all, enabled, disabled }

IconData _deviceTypeIcon(String type) => switch (type) {
  'UAV_CONTROLLER' => Icons.flight_rounded,
  'VEHICLE' => Icons.directions_car_filled_rounded,
  _ => Icons.memory_rounded,
};

class DeviceManagementCard extends StatefulWidget {
  const DeviceManagementCard({
    super.key,
    required this.devices,
    required this.sightings,
    required this.loading,
    required this.operationInProgress,
  });

  final List<DeviceModel> devices;
  final List<MqttDeviceSightingModel> sightings;
  final bool loading;
  final bool operationInProgress;

  @override
  State<DeviceManagementCard> createState() => _DeviceManagementCardState();
}

class _DeviceManagementCardState extends State<DeviceManagementCard>
    with SingleTickerProviderStateMixin {
  static const _pageSize = 30;

  final _searchController = TextEditingController();
  _DevicePermissionFilter _permissionFilter = _DevicePermissionFilter.all;
  late final TabController _tabController;
  int _selectedTabIndex = 0;
  int _registeredVisible = _pageSize;
  int _pendingVisible = _pageSize;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || widget.loading || widget.operationInProgress) return;
      context.read<SettingsCubit>().refreshDeviceManagement();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _resetVisibleCounts() {
    _registeredVisible = _pageSize;
    _pendingVisible = _pageSize;
  }

  List<DeviceModel> get _filteredDevices {
    final query = _searchController.text.trim().toLowerCase();
    return widget.devices
        .where((device) {
          final permissionMatches = switch (_permissionFilter) {
            _DevicePermissionFilter.all => true,
            _DevicePermissionFilter.enabled => device.isEnabled,
            _DevicePermissionFilter.disabled => !device.isEnabled,
          };
          if (!permissionMatches) return false;
          if (query.isEmpty) return true;
          return device.deviceCode.toLowerCase().contains(query) ||
              device.name.toLowerCase().contains(query) ||
              (device.serialNumber?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);
  }

  List<MqttDeviceSightingModel> get _filteredSightings {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.sightings;
    return widget.sightings
        .where(
          (sighting) =>
              sighting.deviceCode.toLowerCase().contains(query) ||
              sighting.lastTopic.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  Future<void> _openDeviceDialog({
    DeviceModel? device,
    MqttDeviceSightingModel? sighting,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !widget.operationInProgress,
      builder: (_) => BlocProvider.value(
        value: context.read<SettingsCubit>(),
        child: _DeviceEditorDialog(device: device, sighting: sighting),
      ),
    );
  }

  Future<void> _setEnabled(DeviceModel device, bool enabled) async {
    if (widget.operationInProgress || device.isEnabled == enabled) return;
    if (!enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Tạm khóa thiết bị?'),
          content: Text(
            'Hệ thống sẽ ngừng nhận telemetry từ ${device.deviceCode}. '
            'Dữ liệu và lịch sử hiện có vẫn được giữ nguyên.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Tạm khóa'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final error = await context.read<SettingsCubit>().updateDevice(device.id, {
      'is_enabled': enabled,
    });
    if (!mounted || error != null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Đã cho phép tiếp nhận telemetry từ ${device.deviceCode}.'
                : 'Đã tạm khóa ${device.deviceCode}.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final enabledCount = widget.devices
        .where((device) => device.isEnabled)
        .length;
    final filteredDevices = _filteredDevices;
    final filteredSightings = _filteredSightings;
    final visibleDevices = filteredDevices.take(_registeredVisible).toList();
    final visibleSightings = filteredSightings.take(_pendingVisible).toList();

    final registeredContent = visibleDevices.isEmpty
        ? const _DeviceEmptyState(
            key: Key('registered-device-empty'),
            icon: Icons.devices_other_outlined,
            title: 'Không có thiết bị phù hợp',
            description: 'Thử đổi từ khóa hoặc bộ lọc quyền nhận dữ liệu.',
          )
        : Column(
            children: [
              for (var index = 0; index < visibleDevices.length; index++) ...[
                _RegisteredDeviceTile(
                  key: Key(
                    'registered-device-${visibleDevices[index].deviceCode}',
                  ),
                  device: visibleDevices[index],
                  operationInProgress: widget.operationInProgress,
                  onEdit: () =>
                      _openDeviceDialog(device: visibleDevices[index]),
                  onEnabledChanged: (value) =>
                      _setEnabled(visibleDevices[index], value),
                ),
                if (index != visibleDevices.length - 1)
                  const SizedBox(height: 10),
              ],
              if (visibleDevices.length < filteredDevices.length) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        setState(() => _registeredVisible += _pageSize),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text(
                      'Hiển thị thêm (${filteredDevices.length - visibleDevices.length})',
                    ),
                  ),
                ),
              ],
            ],
          );
    final pendingContent = visibleSightings.isEmpty
        ? const _DeviceEmptyState(
            key: Key('mqtt-sighting-empty'),
            icon: Icons.verified_outlined,
            title: 'Không có thiết bị chờ xử lý',
            description:
                'Mã lạ sẽ xuất hiện sau khi backend nhận JSON trên topic MQTT đúng định dạng.',
          )
        : Column(
            children: [
              for (var index = 0; index < visibleSightings.length; index++) ...[
                _MqttSightingTile(
                  key: Key(
                    'mqtt-sighting-${visibleSightings[index].deviceCode}',
                  ),
                  sighting: visibleSightings[index],
                  operationInProgress: widget.operationInProgress,
                  onRegister: () =>
                      _openDeviceDialog(sighting: visibleSightings[index]),
                ),
                if (index != visibleSightings.length - 1)
                  const SizedBox(height: 10),
              ],
              if (visibleSightings.length < filteredSightings.length) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        setState(() => _pendingVisible += _pageSize),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text(
                      'Hiển thị thêm (${filteredSightings.length - visibleSightings.length})',
                    ),
                  ),
                ),
              ],
            ],
          );

    return Column(
      key: const Key('device-management-content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DeviceManagementHeader(
          registeredCount: widget.devices.length,
          enabledCount: enabledCount,
          pendingCount: widget.sightings.length,
          loading: widget.loading,
          operationInProgress: widget.operationInProgress,
          onAdd: () => _openDeviceDialog(),
          controls: _DeviceFilterBar(
            controller: _searchController,
            permissionFilter: _permissionFilter,
            totalCount: widget.devices.length,
            enabledCount: enabledCount,
            disabledCount: widget.devices.length - enabledCount,
            showPermissionFilter: _selectedTabIndex == 0,
            onSearchChanged: (_) => setState(_resetVisibleCounts),
            onPermissionChanged: (value) {
              setState(() {
                _permissionFilter = value;
                _resetVisibleCounts();
              });
            },
          ),
        ),
        const SizedBox(height: 12),
        _DeviceTabbedContent(
          controller: _tabController,
          selectedIndex: _selectedTabIndex,
          registeredCount: filteredDevices.length,
          pendingCount: filteredSightings.length,
          registeredContent: registeredContent,
          pendingContent: pendingContent,
          onSelected: (index) {
            if (_selectedTabIndex == index) return;
            setState(() => _selectedTabIndex = index);
          },
        ),
      ],
    );
  }
}

class _DeviceManagementHeader extends StatelessWidget {
  const _DeviceManagementHeader({
    required this.registeredCount,
    required this.enabledCount,
    required this.pendingCount,
    required this.loading,
    required this.operationInProgress,
    required this.onAdd,
    required this.controls,
  });

  final int registeredCount;
  final int enabledCount;
  final int pendingCount;
  final bool loading;
  final bool operationInProgress;
  final VoidCallback onAdd;
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Card(
      key: const Key('device-management-controls'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useCompactMetrics = constraints.maxWidth < 620;
                final metricItems = [
                  _DeviceMetric(
                    compact: useCompactMetrics,
                    icon: Icons.inventory_2_outlined,
                    label: 'Đã đăng ký',
                    value: registeredCount,
                    color: appColors.primary,
                  ),
                  _DeviceMetric(
                    compact: useCompactMetrics,
                    icon: Icons.sensors_rounded,
                    label: 'Được phép',
                    value: enabledCount,
                    color: appColors.successStrong,
                  ),
                  _DeviceMetric(
                    compact: useCompactMetrics,
                    icon: Icons.radar_rounded,
                    label: 'Chờ xử lý',
                    value: pendingCount,
                    color: appColors.warningStrong,
                  ),
                ];
                final metrics = KeyedSubtree(
                  key: const Key('device-compact-metrics'),
                  child: useCompactMetrics
                      ? IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (
                                var index = 0;
                                index < metricItems.length;
                                index++
                              ) ...[
                                Expanded(child: metricItems[index]),
                                if (index != metricItems.length - 1)
                                  const SizedBox(width: 6),
                              ],
                            ],
                          ),
                        )
                      : Wrap(spacing: 8, runSpacing: 8, children: metricItems),
                );
                final addButton = FilledButton.icon(
                  key: const Key('add-device-button'),
                  onPressed: operationInProgress ? null : onAdd,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('Thêm thiết bị'),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (constraints.maxWidth >= 500)
                      Row(
                        children: [
                          Expanded(child: metrics),
                          const SizedBox(width: 12),
                          addButton,
                        ],
                      )
                    else ...[
                      metrics,
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerLeft, child: addButton),
                    ],
                    const SizedBox(height: 12),
                    Divider(height: 1, color: appColors.divider),
                    const SizedBox(height: 12),
                    controls,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceMetric extends StatelessWidget {
  const _DeviceMetric({
    this.compact = false,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final bool compact;
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        decoration: BoxDecoration(
          color: appColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: appColors.borderSoft),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 4),
                Text(
                  value.toString(),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: appColors.textSecondary,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: appColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: appColors.borderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            value.toString(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: appColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceFilterBar extends StatelessWidget {
  const _DeviceFilterBar({
    required this.controller,
    required this.permissionFilter,
    required this.totalCount,
    required this.enabledCount,
    required this.disabledCount,
    required this.showPermissionFilter,
    required this.onSearchChanged,
    required this.onPermissionChanged,
  });

  final TextEditingController controller;
  final _DevicePermissionFilter permissionFilter;
  final int totalCount;
  final int enabledCount;
  final int disabledCount;
  final bool showPermissionFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_DevicePermissionFilter> onPermissionChanged;

  @override
  Widget build(BuildContext context) {
    final search = Semantics(
      textField: true,
      label: 'Tìm kiếm thiết bị',
      child: SizedBox(
        height: 44,
        child: TextField(
          key: const Key('device-search-field'),
          controller: controller,
          onChanged: onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Tìm mã, tên, serial hoặc topic MQTT',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 42,
              minHeight: 42,
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 42,
              minHeight: 42,
            ),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    key: const Key('clear-device-search'),
                    tooltip: 'Xóa tìm kiếm',
                    onPressed: () {
                      controller.clear();
                      onSearchChanged('');
                    },
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(40),
                      maximumSize: const Size.square(40),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
          ),
        ),
      ),
    );
    if (!showPermissionFilter) return search;

    final filter = _DevicePermissionFilterMenu(
      value: permissionFilter,
      totalCount: totalCount,
      enabledCount: enabledCount,
      disabledCount: disabledCount,
      onChanged: onPermissionChanged,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [search, const SizedBox(height: 10), filter],
          );
        }
        return Row(
          children: [
            Expanded(flex: 5, child: search),
            const SizedBox(width: 12),
            Expanded(flex: 4, child: filter),
          ],
        );
      },
    );
  }
}

class _DevicePermissionFilterMenu extends StatelessWidget {
  const _DevicePermissionFilterMenu({
    required this.value,
    required this.totalCount,
    required this.enabledCount,
    required this.disabledCount,
    required this.onChanged,
  });

  final _DevicePermissionFilter value;
  final int totalCount;
  final int enabledCount;
  final int disabledCount;
  final ValueChanged<_DevicePermissionFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final selectedLabel = switch (value) {
      _DevicePermissionFilter.all => 'Tất cả thiết bị ($totalCount)',
      _DevicePermissionFilter.enabled => 'Được phép ($enabledCount)',
      _DevicePermissionFilter.disabled => 'Tạm khóa telemetry ($disabledCount)',
    };

    return SizedBox(
      height: 44,
      child: PopupMenuButton<_DevicePermissionFilter>(
        key: const Key('device-permission-filter'),
        tooltip: 'Lọc thiết bị đã đăng ký theo quyền nhận dữ liệu',
        padding: EdgeInsets.zero,
        style: const ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        initialValue: value,
        onSelected: onChanged,
        itemBuilder: (context) => [
          CheckedPopupMenuItem(
            key: const Key('device-filter-all'),
            value: _DevicePermissionFilter.all,
            checked: value == _DevicePermissionFilter.all,
            child: Text('Tất cả thiết bị ($totalCount)'),
          ),
          CheckedPopupMenuItem(
            key: const Key('device-filter-enabled'),
            value: _DevicePermissionFilter.enabled,
            checked: value == _DevicePermissionFilter.enabled,
            child: Text('Được phép nhận dữ liệu ($enabledCount)'),
          ),
          CheckedPopupMenuItem(
            key: const Key('device-filter-disabled'),
            value: _DevicePermissionFilter.disabled,
            checked: value == _DevicePermissionFilter.disabled,
            child: Text('Tạm khóa telemetry ($disabledCount)'),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: appColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: value == _DevicePermissionFilter.all
                  ? appColors.border
                  : appColors.primary,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.filter_alt_outlined,
                size: 20,
                color: value == _DevicePermissionFilter.all
                    ? appColors.textSecondary
                    : appColors.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      selectedLabel,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.expand_more_rounded,
                size: 20,
                color: appColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceTabbedContent extends StatelessWidget {
  const _DeviceTabbedContent({
    required this.controller,
    required this.selectedIndex,
    required this.registeredCount,
    required this.pendingCount,
    required this.registeredContent,
    required this.pendingContent,
    required this.onSelected,
  });

  final TabController controller;
  final int selectedIndex;
  final int registeredCount;
  final int pendingCount;
  final Widget registeredContent;
  final Widget pendingContent;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Card(
      key: const Key('device-management-tabs'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: appColors.surfaceSubtle,
              border: Border(bottom: BorderSide(color: appColors.borderSoft)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                return TabBar(
                  controller: controller,
                  onTap: onSelected,
                  indicatorColor: appColors.primary,
                  indicatorSize: TabBarIndicatorSize.label,
                  indicatorWeight: 3,
                  dividerColor: AppPalette.transparent,
                  labelColor: appColors.primary,
                  unselectedLabelColor: appColors.textSecondary,
                  labelStyle: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  unselectedLabelStyle: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                  tabs: [
                    Tab(
                      key: const Key('registered-devices-tab'),
                      height: 58,
                      child: Text(
                        '${compact ? 'Đã đăng ký' : 'Thiết bị đã đăng ký'} ($registeredCount)',
                        maxLines: 1,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Tab(
                      key: const Key('pending-devices-tab'),
                      height: 58,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              compact ? 'MQTT chờ' : 'MQTT chờ đăng ký',
                              maxLines: 1,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Container(
                            key: const Key('pending-devices-tab-badge'),
                            constraints: const BoxConstraints(minWidth: 22),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: appColors.primarySoft,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              pendingCount.toString(),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: appColors.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            key: Key(
              selectedIndex == 0
                  ? 'registered-devices-pane'
                  : 'pending-devices-pane',
            ),
            padding: const EdgeInsets.all(14),
            child: selectedIndex == 0 ? registeredContent : pendingContent,
          ),
        ],
      ),
    );
  }
}

class _RegisteredDeviceTile extends StatelessWidget {
  const _RegisteredDeviceTile({
    super.key,
    required this.device,
    required this.operationInProgress,
    required this.onEdit,
    required this.onEnabledChanged,
  });

  final DeviceModel device;
  final bool operationInProgress;
  final VoidCallback onEdit;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final permissionColor = device.isEnabled
        ? appColors.successStrong
        : appColors.dangerStrong;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DeviceAvatar(
              icon: _deviceTypeIcon(device.type),
              foreground: appColors.primary,
              background: appColors.primarySoft,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    softWrap: true,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: appColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    device.deviceCode,
                    softWrap: true,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: appColors.textSecondary,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _CompactLabel(
              icon: Icons.category_outlined,
              label: DeviceFormatters.deviceTypeLabel(device.type),
            ),
            _CompactLabel(
              icon: device.isOnline
                  ? Icons.wifi_rounded
                  : Icons.wifi_off_rounded,
              label: device.isOnline ? 'Trực tuyến' : 'Ngoại tuyến',
              foreground: device.isOnline
                  ? appColors.successStrong
                  : appColors.offline,
              background: device.isOnline
                  ? appColors.successSoft
                  : appColors.surfaceMuted,
            ),
            if (device.lastSeenAt != null)
              _CompactLabel(
                icon: Icons.schedule_rounded,
                label:
                    'Nhận dữ liệu ${DeviceFormatters.relativeTime(device.lastSeenAt)}',
              ),
          ],
        ),
      ],
    );
    Widget buildActions({required bool showPermissionLabel}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showPermissionLabel) ...[
            Text(
              device.isEnabled ? 'Quyền nhận: Bật' : 'Quyền nhận: Tắt',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: permissionColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
          ],
          _PermissionBadge(enabled: device.isEnabled),
          const SizedBox(width: 6),
          Tooltip(
            message: device.isEnabled
                ? 'Tạm khóa quyền nhận telemetry'
                : 'Cho phép nhận telemetry',
            child: Switch.adaptive(
              key: Key('device-enabled-${device.deviceCode}'),
              value: device.isEnabled,
              onChanged: operationInProgress ? null : onEnabledChanged,
            ),
          ),
          IconButton.filledTonal(
            key: Key('edit-device-${device.deviceCode}'),
            tooltip: 'Chỉnh sửa ${device.deviceCode}',
            onPressed: operationInProgress ? null : onEdit,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: appColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: appColors.borderSoft),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(padding: const EdgeInsets.all(14), child: details),
                Divider(height: 1, color: appColors.divider),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 7, 9, 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          device.isEnabled
                              ? 'Quyền nhận: Bật'
                              : 'Quyền nhận: Tắt',
                          softWrap: true,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: permissionColor,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      buildActions(showPermissionLabel: false),
                    ],
                  ),
                ),
              ],
            );
          }
          return Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: 12),
                buildActions(showPermissionLabel: true),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DeviceAvatar extends StatelessWidget {
  const _DeviceAvatar({
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 21, color: foreground),
    );
  }
}

class _MqttSightingTile extends StatelessWidget {
  const _MqttSightingTile({
    super.key,
    required this.sighting,
    required this.operationInProgress,
    required this.onRegister,
  });

  final MqttDeviceSightingModel sighting;
  final bool operationInProgress;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DeviceAvatar(
              icon: Icons.radar_rounded,
              foreground: appColors.warningStrong,
              background: appColors.warningSoft,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sighting.deviceCode,
                    softWrap: true,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: appColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: appColors.warningSoft,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: appColors.warningStrong.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      'Chưa được cấp quyền nhận dữ liệu',
                      softWrap: true,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: appColors.warningStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CompactLabel(
              icon: Icons.mark_email_unread_outlined,
              label: '${sighting.messageCount} gói đã ghi nhận',
            ),
            _CompactLabel(
              icon: Icons.history_rounded,
              label:
                  'Phát hiện ${DeviceFormatters.relativeTime(sighting.firstSeenAt)}',
            ),
            _CompactLabel(
              icon: Icons.schedule_rounded,
              label:
                  'Gần nhất ${DeviceFormatters.relativeTime(sighting.lastSeenAt)}',
            ),
          ],
        ),
        const SizedBox(height: 11),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: appColors.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: appColors.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOPIC GẦN NHẤT',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: appColors.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sighting.lastTopic,
                softWrap: true,
                overflow: TextOverflow.visible,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: appColors.textSecondary,
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final action = FilledButton.tonalIcon(
      key: Key('register-device-${sighting.deviceCode}'),
      onPressed: operationInProgress ? null : onRegister,
      icon: const Icon(Icons.add_task_rounded),
      label: const Text('Kiểm tra và đăng ký'),
    );

    return Container(
      decoration: BoxDecoration(
        color: appColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: appColors.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 14, 14, 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [information, const SizedBox(height: 12), action],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: information),
                    const SizedBox(width: 14),
                    action,
                  ],
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: appColors.warningStrong),
          ),
        ],
      ),
    );
  }
}

class _CompactLabel extends StatelessWidget {
  const _CompactLabel({
    required this.icon,
    required this.label,
    this.foreground,
    this.background,
  });

  final IconData icon;
  final String label;
  final Color? foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final contentColor = foreground ?? appColors.textSecondary;
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background ?? appColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: contentColor),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              softWrap: true,
              overflow: TextOverflow.visible,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: contentColor,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionBadge extends StatelessWidget {
  const _PermissionBadge({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final color = enabled ? appColors.successStrong : appColors.dangerStrong;
    return Tooltip(
      message: enabled ? 'Được phép nhận telemetry' : 'Đang tạm khóa telemetry',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(
          enabled ? Icons.check_rounded : Icons.block_rounded,
          size: 16,
          color: color,
        ),
      ),
    );
  }
}

class _DeviceEmptyState extends StatelessWidget {
  const _DeviceEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: appColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: appColors.borderSoft),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: appColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: appColors.primary),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: appColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceEditorDialog extends StatefulWidget {
  const _DeviceEditorDialog({this.device, this.sighting});

  final DeviceModel? device;
  final MqttDeviceSightingModel? sighting;

  @override
  State<_DeviceEditorDialog> createState() => _DeviceEditorDialogState();
}

class _DeviceEditorDialogState extends State<_DeviceEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _serialController;
  late final TextEditingController _manufacturerController;
  late final TextEditingController _modelController;
  late final TextEditingController _firmwareController;
  late String _type;
  late bool _isEnabled;
  bool _saving = false;

  bool get _isEditing => widget.device != null;

  @override
  void initState() {
    super.initState();
    final device = widget.device;
    final discoveredCode = widget.sighting?.deviceCode ?? '';
    _codeController = TextEditingController(
      text: device?.deviceCode ?? discoveredCode,
    );
    _nameController = TextEditingController(
      text: device?.name ?? discoveredCode,
    );
    _serialController = TextEditingController(text: device?.serialNumber ?? '');
    _manufacturerController = TextEditingController(
      text: device?.manufacturer ?? '',
    );
    _modelController = TextEditingController(text: device?.model ?? '');
    _firmwareController = TextEditingController(
      text: device?.firmwareVersion ?? '',
    );
    _type = device?.type ?? 'OTHER';
    _isEnabled = device?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _serialController.dispose();
    _manufacturerController.dispose();
    _modelController.dispose();
    _firmwareController.dispose();
    super.dispose();
  }

  String? _requiredText(String? value, String label) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return '$label không được để trống.';
    if (label == 'Mã thiết bị' && normalized.contains('/')) {
      return 'Mã thiết bị không được chứa dấu /.';
    }
    return null;
  }

  String? _optionalValue(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      'device_code': _codeController.text.trim(),
      'name': _nameController.text.trim(),
      'device_type': _type,
      'serial_number': _optionalValue(_serialController),
      'manufacturer': _optionalValue(_manufacturerController),
      'model': _optionalValue(_modelController),
      'firmware_version': _optionalValue(_firmwareController),
      'is_enabled': _isEnabled,
    };
    final cubit = context.read<SettingsCubit>();
    final error = _isEditing
        ? await cubit.updateDevice(widget.device!.id, payload)
        : await cubit.createDevice(payload);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(_isEditing ? 'Chỉnh sửa thiết bị' : 'Đăng ký thiết bị'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('device-code-field'),
                  controller: _codeController,
                  enabled: !_saving,
                  maxLength: 50,
                  decoration: const InputDecoration(
                    labelText: 'Mã thiết bị',
                    prefixIcon: Icon(Icons.tag_rounded),
                  ),
                  validator: (value) => _requiredText(value, 'Mã thiết bị'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('device-name-field'),
                  controller: _nameController,
                  enabled: !_saving,
                  maxLength: 255,
                  decoration: const InputDecoration(
                    labelText: 'Tên hiển thị',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: (value) => _requiredText(value, 'Tên thiết bị'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: const Key('device-type-field'),
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Loại thiết bị',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'UAV_CONTROLLER',
                      child: Text('Điều khiển UAV'),
                    ),
                    DropdownMenuItem(value: 'VEHICLE', child: Text('Xe')),
                    DropdownMenuItem(
                      value: 'OTHER',
                      child: Text('Thiết bị khác'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _type = value ?? 'OTHER'),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fields = [
                      TextFormField(
                        controller: _serialController,
                        enabled: !_saving,
                        decoration: const InputDecoration(labelText: 'Serial'),
                      ),
                      TextFormField(
                        controller: _manufacturerController,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Nhà sản xuất',
                        ),
                      ),
                      TextFormField(
                        controller: _modelController,
                        enabled: !_saving,
                        decoration: const InputDecoration(labelText: 'Model'),
                      ),
                      TextFormField(
                        controller: _firmwareController,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Firmware',
                        ),
                      ),
                    ];
                    if (constraints.maxWidth < 480) {
                      return Column(
                        children: [
                          for (
                            var index = 0;
                            index < fields.length;
                            index++
                          ) ...[
                            fields[index],
                            if (index != fields.length - 1)
                              const SizedBox(height: 10),
                          ],
                        ],
                      );
                    }
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final field in fields)
                          SizedBox(
                            width: (constraints.maxWidth - 10) / 2,
                            child: field,
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                Material(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: SwitchListTile.adaptive(
                    key: const Key('device-enabled-field'),
                    value: _isEnabled,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _isEnabled = value),
                    title: const Text('Cho phép nhận telemetry'),
                    subtitle: const Text(
                      'Có thể thay đổi sau mà không làm mất dữ liệu lịch sử.',
                    ),
                    secondary: Icon(
                      _isEnabled
                          ? Icons.check_circle_outline_rounded
                          : Icons.block_rounded,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          key: const Key('save-device-button'),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isEditing ? 'Lưu thay đổi' : 'Đăng ký'),
        ),
      ],
    );
  }
}
