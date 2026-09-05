// Giao diện quản lý thiết bị dành cho ADMIN: tách thiết bị đã đăng ký và MQTT chờ duyệt,
// hỗ trợ tìm kiếm/lọc, chế độ gọn/chi tiết, thêm/sửa và bật/tạm khóa nhận dữ liệu.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/device_formatters.dart';
import '../../../data/models/device_model.dart';
import '../../../data/models/mqtt_device_sighting_model.dart';
import '../../../domain/entities/device_status_resolver.dart';
import '../settings_cubit.dart';

// Bộ lọc chỉ áp dụng cho tab thiết bị đã đăng ký; tab chờ duyệt chưa có quyền nhận dữ liệu.
enum _DevicePermissionFilter { all, enabled, disabled }

// Chế độ gọn ưu tiên quét danh sách; chế độ chi tiết mở thêm metadata vận hành.
enum _DeviceViewMode { compact, detailed }

// Ánh xạ loại thiết bị từ API sang biểu tượng nhận diện, không dùng để suy luận trạng thái.
IconData _deviceTypeIcon(String type) => switch (type) {
  'UAV_CONTROLLER' => Icons.flight_rounded,
  'VEHICLE' => Icons.directions_car_filled_rounded,
  _ => Icons.memory_rounded,
};

