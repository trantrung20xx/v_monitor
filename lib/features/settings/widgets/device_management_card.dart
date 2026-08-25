import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/utils/device_formatters.dart';
import '../../../data/models/device_model.dart';
import '../../../data/models/mqtt_device_sighting_model.dart';
import '../settings_cubit.dart';

enum _DevicePermissionFilter { all, enabled, disabled }

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

class _DeviceManagementCardState extends State<DeviceManagementCard> {
  static const _pageSize = 30;

  final _searchController = TextEditingController();
  _DevicePermissionFilter _permissionFilter = _DevicePermissionFilter.all;
  int _registeredVisible = _pageSize;
  int _pendingVisible = _pageSize;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || widget.loading || widget.operationInProgress) return;
      context.read<SettingsCubit>().refreshMqttDeviceSightings();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
                ? 'Đã cho phép ${device.deviceCode} gửi telemetry.'
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
          onRefresh: () => context.read<SettingsCubit>().loadDeviceManagement(),
        ),
        const SizedBox(height: 16),
        _DeviceFilterBar(
          controller: _searchController,
          permissionFilter: _permissionFilter,
          onSearchChanged: (_) => setState(_resetVisibleCounts),
          onPermissionChanged: (value) {
            setState(() {
              _permissionFilter = value;
              _resetVisibleCounts();
            });
          },
        ),
        const SizedBox(height: 16),
        _DeviceSection(
          title: 'Thiết bị đã đăng ký',
          description:
              'Thiết bị chính thức trong hệ thống; quyền nhận dữ liệu độc lập với trạng thái online.',
          icon: Icons.devices_other_rounded,
          count: filteredDevices.length,
          child: visibleDevices.isEmpty
              ? const _DeviceEmptyState(
                  key: Key('registered-device-empty'),
                  icon: Icons.devices_other_outlined,
                  title: 'Không có thiết bị phù hợp',
                  description:
                      'Thử đổi từ khóa hoặc bộ lọc quyền nhận dữ liệu.',
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < visibleDevices.length;
                      index++
                    ) ...[
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
                      OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _registeredVisible += _pageSize),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(
                          'Hiển thị thêm (${filteredDevices.length - visibleDevices.length})',
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _DeviceSection(
          title: 'Thiết bị MQTT chờ đăng ký',
          description:
              'Mã thiết bị hệ thống đã phát hiện nhưng chưa được phép cập nhật bản đồ.',
          icon: Icons.radar_rounded,
          count: filteredSightings.length,
          child: visibleSightings.isEmpty
              ? const _DeviceEmptyState(
                  key: Key('mqtt-sighting-empty'),
                  icon: Icons.verified_outlined,
                  title: 'Không có thiết bị chờ xử lý',
                  description:
                      'Thiết bị lạ sẽ xuất hiện tại đây sau khi gửi gói MQTT hợp lệ.',
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < visibleSightings.length;
                      index++
                    ) ...[
                      _MqttSightingTile(
                        key: Key(
                          'mqtt-sighting-${visibleSightings[index].deviceCode}',
                        ),
                        sighting: visibleSightings[index],
                        operationInProgress: widget.operationInProgress,
                        onRegister: () => _openDeviceDialog(
                          sighting: visibleSightings[index],
                        ),
                      ),
                      if (index != visibleSightings.length - 1)
                        const SizedBox(height: 10),
                    ],
                    if (visibleSightings.length < filteredSightings.length) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _pendingVisible += _pageSize),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(
                          'Hiển thị thêm (${filteredSightings.length - visibleSightings.length})',
                        ),
                      ),
                    ],
                  ],
                ),
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
    required this.onRefresh,
  });

  final int registeredCount;
  final int enabledCount;
  final int pendingCount;
  final bool loading;
  final bool operationInProgress;
  final VoidCallback onAdd;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final heading = Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.developer_board_rounded,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quản lý thiết bị',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Đăng ký, chỉnh sửa và kiểm soát quyền nhận telemetry.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    IconButton.outlined(
                      key: const Key('refresh-device-management'),
                      tooltip: 'Làm mới danh sách thiết bị',
                      onPressed: loading || operationInProgress
                          ? null
                          : onRefresh,
                      icon: loading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                    FilledButton.icon(
                      key: const Key('add-device-button'),
                      onPressed: operationInProgress ? null : onAdd,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Thêm thiết bị'),
                    ),
                  ],
                );
                if (constraints.maxWidth < 680) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heading,
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerRight, child: actions),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 18),
                    actions,
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _DeviceMetric(
                  icon: Icons.inventory_2_outlined,
                  label: 'Đã đăng ký',
                  value: registeredCount,
                  color: colors.primary,
                ),
                _DeviceMetric(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Đang cho phép',
                  value: enabledCount,
                  color: colors.tertiary,
                ),
                _DeviceMetric(
                  icon: Icons.radar_rounded,
                  label: 'Chờ đăng ký',
                  value: pendingCount,
                  color: colors.secondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceMetric extends StatelessWidget {
  const _DeviceMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 8),
          Text(
            value.toString(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
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
    required this.onSearchChanged,
    required this.onPermissionChanged,
  });

  final TextEditingController controller;
  final _DevicePermissionFilter permissionFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_DevicePermissionFilter> onPermissionChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final search = TextField(
              key: const Key('device-search-field'),
              controller: controller,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Tìm theo mã, tên hoặc serial',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Xóa tìm kiếm',
                        onPressed: () {
                          controller.clear();
                          onSearchChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            );
            final filters = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DeviceFilterChip(
                  label: 'Tất cả',
                  selected: permissionFilter == _DevicePermissionFilter.all,
                  onSelected: () =>
                      onPermissionChanged(_DevicePermissionFilter.all),
                ),
                _DeviceFilterChip(
                  label: 'Cho phép',
                  selected: permissionFilter == _DevicePermissionFilter.enabled,
                  onSelected: () =>
                      onPermissionChanged(_DevicePermissionFilter.enabled),
                ),
                _DeviceFilterChip(
                  label: 'Tạm khóa',
                  selected:
                      permissionFilter == _DevicePermissionFilter.disabled,
                  onSelected: () =>
                      onPermissionChanged(_DevicePermissionFilter.disabled),
                ),
              ],
            );
            if (constraints.maxWidth < 680) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [search, const SizedBox(height: 12), filters],
              );
            }
            return Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 14),
                filters,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DeviceFilterChip extends StatelessWidget {
  const _DeviceFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _DeviceSection extends StatelessWidget {
  const _DeviceSection({
    required this.title,
    required this.description,
    required this.icon,
    required this.count,
    required this.child,
  });

  final String title;
  final String description;
  final IconData icon;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Badge(label: Text(count.toString())),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
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
    final colors = Theme.of(context).colorScheme;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          device.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _CompactLabel(icon: Icons.tag_rounded, label: device.deviceCode),
            _CompactLabel(
              icon: Icons.category_outlined,
              label: DeviceFormatters.deviceTypeLabel(device.type),
            ),
            _CompactLabel(
              icon: device.isOnline
                  ? Icons.wifi_rounded
                  : Icons.wifi_off_rounded,
              label: device.isOnline ? 'Online' : 'Offline',
            ),
          ],
        ),
        if (device.lastSeenAt != null) ...[
          const SizedBox(height: 7),
          Text(
            'Nhận dữ liệu ${DeviceFormatters.relativeTime(device.lastSeenAt)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PermissionBadge(enabled: device.isEnabled),
        const SizedBox(width: 6),
        Switch.adaptive(
          key: Key('device-enabled-${device.deviceCode}'),
          value: device.isEnabled,
          onChanged: operationInProgress ? null : onEnabledChanged,
        ),
        IconButton(
          key: Key('edit-device-${device.deviceCode}'),
          tooltip: 'Chỉnh sửa ${device.deviceCode}',
          onPressed: operationInProgress ? null : onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    );

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  details,
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
      ),
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
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondaryContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final information = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sighting.deviceCode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _CompactLabel(
                      icon: Icons.mark_email_unread_outlined,
                      label: '${sighting.messageCount} gói',
                    ),
                    _CompactLabel(
                      icon: Icons.schedule_rounded,
                      label:
                          'Gần nhất ${DeviceFormatters.relativeTime(sighting.lastSeenAt)}',
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  sighting.lastTopic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            );
            final action = FilledButton.tonalIcon(
              key: Key('register-device-${sighting.deviceCode}'),
              onPressed: operationInProgress ? null : onRegister,
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('Đăng ký'),
            );
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  information,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: information),
                const SizedBox(width: 14),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CompactLabel extends StatelessWidget {
  const _CompactLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 250),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
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
    final colors = Theme.of(context).colorScheme;
    final color = enabled ? colors.tertiary : colors.error;
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
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Icon(icon, size: 34, color: colors.onSurfaceVariant),
          const SizedBox(height: 9),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
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