// Khối nội dung chính của mục Quản lý thiết bị. Danh sách đã đăng ký và danh sách
// MQTT chờ duyệt được truyền từ SettingsState; widget chỉ lọc và trình bày dữ liệu đó.
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
  // Mỗi lần chỉ dựng thêm 30 dòng để danh sách lớn không tạo toàn bộ widget cùng lúc.
  static const _pageSize = 30;

  // State cục bộ chỉ điều khiển cách xem: từ khóa, bộ lọc, tab, độ chi tiết và số
  // dòng đang hiện. Dữ liệu thiết bị thật vẫn do SettingsCubit quản lý.
  final _searchController = TextEditingController();
  _DevicePermissionFilter _permissionFilter = _DevicePermissionFilter.all;
  _DeviceViewMode _viewMode = _DeviceViewMode.compact;
  late final TabController _tabController;
  int _selectedTabIndex = 0;
  int _registeredVisible = _pageSize;
  int _pendingVisible = _pageSize;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Hai tab dùng chung một controller để thanh tab và pane nội dung giữ cùng index.
    _tabController = TabController(length: 2, vsync: this);
    // Làm mới nền theo chu kỳ để tab chờ duyệt nhận mã MQTT mới mà không che danh
    // sách hiện tại bằng loading. Cubit tự chặn khi một thao tác ghi đang chạy.
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      // Không đọc context sau dispose và không refresh chồng lên request đang chạy.
      if (!mounted || widget.loading || widget.operationInProgress) return;
      // Chỉ yêu cầu Cubit làm mới nguồn; widget không tự sửa danh sách cục bộ.
      context.read<SettingsCubit>().refreshDeviceManagement();
    });
  }

  @override
  void dispose() {
    // Hủy timer trước khi dispose controller để callback không dùng context đã đóng.
    _refreshTimer?.cancel();
    // Mỗi controller do state tạo phải được giải phóng cùng vòng đời widget.
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _resetVisibleCounts() {
    // Mỗi lần đổi tìm kiếm/bộ lọc đưa phân trang hiển thị về trang đầu.
    _registeredVisible = _pageSize;
    _pendingVisible = _pageSize;
  }

  List<DeviceModel> get _filteredDevices {
    // Lọc trên snapshot đã tải: quyền nhận dữ liệu trước, sau đó mã/tên/sê-ri.
    final query = _searchController.text.trim().toLowerCase();
    return widget.devices
        .where((device) {
          // Filter permission đọc trực tiếp isEnabled do backend trả về.
          final permissionMatches = switch (_permissionFilter) {
            _DevicePermissionFilter.all => true,
            _DevicePermissionFilter.enabled => device.isEnabled,
            _DevicePermissionFilter.disabled => !device.isEnabled,
          };
          // Loại thiết bị sai quyền trước để không chạy ba phép contains không cần thiết.
          if (!permissionMatches) return false;
          // Từ khóa rỗng giữ toàn bộ bản ghi đã qua lọc quyền.
          if (query.isEmpty) return true;
          // Tìm không phân biệt hoa thường trên ba trường người vận hành dễ nhận diện nhất.
          return device.deviceCode.toLowerCase().contains(query) ||
              device.name.toLowerCase().contains(query) ||
              (device.serialNumber?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);
  }

  List<MqttDeviceSightingModel> get _filteredSightings {
    // Thiết bị chờ chỉ có mã và topic thật do backend tổng hợp, chưa có hồ sơ mô tả.
    final query = _searchController.text.trim().toLowerCase();
    // Không sao chép danh sách khi không tìm kiếm; widget chỉ đọc snapshot đầu vào.
    if (query.isEmpty) return widget.sightings;
    // Sighting chưa có name/serial nên chỉ tìm trong deviceCode và lastTopic.
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
    // Cùng một form phục vụ thêm thủ công, sửa hồ sơ và đăng ký từ sighting.
    // BlocProvider.value giữ đúng SettingsCubit khi dialog nằm ngoài cây route.
    // barrierDismissible bị khóa khi operation đang chạy để tránh đóng form giữa request.
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
    // Tắt nhận dữ liệu cần xác nhận vì ảnh hưởng pipeline telemetry; bật lại được gửi
    // ngay. Cả hai trường hợp đều chờ backend xác nhận trước khi báo thành công.
    // Guard bỏ thao tác lặp và bỏ request không làm thay đổi giá trị hiện tại.
    if (widget.operationInProgress || device.isEnabled == enabled) return;
    // Chỉ nhánh tắt cần xác nhận vì nó làm backend ngừng xử lý telemetry mới.
    if (!enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Tạm ngừng nhận dữ liệu?'),
          content: Text(
            'Hệ thống sẽ ngừng tiếp nhận dữ liệu từ ${device.deviceCode}. '
            'Dữ liệu và lịch sử hiện có vẫn được giữ nguyên.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Tạm ngừng'),
            ),
          ],
        ),
      );
      // null xảy ra khi đóng dialog bằng back; false là nhấn Hủy.
      if (confirmed != true || !mounted) return;
    }

    // PATCH chỉ gửi is_enabled, không ghi đè các trường hồ sơ khác.
    final error = await context.read<SettingsCubit>().updateDevice(device.id, {
      'is_enabled': enabled,
    });
    // Chỉ hiện SnackBar thành công khi widget còn sống và Cubit không trả lỗi.
    if (!mounted || error != null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Đã bật nhận dữ liệu từ ${device.deviceCode}.'
                : 'Đã tạm ngừng nhận dữ liệu từ ${device.deviceCode}.',
          ),
        ),
      );
  }

  Future<void> _deleteDevice(DeviceModel device) async {
    // Xóa là thao tác không thể hoàn tác và kéo theo toàn bộ lịch sử của thiết bị,
    // vì vậy luôn yêu cầu xác nhận rõ đối tượng trước khi gọi backend.
    if (widget.operationInProgress) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final appColors = dialogContext.appColors;
        return AlertDialog(
          title: const Text('Xóa thiết bị?'),
          content: Text(
            'Thiết bị ${device.name} (${device.deviceCode}) sắp bị xóa vĩnh viễn. '
            'Toàn bộ vị trí, hành trình, sự kiện và dữ liệu telemetry đã lưu của '
            'thiết bị này cũng sẽ bị xóa và không thể khôi phục.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton.icon(
              key: Key('confirm-delete-device-${device.deviceCode}'),
              style: FilledButton.styleFrom(
                backgroundColor: appColors.dangerStrong,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Xóa thiết bị'),
            ),
          ],
        );
      },
    );
    // null là đóng bằng back/click ngoài; cả null và false đều không thay đổi dữ liệu.
    if (confirmed != true || !mounted) return;

    final error = await context.read<SettingsCubit>().deleteDevice(device.id);
    if (!mounted || error != null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Đã xóa thiết bị ${device.deviceCode}.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Các số đếm lấy trực tiếp từ SettingsState. `visible*` chỉ là phần được dựng
    // ở lượt hiện tại, không làm thay đổi tổng số hoặc dữ liệu nguồn.
    final enabledCount = widget.devices
        .where((device) => device.isEnabled)
        .length;
    // Hai getter áp dụng cùng từ khóa nhưng quy tắc khác nhau theo nguồn dữ liệu.
    final filteredDevices = _filteredDevices;
    final filteredSightings = _filteredSightings;
    // `take` giới hạn số item dựng trong lần render, không thay đổi danh sách đã lọc.
    final visibleDevices = filteredDevices.take(_registeredVisible).toList();
    final visibleSightings = filteredSightings.take(_pendingVisible).toList();

    // Nội dung tab đã đăng ký: trạng thái rỗng, các thẻ thiết bị và nút tải thêm.
    // Biểu thức chọn đúng một trong hai cây widget nên danh sách rỗng không vẫn dựng item.
    final registeredContent = visibleDevices.isEmpty
        ? const _DeviceEmptyState(
            key: Key('registered-device-empty'),
            icon: Icons.devices_other_outlined,
            title: 'Không có thiết bị phù hợp',
            description: 'Thử đổi từ khóa hoặc bộ lọc trạng thái nhận dữ liệu.',
          )
        : Column(
            children: [
              // Spread thêm khoảng cách giữa các item nhưng không thêm sau item cuối.
              for (var index = 0; index < visibleDevices.length; index++) ...[
                _RegisteredDeviceTile(
                  key: Key(
                    'registered-device-${visibleDevices[index].deviceCode}',
                  ),
                  device: visibleDevices[index],
                  detailed: _viewMode == _DeviceViewMode.detailed,
                  operationInProgress: widget.operationInProgress,
                  onEdit: () =>
                      _openDeviceDialog(device: visibleDevices[index]),
                  onDelete: () => _deleteDevice(visibleDevices[index]),
                  onEnabledChanged: (value) =>
                      _setEnabled(visibleDevices[index], value),
                ),
                if (index != visibleDevices.length - 1)
                  const SizedBox(height: 10),
              ],
              // Nút tải thêm chỉ xuất hiện khi phần visible chưa bao phủ toàn bộ kết quả lọc.
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
    // Tab chờ dùng MqttDeviceSightingModel; nút Đăng ký điền trước device_code nhưng
    // không tự cấp quyền hoạt động cho tới khi backend tạo hồ sơ thành công.
    final pendingContent = visibleSightings.isEmpty
        ? const _DeviceEmptyState(
            key: Key('mqtt-sighting-empty'),
            icon: Icons.verified_outlined,
            title: 'Không có thiết bị chờ xác nhận',
            description:
                'Thiết bị mới sẽ xuất hiện khi hệ thống nhận được tín hiệu hợp lệ.',
          )
        : Column(
            children: [
              // Item sighting chỉ có hành động đăng ký, không có switch quyền hay trạng thái online.
              for (var index = 0; index < visibleSightings.length; index++) ...[
                _MqttSightingTile(
                  key: Key(
                    'mqtt-sighting-${visibleSightings[index].deviceCode}',
                  ),
                  sighting: visibleSightings[index],
                  detailed: _viewMode == _DeviceViewMode.detailed,
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

    // Bố cục dọc gồm card điều khiển gọn và card tab danh sách, dành phần lớn chiều
    // cao màn hình cho các item thiết bị.
    return Column(
      key: const Key('device-management-content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header nhận tổng số nguồn, không nhận số sau lọc để các chỉ số luôn phản ánh toàn hệ thống.
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
            pendingMode: _selectedTabIndex == 1,
            // Mỗi ký tự tìm kiếm rebuild cục bộ và đưa giới hạn visible về trang đầu.
            onSearchChanged: (_) => setState(_resetVisibleCounts),
            onPermissionChanged: (value) {
              setState(() {
                _permissionFilter = value;
                _resetVisibleCounts();
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        // Card thứ hai nhận sẵn hai pane; bản thân nó chỉ hiển thị pane của selectedIndex.
        _DeviceTabbedContent(
          controller: _tabController,
          selectedIndex: _selectedTabIndex,
          registeredCount: filteredDevices.length,
          pendingCount: filteredSightings.length,
          viewMode: _viewMode,
          registeredContent: registeredContent,
          pendingContent: pendingContent,
          onSelected: (index) {
            // Chạm lại tab hiện tại không cần setState/rebuild.
            if (_selectedTabIndex == index) return;
            setState(() => _selectedTabIndex = index);
          },
          // Chế độ xem chỉ là state cục bộ, không phát request cấu hình.
          onViewModeChanged: (value) => setState(() => _viewMode = value),
        ),
      ],
    );
  }
}

// Card đầu trang gom ba chỉ số tổng quan, nút thêm và thanh tìm kiếm/lọc vào một vùng.
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
    // Card này là vùng điều khiển phía trên, tách khỏi card danh sách để cuộn/quét rõ ràng.
    return Card(
      key: const Key('device-management-controls'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thanh 2 px chỉ báo request ban đầu nhưng không thay chiều cao nội dung đáng kể.
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            // LayoutBuilder chuyển chỉ số và nút thêm sang dạng compact khi hẹp,
            // tránh ép chữ hoặc gây overflow trên điện thoại.
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Dưới 600 px, mỗi metric bỏ nền viền và ưu tiên icon+số+nhãn hai dòng.
                final useCompactMetrics = constraints.maxWidth < 600;
                // Ba metric đều lấy số từ SettingsState được truyền qua widget cha.
                final metricItems = [
                  _DeviceMetric(
                    compact: useCompactMetrics,
                    icon: Icons.inventory_2_outlined,
                    label: 'Đã thêm',
                    tooltip: 'Thiết bị đã thêm vào hệ thống',
                    value: registeredCount,
                    color: appColors.primary,
                  ),
                  _DeviceMetric(
                    compact: useCompactMetrics,
                    icon: Icons.sensors_rounded,
                    label: 'Đang bật',
                    tooltip: 'Thiết bị được phép nhận dữ liệu',
                    value: enabledCount,
                    color: appColors.successStrong,
                  ),
                  _DeviceMetric(
                    compact: useCompactMetrics,
                    icon: Icons.radar_rounded,
                    label: 'Chờ xác nhận',
                    tooltip: 'Thiết bị mới đang chờ xác nhận',
                    value: pendingCount,
                    color: appColors.warningStrong,
                  ),
                ];
                final metrics = KeyedSubtree(
                  key: const Key('device-compact-metrics'),
                  // Mobile dùng ba cột bằng nhau; desktop dùng Wrap để co giãn tự nhiên.
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
                                  const SizedBox(width: 2),
                              ],
                            ],
                          ),
                        )
                      : Wrap(spacing: 8, runSpacing: 8, children: metricItems),
                );
                // Nút thêm chuyển từ icon-only có tooltip sang nút icon+text khi đủ rộng.
                final addButton = useCompactMetrics
                    ? Tooltip(
                        message: 'Thêm thiết bị',
                        child: IconButton.filled(
                          key: const Key('add-device-button'),
                          onPressed: operationInProgress ? null : onAdd,
                          style: IconButton.styleFrom(
                            minimumSize: const Size.square(40),
                            maximumSize: const Size.square(40),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.add_rounded, size: 19),
                        ),
                      )
                    : FilledButton.icon(
                        key: const Key('add-device-button'),
                        onPressed: operationInProgress ? null : onAdd,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Thêm thiết bị'),
                      );
                // Hàng metric/nút thêm nằm trên, tìm kiếm/lọc nằm dưới divider.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: metrics),
                        const SizedBox(width: 8),
                        addButton,
                      ],
                    ),
                    const SizedBox(height: 8),
                    Divider(height: 1, color: appColors.divider),
                    const SizedBox(height: 8),
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

// Một chỉ số nhỏ trong header; màu lấy từ AppThemeColors của theme hiện tại.
class _DeviceMetric extends StatelessWidget {
  const _DeviceMetric({
    this.compact = false,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.value,
    required this.color,
  });

  final bool compact;
  final IconData icon;
  final String label;
  final String tooltip;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    // Nhánh compact bỏ container trang trí để dành diện tích ngang cho ba chỉ số.
    if (compact) {
      return Tooltip(
        message: '$tooltip: $value',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 3),
                  Text(
                    value.toString(),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: appColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Nhánh rộng dùng pill độc lập để mỗi chỉ số dễ quét bằng mắt.
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: appColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: appColors.borderSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Text(
              value.toString(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: appColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Thanh điều khiển: ô tìm kiếm luôn hiện, bộ lọc quyền chỉ hiện ở tab đã thêm.
class _DeviceFilterBar extends StatelessWidget {
  const _DeviceFilterBar({
    required this.controller,
    required this.permissionFilter,
    required this.totalCount,
    required this.enabledCount,
    required this.disabledCount,
    required this.showPermissionFilter,
    required this.pendingMode,
    required this.onSearchChanged,
    required this.onPermissionChanged,
  });

  final TextEditingController controller;
  final _DevicePermissionFilter permissionFilter;
  final int totalCount;
  final int enabledCount;
  final int disabledCount;
  final bool showPermissionFilter;
  final bool pendingMode;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_DevicePermissionFilter> onPermissionChanged;

  @override
  Widget build(BuildContext context) {
    // Semantics mô tả đúng ngữ cảnh tab cho trình đọc màn hình; controller thuộc
    // widget cha để cùng một từ khóa áp dụng nhất quán khi chuyển tab.
    final search = Semantics(
      textField: true,
      label: pendingMode
          ? 'Tìm thiết bị đang chờ xác nhận'
          : 'Tìm thiết bị đã thêm',
      child: SizedBox(
        height: 40,
        child: TextField(
          key: const Key('device-search-field'),
          controller: controller,
          onChanged: onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            hintText: pendingMode
                ? 'Tìm theo mã hoặc kênh dữ liệu'
                : 'Tìm theo mã, tên hoặc số sê-ri',
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 38,
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 38,
            ),
            suffixIcon: controller.text.isEmpty
                // Không giữ chỗ nút xóa khi chưa có từ khóa để ô tìm kiếm rộng hơn.
                ? null
                : IconButton(
                    key: const Key('clear-device-search'),
                    tooltip: 'Xóa tìm kiếm',
                    onPressed: () {
                      // Xóa controller và báo widget cha để danh sách được lọc lại ngay.
                      controller.clear();
                      onSearchChanged('');
                    },
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(38),
                      maximumSize: const Size.square(38),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
          ),
        ),
      ),
    );
    // Tab chờ không có is_enabled nên chỉ cần ô tìm kiếm.
    if (!showPermissionFilter) return search;

    // Tab đã thêm ghép tìm kiếm và bộ lọc trên một hàng; bộ lọc tự rút gọn khi hẹp.
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactFilter = constraints.maxWidth < 520;
        final filter = _DevicePermissionFilterMenu(
          value: permissionFilter,
          totalCount: totalCount,
          enabledCount: enabledCount,
          disabledCount: disabledCount,
          compact: compactFilter,
          onChanged: onPermissionChanged,
        );
        return Row(
          children: [
            Expanded(flex: 5, child: search),
            const SizedBox(width: 8),
            if (compactFilter) filter else Expanded(flex: 4, child: filter),
          ],
        );
      },
    );
  }
}

// Popup lọc trạng thái nhận dữ liệu; số lượng lấy từ danh sách thật đã tải.
class _DevicePermissionFilterMenu extends StatelessWidget {
  const _DevicePermissionFilterMenu({
    required this.value,
    required this.totalCount,
    required this.enabledCount,
    required this.disabledCount,
    required this.compact,
    required this.onChanged,
  });

  final _DevicePermissionFilter value;
  final int totalCount;
  final int enabledCount;
  final int disabledCount;
  final bool compact;
  final ValueChanged<_DevicePermissionFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    // Nhãn nút phản ánh cả lựa chọn và số lượng thật tương ứng.
    final selectedLabel = switch (value) {
      _DevicePermissionFilter.all => 'Tất cả ($totalCount)',
      _DevicePermissionFilter.enabled => 'Đang bật ($enabledCount)',
      _DevicePermissionFilter.disabled => 'Tạm ngừng ($disabledCount)',
    };

    // Ở dạng compact, nút chỉ rộng 40 px và tooltip vẫn giữ nhãn đầy đủ.
    return SizedBox(
      width: compact ? 40 : null,
      height: 40,
      child: PopupMenuButton<_DevicePermissionFilter>(
        key: const Key('device-permission-filter'),
        tooltip: 'Lọc trạng thái nhận dữ liệu: $selectedLabel',
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
            child: Text('Tất cả ($totalCount)'),
          ),
          CheckedPopupMenuItem(
            key: const Key('device-filter-enabled'),
            value: _DevicePermissionFilter.enabled,
            checked: value == _DevicePermissionFilter.enabled,
            child: Text('Đang bật nhận dữ liệu ($enabledCount)'),
          ),
          CheckedPopupMenuItem(
            key: const Key('device-filter-disabled'),
            value: _DevicePermissionFilter.disabled,
            checked: value == _DevicePermissionFilter.disabled,
            child: Text('Tạm ngừng nhận dữ liệu ($disabledCount)'),
          ),
        ],
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 11,
            vertical: 7,
          ),
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.filter_alt_outlined,
                size: 19,
                color: value == _DevicePermissionFilter.all
                    ? appColors.textSecondary
                    : appColors.primary,
              ),
              if (!compact) ...[
                // Text và mũi tên chỉ xuất hiện ở chiều rộng đủ lớn; icon lọc luôn hiện.
                const SizedBox(width: 8),
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
                const SizedBox(width: 6),
                Icon(
                  Icons.expand_more_rounded,
                  size: 19,
                  color: appColors.textSecondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Card danh sách tách hai nguồn dữ liệu thành tab Đã thêm và Chờ xác nhận; thanh tab
// đồng thời chứa lựa chọn Gọn/Chi tiết áp dụng cho item ở cả hai tab.
class _DeviceTabbedContent extends StatelessWidget {
  const _DeviceTabbedContent({
    required this.controller,
    required this.selectedIndex,
    required this.registeredCount,
    required this.pendingCount,
    required this.viewMode,
    required this.registeredContent,
    required this.pendingContent,
    required this.onSelected,
    required this.onViewModeChanged,
  });

  final TabController controller;
  final int selectedIndex;
  final int registeredCount;
  final int pendingCount;
  final _DeviceViewMode viewMode;
  final Widget registeredContent;
  final Widget pendingContent;
  final ValueChanged<int> onSelected;
  final ValueChanged<_DeviceViewMode> onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Card(
      key: const Key('device-management-tabs'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thanh trên cao cố định 44 px chứa tab co giãn và menu chế độ xem.
          Container(
            decoration: BoxDecoration(
              color: appColors.surfaceSubtle,
              border: Border(bottom: BorderSide(color: appColors.borderSoft)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Chỉ rút ngắn nhãn tab Chờ xác nhận; badge số lượng vẫn được giữ.
                final compactTabs = constraints.maxWidth < 430;
                return SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Expanded(
                        // Expanded cho TabBar dùng toàn bộ phần còn lại trước menu chế độ xem.
                        child: TabBar(
                          controller: controller,
                          onTap: onSelected,
                          indicatorColor: appColors.primary,
                          indicatorSize: TabBarIndicatorSize.label,
                          indicatorWeight: 2,
                          dividerColor: AppPalette.transparent,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          labelColor: appColors.primary,
                          unselectedLabelColor: appColors.textSecondary,
                          labelStyle: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                          unselectedLabelStyle: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          tabs: [
                            Tab(
                              key: const Key('registered-devices-tab'),
                              height: 44,
                              child: _DeviceTabLabel(
                                label: 'Đã thêm',
                                count: registeredCount,
                              ),
                            ),
                            Tab(
                              key: const Key('pending-devices-tab'),
                              height: 44,
                              child: _DeviceTabLabel(
                                label: compactTabs ? 'Chờ' : 'Chờ xác nhận',
                                count: pendingCount,
                                badgeKey: const Key(
                                  'pending-devices-tab-badge',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Divider dọc phân tách điều hướng tab và tùy chọn mật độ item.
                      SizedBox(
                        height: 24,
                        child: VerticalDivider(
                          width: 1,
                          color: appColors.borderSoft,
                        ),
                      ),
                      _DeviceViewModeMenu(
                        value: viewMode,
                        compact: constraints.maxWidth < 620,
                        onChanged: onViewModeChanged,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Chỉ dựng pane đang chọn để không hiển thị hai danh sách cùng lúc và
          // không tiêu tốn chiều cao cho nội dung không được xem.
          Padding(
            // Key theo tab giúp kiểm thử và semantics xác định đúng pane đang hiển thị.
            key: Key(
              selectedIndex == 0
                  ? 'registered-devices-pane'
                  : 'pending-devices-pane',
            ),
            padding: const EdgeInsets.all(10),
            child: selectedIndex == 0 ? registeredContent : pendingContent,
          ),
        ],
      ),
    );
  }
}

// Nhãn tab gồm tên ngắn và badge số bản ghi sau tìm kiếm/bộ lọc.
class _DeviceTabLabel extends StatelessWidget {
  const _DeviceTabLabel({
    required this.label,
    required this.count,
    this.badgeKey,
  });

  final String label;
  final int count;
  final Key? badgeKey;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.fade)),
        const SizedBox(width: 5),
        Container(
          key: badgeKey,
          constraints: const BoxConstraints(minWidth: 20),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: appColors.primarySoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            count.toString(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: appColors.primary,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

// Menu đổi mật độ item; đây là tùy chọn hiển thị cục bộ, không ghi vào backend.
class _DeviceViewModeMenu extends StatelessWidget {
  const _DeviceViewModeMenu({
    required this.value,
    required this.compact,
    required this.onChanged,
  });

  final _DeviceViewMode value;
  final bool compact;
  final ValueChanged<_DeviceViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    // Ba biến này cùng xuất phát từ enum để icon, nhãn và checked không lệch nhau.
    final isCompact = value == _DeviceViewMode.compact;
    final label = isCompact ? 'Gọn' : 'Chi tiết';
    final icon = isCompact
        ? Icons.view_agenda_outlined
        : Icons.view_day_outlined;
    // Popup giữ hai lựa chọn luôn sẵn; child bên dưới chỉ là nút hiển thị lựa chọn hiện tại.
    return PopupMenuButton<_DeviceViewMode>(
      key: const Key('device-view-mode-menu'),
      tooltip: 'Kiểu hiển thị: $label',
      padding: EdgeInsets.zero,
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          key: const Key('device-view-mode-compact'),
          value: _DeviceViewMode.compact,
          checked: isCompact,
          child: const ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.view_agenda_outlined),
            title: Text('Gọn'),
            subtitle: Text('Chỉ hiện thông tin cần thiết'),
          ),
        ),
        CheckedPopupMenuItem(
          key: const Key('device-view-mode-detailed'),
          value: _DeviceViewMode.detailed,
          checked: !isCompact,
          child: const ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.view_day_outlined),
            title: Text('Chi tiết'),
            subtitle: Text('Hiện đầy đủ thông tin thiết bị'),
          ),
        ),
      ],
      child: Container(
        height: 44,
        constraints: BoxConstraints(minWidth: compact ? 76 : 108),
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: appColors.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: appColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 17,
                color: appColors.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Dòng thiết bị đã đăng ký. Hồ sơ lấy từ DeviceModel; nhãn online/GPS/chuyển động
// được DeviceStatusResolver tính từ latest state thật và các ngưỡng runtime.
class _RegisteredDeviceTile extends StatelessWidget {
  const _RegisteredDeviceTile({
    super.key,
    required this.device,
    required this.detailed,
    required this.operationInProgress,
    required this.onEdit,
    required this.onDelete,
    required this.onEnabledChanged,
  });

  final DeviceModel device;
  final bool detailed;
  final bool operationInProgress;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    // Resolver thống nhất cùng logic với dashboard, bản đồ và trang chi tiết;
    // widget không tự đoán trạng thái từ màu hoặc text.
    final status = DeviceStatusResolver.resolve(
      isOnline: device.isOnline,
      lastSeenAt: device.lastSeenAt,
      latestMeasuredAt: device.latestMeasuredAt,
      currentSpeedMps: device.currentSpeedMps,
      baseStatus: device.status,
    );
    final statusColor = status.activity == ActivityStatus.inactive
        // Thứ tự ưu tiên màu: tạm khóa → ngoại tuyến → dữ liệu cũ → chuyển động → dừng → online.
        // Màu chỉ phục vụ trình bày; nhãn status vẫn là thông tin đọc được chính.
        ? appColors.offline
        : status.connectivity == ConnectivityStatus.offline
        ? appColors.offline
        : status.freshness == DataFreshnessStatus.stale
        ? appColors.dangerStrong
        : status.movement == MovementStatus.moving
        ? appColors.primary
        : status.movement == MovementStatus.stopped
        ? appColors.warningStrong
        : appColors.successStrong;
    // displayName ưu tiên tên thân thiện; mã chỉ ẩn khi hai giá trị thực sự giống nhau.
    final displayName = DeviceFormatters.displayName(device);
    final showDeviceCode =
        displayName.trim().toLowerCase() !=
        device.deviceCode.trim().toLowerCase();
    // Cụm trái luôn giữ avatar, tên và mã; thông tin phụ thay đổi theo chế độ xem.
    final identity = Row(
      key: Key('device-identity-${device.deviceCode}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DeviceAvatar(
          icon: _deviceTypeIcon(device.type),
          foreground: appColors.primary,
          background: appColors.primarySoft,
          compact: !detailed,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                softWrap: true,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: appColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              if (detailed && showDeviceCode) ...[
                // Chế độ chi tiết tách mã monospace thành dòng riêng dưới tên.
                const SizedBox(height: 2),
                Text(
                  device.deviceCode,
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: appColors.textSecondary,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
              if (!detailed) ...[
                // Chế độ gọn đặt mã, trạng thái và thời gian trong Wrap ngay dưới tên.
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (showDeviceCode)
                      Text(
                        device.deviceCode,
                        softWrap: true,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: appColors.textSecondary,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    _InlineDeviceMetadata(
                      key: Key('device-connectivity-${device.deviceCode}'),
                      icon: DeviceFormatters.statusIcon(status),
                      label: status.label,
                      color: statusColor,
                    ),
                    if (device.lastSeenAt != null)
                      _InlineDeviceMetadata(
                        icon: Icons.schedule_rounded,
                        label:
                            'Dữ liệu ${DeviceFormatters.relativeTime(device.lastSeenAt)}',
                        color: appColors.textMuted,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
    // Chế độ chi tiết đặt các nhãn trạng thái/type/time trong Wrap để tự xuống dòng.
    final statusLabels = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (detailed)
          _CompactLabel(
            icon: Icons.category_outlined,
            label: DeviceFormatters.deviceTypeLabel(device.type),
          ),
        _CompactLabel(
          icon: DeviceFormatters.statusIcon(status),
          label: status.label,
          foreground: statusColor,
          background: statusColor.withValues(alpha: 0.1),
        ),
        if (device.lastSeenAt != null)
          _CompactLabel(
            icon: Icons.schedule_rounded,
            label:
                '${detailed ? 'Nhận dữ liệu' : 'Dữ liệu'} ${DeviceFormatters.relativeTime(device.lastSeenAt)}',
          ),
      ],
    );
    // Cụm hành động giữ nút sửa/xóa riêng và switch quyền nhận dữ liệu có tooltip rõ nghĩa.
    final editButton = IconButton.filledTonal(
      key: Key('edit-device-${device.deviceCode}'),
      tooltip: 'Chỉnh sửa ${device.deviceCode}',
      onPressed: operationInProgress ? null : onEdit,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(36),
        maximumSize: const Size.square(36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: appColors.primary,
        backgroundColor: appColors.primarySoft,
      ),
      icon: const Icon(Icons.edit_outlined, size: 18),
    );
    final deleteButton = IconButton.filledTonal(
      key: Key('delete-device-${device.deviceCode}'),
      tooltip: 'Xóa ${device.deviceCode}',
      onPressed: operationInProgress ? null : onDelete,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(36),
        maximumSize: const Size.square(36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: appColors.dangerStrong,
        backgroundColor: appColors.dangerSoft,
      ),
      icon: const Icon(Icons.delete_outline_rounded, size: 18),
    );
    final actionButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [editButton, const SizedBox(width: 5), deleteButton],
    );
    Widget permissionControl({required bool showLabel}) {
      // Label được ẩn ở chiều rộng nhỏ nhưng tooltip vẫn mô tả đầy đủ trạng thái và hành động.
      // Switch đọc isEnabled thật và bị disable trong lúc SettingsCubit đang thao tác.
      return Container(
        key: Key('device-permission-control-${device.deviceCode}'),
        padding: EdgeInsets.only(
          left: showLabel ? 9 : 3,
          right: 3,
          top: 2,
          bottom: 2,
        ),
        decoration: BoxDecoration(
          color: appColors.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: appColors.borderSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLabel) ...[
              Text(
                'Nhận dữ liệu',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: appColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Tooltip(
              message: device.isEnabled
                  ? 'Được phép nhận dữ liệu · Nhấn để tạm ngừng'
                  : 'Đang tạm ngừng nhận dữ liệu · Nhấn để bật lại',
              child: Switch.adaptive(
                key: Key('device-enabled-${device.deviceCode}'),
                value: device.isEnabled,
                activeTrackColor: appColors.successStrong,
                inactiveTrackColor: appColors.border,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                onChanged: operationInProgress ? null : onEnabledChanged,
              ),
            ),
          ],
        ),
      );
    }

    // Cột thông tin chi tiết tái sử dụng cho cả nhánh mobile và desktop.
    final detailedInformation = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [identity, const SizedBox(height: 10), statusLabels],
    );

    return Container(
      decoration: BoxDecoration(
        color: appColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: appColors.borderSoft),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Bốn nhánh dưới chỉ đổi cấu trúc trình bày; cùng identity/status/action được tái sử dụng.
          // Gọn + rộng: toàn bộ item nằm một hàng để quét nhanh nhiều thiết bị.
          if (!detailed && constraints.maxWidth >= 700) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 12),
                  permissionControl(showLabel: constraints.maxWidth >= 900),
                  const SizedBox(width: 5),
                  actionButtons,
                ],
              ),
            );
          }
          // Gọn + hẹp: identity ở trên, switch ở cuối để không chen giữa tên/mã.
          if (!detailed) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 8, 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 8),
                      actionButtons,
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 7, 7),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: permissionControl(
                      showLabel: constraints.maxWidth >= 390,
                    ),
                  ),
                ),
              ],
            );
          }
          // Chi tiết + hẹp: tách vùng thông tin và hành động bằng divider.
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(13),
                  child: detailedInformation,
                ),
                Divider(height: 1, color: appColors.divider),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 5, 8, 5),
                  child: Row(
                    children: [
                      Expanded(child: permissionControl(showLabel: true)),
                      const SizedBox(width: 6),
                      actionButtons,
                    ],
                  ),
                ),
              ],
            );
          }
          // Chi tiết + rộng: thông tin và hành động cùng một hàng, không cắt metadata.
          return Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Expanded(child: detailedInformation),
                const SizedBox(width: 12),
                permissionControl(showLabel: true),
                const SizedBox(width: 5),
                actionButtons,
              ],
            ),
          );
        },
      ),
    );
  }
}

// Dải metadata chỉ hiện ở chế độ chi tiết, dùng Wrap để tự xuống dòng khi thiếu rộng.
class _InlineDeviceMetadata extends StatelessWidget {
  const _InlineDeviceMetadata({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              softWrap: true,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Nền biểu tượng thiết bị dùng palette theo theme; kích thước đổi theo mật độ item.
class _DeviceAvatar extends StatelessWidget {
  const _DeviceAvatar({
    required this.icon,
    required this.foreground,
    required this.background,
    this.compact = false,
  });

  final IconData icon;
  final Color foreground;
  final Color background;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 36 : 40,
      height: compact ? 36 : 40,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: compact ? 19 : 21, color: foreground),
    );
  }
}

// Dòng thiết bị chưa đăng ký lấy từ thống kê sighting: mã, topic, lần thấy đầu/cuối
// và số gói. Không hiển thị online vì chưa có DeviceLatestState chính thức.
class _MqttSightingTile extends StatelessWidget {
  const _MqttSightingTile({
    super.key,
    required this.sighting,
    required this.detailed,
    required this.operationInProgress,
    required this.onRegister,
  });

  final MqttDeviceSightingModel sighting;
  final bool detailed;
  final bool operationInProgress;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    // Identity chỉ dùng deviceCode do backend quan sát; không gán tên hoặc loại thiết bị giả.
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DeviceAvatar(
          icon: Icons.radar_rounded,
          foreground: appColors.warningStrong,
          background: appColors.warningSoft,
          compact: !detailed,
        ),
        const SizedBox(width: 10),
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
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detailed ? 'Chưa được thêm vào hệ thống' : 'Chờ xác nhận',
                softWrap: true,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: appColors.warningStrong,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    // Chế độ gọn chỉ giữ số tín hiệu và thời điểm gần nhất để quét danh sách nhanh.
    final compactMetadata = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _CompactLabel(
          icon: Icons.mark_email_unread_outlined,
          label: '${sighting.messageCount} tín hiệu',
        ),
        _CompactLabel(
          icon: Icons.schedule_rounded,
          label:
              'Gần nhất ${DeviceFormatters.relativeTime(sighting.lastSeenAt)}',
        ),
      ],
    );
    // Chế độ chi tiết bổ sung lần đầu và topic MQTT phục vụ chẩn đoán/đăng ký.
    final detailedInformation = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        identity,
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _CompactLabel(
              icon: Icons.mark_email_unread_outlined,
              label: '${sighting.messageCount} tín hiệu đã nhận',
            ),
            _CompactLabel(
              icon: Icons.history_rounded,
              label:
                  'Lần đầu ${DeviceFormatters.relativeTime(sighting.firstSeenAt)}',
            ),
            _CompactLabel(
              icon: Icons.schedule_rounded,
              label:
                  'Gần nhất ${DeviceFormatters.relativeTime(sighting.lastSeenAt)}',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: appColors.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: appColors.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KÊNH NHẬN DỮ LIỆU GẦN NHẤT',
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
    // Nút chỉ mở form điền trước mã; chưa gọi API cho tới khi xác nhận trong dialog.
    final action = FilledButton.tonalIcon(
      key: Key('register-device-${sighting.deviceCode}'),
      onPressed: operationInProgress ? null : onRegister,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.add_task_rounded, size: 18),
      label: const Text('Xem và thêm'),
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
            padding: EdgeInsets.fromLTRB(
              15,
              detailed ? 13 : 9,
              detailed ? 13 : 9,
              detailed ? 13 : 9,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Gọn+rộng: identity, metadata và hành động nằm trên một hàng.
                if (!detailed && constraints.maxWidth >= 700) {
                  return Row(
                    children: [
                      Expanded(flex: 4, child: identity),
                      const SizedBox(width: 12),
                      Expanded(flex: 3, child: compactMetadata),
                      const SizedBox(width: 10),
                      action,
                    ],
                  );
                }
                // Gọn+hẹp: metadata/action chuyển xuống dưới identity.
                if (!detailed) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      identity,
                      const SizedBox(height: 7),
                      // Dưới 480 px nút tách hẳn một hàng để tránh ép metadata.
                      if (constraints.maxWidth < 480) ...[
                        compactMetadata,
                        const SizedBox(height: 7),
                        Align(alignment: Alignment.centerRight, child: action),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(child: compactMetadata),
                            const SizedBox(width: 8),
                            action,
                          ],
                        ),
                    ],
                  );
                }
                // Chi tiết+hẹp xếp nút dưới nội dung; chiều rộng lớn đặt nút bên phải.
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      detailedInformation,
                      const SizedBox(height: 10),
                      action,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: detailedInformation),
                    const SizedBox(width: 12),
                    action,
                  ],
                );
              },
            ),
          ),
          // Dải màu cảnh báo ở cạnh trái giúp phân biệt sighting với thiết bị đã đăng ký.
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

// Nhãn thông tin phụ có icon và một dòng chữ, dùng lại trong các item thiết bị.
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

// Trạng thái rỗng dùng chung cho kết quả lọc không khớp và danh sách chờ chưa có dữ liệu.
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

// Form thêm/sửa/đăng ký thiết bị. Dữ liệu ban đầu đến từ DeviceModel hoặc sighting;
// khi lưu, form gửi trường quản trị tới SettingsCubit rồi chờ backend phản hồi.
class _DeviceEditorDialog extends StatefulWidget {
  const _DeviceEditorDialog({this.device, this.sighting});

  final DeviceModel? device;
  final MqttDeviceSightingModel? sighting;

  @override
  State<_DeviceEditorDialog> createState() => _DeviceEditorDialogState();
}

class _DeviceEditorDialogState extends State<_DeviceEditorDialog> {
  // Controller giữ các trường nhập; `_saving` khóa gửi lặp và `_error` hiển thị
  // thông báo nghiệp vụ do Cubit trả về ngay trong dialog.
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
    // Sửa dùng DeviceModel; đăng ký sighting chỉ có deviceCode; thêm thủ công bắt đầu rỗng.
    final device = widget.device;
    final discoveredCode = widget.sighting?.deviceCode ?? '';
    // Mã sighting được điền sẵn vào cả mã và tên để form có nhãn ban đầu dễ nhận biết.
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
    // Loại/permission lấy từ hồ sơ khi sửa; thiết bị mới mặc định OTHER và được bật.
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
    // Kiểm tra sau trim để chuỗi toàn khoảng trắng không vượt validation.
    if (normalized.isEmpty) return '$label không được để trống.';
    // Dấu `/` sẽ tạo thêm cấp topic MQTT nên bị chặn ngay tại form.
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
    // Validation xử lý lỗi nhập liệu cơ bản; backend/schema/database vẫn là lớp xác
    // thực cuối cùng và có thể trả lỗi để hiển thị tại `_error`.
    // Guard khóa nút khi request cũ chưa xong và dừng nếu bất kỳ field nào không hợp lệ.
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    // Payload chỉ gồm trường hồ sơ được API cho phép; chuỗi tùy chọn rỗng đổi thành null.
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
    // Cùng payload được chuyển tới PATCH khi sửa hoặc POST khi đăng ký mới.
    final error = _isEditing
        ? await cubit.updateDevice(widget.device!.id, payload)
        : await cubit.createDevice(payload);
    // Dialog có thể đã bị route đóng trong lúc request chạy.
    if (!mounted) return;
    // Thành công đóng dialog; SettingsCubit đã tải lại hai danh sách nguồn.
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    // Lỗi mở lại thao tác để người dùng chỉnh dữ liệu và gửi lại.
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    // AlertDialog cho phép phần form cuộn để bàn phím hoặc màn hình thấp không làm
    // nút hành động bị overflow hay cắt khỏi vùng nhìn.
    final colors = Theme.of(context).colorScheme;
    // SizedBox đặt chiều rộng tối đa hợp lý; AlertDialog tự co lại theo màn hình nhỏ.
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
                    // Bốn field phần cứng dùng chung danh sách để đổi giữa một và hai cột.
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
                    // Mobile xếp dọc toàn bộ field, tránh mỗi ô bị quá hẹp hoặc cắt nhãn.
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
                    // Màn rộng dùng Wrap hai cột và tự xuống hàng nếu kích thước thay đổi.
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
                // Khối cuối điều khiển quyền nhận telemetry ban đầu của hồ sơ thiết bị.
                Material(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: SwitchListTile.adaptive(
                    key: const Key('device-enabled-field'),
                    value: _isEnabled,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _isEnabled = value),
                    title: const Text('Cho phép nhận dữ liệu'),
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
