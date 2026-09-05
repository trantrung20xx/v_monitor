// Khung trang Cài đặt và các trang con tài khoản, giao diện, phần mềm, người dùng,
// theo dõi và thiết bị. Điều hướng/visibility theo vai trò, dữ liệu do SettingsCubit quản lý.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/config/map_tile_providers.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/widgets/app_menu.dart';
import '../../data/models/user_model.dart';
import '../../data/models/user_settings_model.dart';
import '../auth/auth_cubit.dart';
import '../auth/change_password_dialog.dart';
import 'settings_cubit.dart';
import 'settings_state.dart';
import 'widgets/tracking_settings_card.dart';
import 'widgets/device_management_card.dart';
import 'widgets/user_management_card.dart';

// Mỗi giá trị tương ứng một điểm đến trong menu cài đặt; enum được router dùng để
// mở trực tiếp đúng nội dung mà không tạo trang quản lý thiết bị trùng lặp.
enum SettingsSection {
  overview,
  personal,
  account,
  about,
  tracking,
  devices,
  users,
}

// Vỏ trang Cài đặt nhận section từ route và người dùng đã xác thực từ AuthState.
// Dữ liệu từng section được SettingsCubit tải theo nhu cầu.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.section});

  // Nullable để instance được giữ lại qua hot reload từ phiên bản cũ không
  // làm ứng dụng crash; giá trị thiếu luôn được quy về trang tổng quan.
  final SettingsSection? section;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Hai cờ tránh tải lặp danh sách quản trị khi didChangeDependencies chạy lại.
  bool _usersRequested = false;
  bool _devicesRequested = false;

  SettingsSection get _requestedSection =>
      widget.section ?? SettingsSection.overview;

  @override
  void didChangeDependencies() {
    // Cài đặt cá nhân/hệ thống được khởi tạo cho mọi người dùng. Danh sách tài khoản
    // và thiết bị chỉ yêu cầu khi có quyền ADMIN và section tương ứng cần hiển thị.
    super.didChangeDependencies();
    final settingsCubit = context.read<SettingsCubit>();
    // Chỉ trạng thái initial kích hoạt lần tải cấu hình chung đầu tiên.
    if (settingsCubit.state.status == SettingsLoadStatus.initial) {
      settingsCubit.initialize();
    }
    // Danh sách user chỉ tải khi route đang ở section users và AuthState có quyền ADMIN.
    if (!_usersRequested &&
        _requestedSection == SettingsSection.users &&
        context.read<AuthCubit>().state.hasAdminAccess) {
      _usersRequested = true;
      settingsCubit.loadUsers();
    }
    // Thiết bị đăng ký/sighting chỉ tải khi route thực sự cần màn quản lý thiết bị.
    if (!_devicesRequested &&
        _requestedSection == SettingsSection.devices &&
        context.read<AuthCubit>().state.hasAdminAccess) {
      _devicesRequested = true;
      settingsCubit.loadDeviceManagement();
    }
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    // Route có thể đổi section trên cùng State; nạp dữ liệu quản trị đúng lúc thay vì
    // dựng lại toàn bộ SettingsCubit hoặc tải trước các danh sách lớn.
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.section ?? SettingsSection.overview) != _requestedSection) {
      // Route đổi section cho phép hai danh sách quản trị được yêu cầu lại đúng ngữ cảnh mới.
      _usersRequested = false;
      _devicesRequested = false;
      // Chuyển tới users tải ngay nếu session hiện tại có quyền.
      if (_requestedSection == SettingsSection.users &&
          context.read<AuthCubit>().state.hasAdminAccess) {
        _usersRequested = true;
        context.read<SettingsCubit>().loadUsers();
      }
      // Chuyển tới devices dùng lại cùng SettingsCubit thay vì tạo trang/dữ liệu riêng.
      if (_requestedSection == SettingsSection.devices &&
          context.read<AuthCubit>().state.hasAdminAccess) {
        _devicesRequested = true;
        context.read<SettingsCubit>().loadDeviceManagement();
      }
    }
  }

  Future<void> _reload(bool hasAdminAccess) async {
    // Pull-to-refresh tải lại cấu hình chung, sau đó chỉ tải dữ liệu thuộc section
    // đang xem. Backend vẫn kiểm tra quyền độc lập với biến giao diện này.
    await context.read<SettingsCubit>().initialize();
    // Kiểm tra mounted sau await trước khi đọc context cho request tiếp theo.
    if (_requestedSection == SettingsSection.users &&
        hasAdminAccess &&
        mounted) {
      await context.read<SettingsCubit>().loadUsers();
    }
    // Hai if độc lập vì section chỉ có một giá trị; mỗi nhánh mô tả rõ nguồn cần refresh.
    if (_requestedSection == SettingsSection.devices &&
        hasAdminAccess &&
        mounted) {
      await context.read<SettingsCubit>().loadDeviceManagement();
    }
  }

  @override
  Widget build(BuildContext context) {
    // AuthState cung cấp tài khoản/quyền; SettingsState cung cấp toàn bộ dữ liệu và
    // cờ loading. Widget chỉ chọn section và truyền đúng lát state xuống khối con.
    final authState = context.watch<AuthCubit>().state;
    final user = authState.user;
    final hasAdminAccess = authState.hasAdminAccess;
    // requestedSection đến từ router; visibleSection là section an toàn thực sự được dựng.
    final requestedSection = _requestedSection;
    // Route quản trị bị truy cập trực tiếp bởi user thường được đưa về overview.
    final visibleSection = _isAdminSection(requestedSection) && !hasAdminAccess
        ? SettingsSection.overview
        : requestedSection;
    // Scaffold cung cấp AppBar theo section và vùng body lắng nghe SettingsState.
    return Scaffold(
      appBar: AppBar(
        leading: visibleSection == SettingsSection.overview
            // Overview là cấp gốc nên dùng leading mặc định của shell.
            ? null
            : IconButton(
                tooltip: 'Quay lại Cài đặt',
                onPressed: () => context.goNamed('settings'),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(_sectionTitle(visibleSection)),
        actions: [
          IconButton(
            tooltip: 'Tải lại cài đặt',
            onPressed: () => _reload(hasAdminAccess),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: BlocConsumer<SettingsCubit, SettingsState>(
        // Listener chỉ chạy khi có message mới khác trước, tránh SnackBar lặp trên rebuild.
        listenWhen: (previous, current) =>
            previous.message != current.message && current.message != null,
        listener: (context, state) {
          // Ẩn SnackBar cũ trước để thông báo thao tác mới luôn hiện rõ.
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.message!)));
        },
        builder: (context, state) {
          // Truyền lát state và quyền xuống section view; widget con không tự gọi Auth API.
          return _SettingsSectionView(
            section: visibleSection,
            state: state,
            user: user,
            hasAdminAccess: hasAdminAccess,
            onRefresh: () => _reload(hasAdminAccess),
          );
        },
      ),
    );
  }
}

bool _isAdminSection(SettingsSection section) =>
    // Danh sách section quản trị dùng cho cả điều hướng và chặn hiển thị trực tiếp.
    section == SettingsSection.tracking ||
    section == SettingsSection.devices ||
    section == SettingsSection.users;

String _sectionTitle(SettingsSection section) => switch (section) {
  SettingsSection.overview => 'Cài đặt',
  SettingsSection.personal => 'Giao diện & hiển thị',
  SettingsSection.account => 'Tài khoản & bảo mật',
  SettingsSection.about => 'Thông tin phần mềm',
  SettingsSection.tracking => 'Theo dõi thiết bị',
  SettingsSection.devices => 'Quản lý thiết bị',
  SettingsSection.users => 'Quản lý người dùng',
};

// Khung hiển thị một section: breadcrumb/tiêu đề, thông báo lỗi và nội dung cụ thể.
class _SettingsSectionView extends StatelessWidget {
  const _SettingsSectionView({
    required this.section,
    required this.state,
    required this.user,
    required this.hasAdminAccess,
    required this.onRefresh,
  });

  final SettingsSection section;
  final SettingsState state;
  final UserModel? user;
  final bool hasAdminAccess;
  final RefreshCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    // Nếu route trỏ vào section ADMIN nhưng tài khoản không có quyền, nội dung được
    // thay bằng thông báo an toàn; đây chỉ là UX, backend vẫn là lớp bảo mật thật.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Desktop tăng padding ngoài; mobile giữ 16 px để tối đa vùng nội dung.
        final horizontalPadding = constraints.maxWidth >= 900 ? 32.0 : 16.0;
        // Device cần toàn bộ chiều rộng cho danh sách; user giới hạn 1120; form thường 840.
        final maxWidth = switch (section) {
          SettingsSection.devices => constraints.maxWidth,
          SettingsSection.users => 1120.0,
          _ => 840.0,
        };
        // RefreshIndicator bao ListView luôn scrollable để pull-to-refresh hoạt động cả khi ít nội dung.
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              20,
              horizontalPadding,
              32,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Thanh mảnh cho lần tải cấu hình chung, không thay thế toàn bộ nội dung.
                      if (state.status == SettingsLoadStatus.loading)
                        const LinearProgressIndicator(minHeight: 2),
                      // Banner chỉ xuất hiện ở trạng thái error và dùng message đã chuẩn hóa.
                      if (state.status == SettingsLoadStatus.error) ...[
                        _LoadErrorBanner(message: state.message),
                        const SizedBox(height: 16),
                      ],
                      // Overview dựng menu đích; các section khác dựng đúng nội dung nghiệp vụ.
                      if (section == SettingsSection.overview)
                        _SettingsOverview(hasAdminAccess: hasAdminAccess)
                      else
                        _sectionContent(),
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

  Widget _sectionContent() => switch (section) {
    // Ánh xạ section sang widget hiện có. DeviceManagementCard được tái sử dụng cho
    // cả menu chính Thiết bị và mục Cài đặt, không tạo hai luồng dữ liệu riêng.
    // Mỗi nhánh chỉ nhận những field SettingsState cần cho khối đó.
    SettingsSection.personal => _PersonalSettingsCard(state: state),
    SettingsSection.account => _AccountSettingsCard(
      user: user,
      hasAdminAccess: hasAdminAccess,
      operationInProgress: state.userOperationInProgress,
    ),
    SettingsSection.about => const _SoftwareInformationCard(),
    SettingsSection.tracking => TrackingSettingsCard(
      settings: state.systemSettings,
      saving: state.systemSaving,
    ),
    SettingsSection.devices => DeviceManagementCard(
      devices: state.devices,
      sightings: state.mqttDeviceSightings,
      loading: state.devicesLoading,
      operationInProgress: state.deviceOperationInProgress,
    ),
    SettingsSection.users => UserManagementCard(
      users: state.users,
      loading: state.usersLoading,
      operationInProgress: state.userOperationInProgress,
    ),
    SettingsSection.overview => const SizedBox.shrink(),
  };
}

// Trang tổng quan cài đặt trình bày các điểm đến dạng nhóm thẻ, không chứa form nghiệp vụ.
class _SettingsOverview extends StatelessWidget {
  const _SettingsOverview({required this.hasAdminAccess});

  final bool hasAdminAccess;

  @override
  Widget build(BuildContext context) {
    // Column chia điểm đến thành ba nhóm: cá nhân, quản trị có điều kiện và thông tin.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SettingsGroupTitle(title: 'Cá nhân'),
        const SizedBox(height: 10),
        _SettingsDestinationGrid(
          destinations: const [
            _SettingsDestination(
              keyName: 'settings-section-personal',
              routeName: 'settings-personal',
              title: 'Giao diện & hiển thị',
              description: 'Chủ đề, loại bản đồ và đơn vị tốc độ',
              icon: Icons.palette_outlined,
            ),
            _SettingsDestination(
              keyName: 'settings-section-account',
              routeName: 'settings-account',
              title: 'Tài khoản & bảo mật',
              description: 'Thông tin tài khoản, mật khẩu và đăng xuất',
              icon: Icons.manage_accounts_outlined,
            ),
          ],
        ),
        // Các widget quản trị chỉ được tạo khi AuthState đã xác thực quyền
        // ADMIN; không phải cơ chế ẩn giao diện sau khi widget đã dựng.
        // Spread đồng thời thêm khoảng cách, tiêu đề và grid quản trị.
        if (hasAdminAccess) ...[
          const SizedBox(height: 28),
          const _SettingsGroupTitle(title: 'Quản trị'),
          const SizedBox(height: 10),
          _SettingsDestinationGrid(
            destinations: const [
              _SettingsDestination(
                keyName: 'settings-section-tracking',
                routeName: 'settings-tracking',
                title: 'Theo dõi thiết bị',
                description: 'Ngưỡng ngoại tuyến, chuyển động và hành trình',
                icon: Icons.sensors_rounded,
              ),
              _SettingsDestination(
                keyName: 'settings-section-devices',
                routeName: 'settings-devices',
                title: 'Quản lý thiết bị',
                description: 'Đăng ký, chỉnh sửa và cấp quyền nhận dữ liệu',
                icon: Icons.developer_board_outlined,
              ),
              _SettingsDestination(
                keyName: 'settings-section-users',
                routeName: 'settings-users',
                title: 'Quản lý người dùng',
                description: 'Tài khoản, vai trò và quyền truy cập',
                icon: Icons.admin_panel_settings_outlined,
              ),
            ],
          ),
        ],
        const SizedBox(height: 28),
        const _SettingsGroupTitle(title: 'Thông tin'),
        const SizedBox(height: 10),
        _SettingsDestinationGrid(
          destinations: const [
            _SettingsDestination(
              keyName: 'settings-section-about',
              routeName: 'settings-about',
              title: 'Thông tin phần mềm',
              description: 'Biểu tượng, phiên bản và thông tin ứng dụng',
              icon: Icons.info_outline_rounded,
            ),
          ],
        ),
      ],
    );
  }
}

// Model trình bày nội bộ mô tả icon, tiêu đề, mô tả và section đích của một ô menu.
class _SettingsDestination {
  const _SettingsDestination({
    required this.keyName,
    required this.routeName,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String keyName;
  final String routeName;
  final String title;
  final String description;
  final IconData icon;
}

// Lưới điểm đến tự đổi số cột theo chiều rộng để không cắt chữ trên mobile/desktop.
class _SettingsDestinationGrid extends StatelessWidget {
  const _SettingsDestinationGrid({required this.destinations});

  final List<_SettingsDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Từ 680 px hiển thị hai thẻ mỗi hàng; thấp hơn dùng một cột không cắt chữ.
        final columns = constraints.maxWidth >= 680 ? 2 : 1;
        // GridView không cuộn riêng vì đang nằm trong ListView của section.
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: destinations.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 126,
          ),
          itemBuilder: (context, index) {
            // Mỗi index ánh xạ một model đích bất biến trong danh sách được truyền vào.
            final destination = destinations[index];
            // Card+InkWell tạo vùng bấm toàn thẻ và hiệu ứng Material đúng theme.
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: Key(destination.keyName),
                // Điều hướng theo routeName, router quyết định SettingsSection tương ứng.
                onTap: () => context.pushNamed(destination.routeName),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          destination.icon,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              destination.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              destination.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// Tiêu đề nhỏ phân chia nhóm cá nhân, hệ thống và quản trị trong trang tổng quan.
class _SettingsGroupTitle extends StatelessWidget {
  const _SettingsGroupTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

// Card Giao diện và hiển thị lấy UserSettingsModel từ SettingsState và gửi từng
// lựa chọn theme/bản đồ/đơn vị tốc độ/nội dung nhãn hành trình về SettingsCubit.
class _PersonalSettingsCard extends StatelessWidget {
  const _PersonalSettingsCard({required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    // Các selector dùng dữ liệu đã lưu từ backend; cờ personalSaving khóa thao tác
    // trong lúc optimistic update đang được xác nhận.
    final cubit = context.read<SettingsCubit>();
    const themeOptions = <_PersonalSettingOption<String>>[
      _PersonalSettingOption(
        value: 'system',
        label: 'Theo hệ thống',
        description: 'Tự động theo thiết bị',
        icon: Icons.brightness_auto_rounded,
      ),
      _PersonalSettingOption(
        value: 'light',
        label: 'Sáng',
        description: 'Nền sáng, độ tương phản cao',
        icon: Icons.light_mode_rounded,
      ),
      _PersonalSettingOption(
        value: 'dark',
        label: 'Tối',
        description: 'Dịu mắt trong môi trường tối',
        icon: Icons.dark_mode_rounded,
      ),
    ];
    const mapOptions = <_PersonalSettingOption<AppMapType>>[
      _PersonalSettingOption(
        value: AppMapType.standard,
        label: 'Đường phố',
        description: 'Rõ đường và địa danh',
        icon: Icons.map_outlined,
      ),
      _PersonalSettingOption(
        value: AppMapType.satellite,
        label: 'Vệ tinh',
        description: 'Ảnh thực địa kèm nhãn',
        icon: Icons.satellite_alt_rounded,
      ),
    ];
    const speedOptions = <_PersonalSettingOption<SpeedUnit>>[
      _PersonalSettingOption(
        value: SpeedUnit.kmh,
        label: 'km/h',
        description: 'Kilômét mỗi giờ',
        icon: Icons.speed_rounded,
      ),
      _PersonalSettingOption(
        value: SpeedUnit.mps,
        label: 'm/s',
        description: 'Mét mỗi giây',
        icon: Icons.straighten_rounded,
      ),
    ];
    const journeyLabelOptions = <_PersonalSettingOption<JourneyNodeLabelMode>>[
      _PersonalSettingOption(
        value: JourneyNodeLabelMode.dateTimeOnly,
        label: 'Ngày giờ',
        description: 'Chỉ hiển thị dd/MM/yyyy · HH:mm:ss',
        icon: Icons.schedule_rounded,
      ),
      _PersonalSettingOption(
        value: JourneyNodeLabelMode.dateTimeAndAddress,
        label: 'Ngày giờ & địa chỉ',
        description: 'Hiển thị đầy đủ thời gian và địa chỉ',
        icon: Icons.location_on_outlined,
      ),
    ];
    final selectors = <Widget>[
      _PersonalSettingSelector<String>(
        key: const Key('theme-setting'),
        title: 'Giao diện',
        icon: Icons.palette_outlined,
        value: state.userSettings.theme,
        options: themeOptions,
        enabled: !state.personalSaving,
        onSelected: cubit.updateTheme,
      ),
      _PersonalSettingSelector<AppMapType>(
        key: const Key('map-type-setting'),
        title: 'Loại bản đồ',
        icon: Icons.map_outlined,
        value: state.userSettings.mapType,
        options: mapOptions,
        enabled: !state.personalSaving,
        onSelected: cubit.updateMapType,
      ),
      _PersonalSettingSelector<SpeedUnit>(
        key: const Key('speed-unit-setting'),
        title: 'Đơn vị tốc độ',
        icon: Icons.speed_rounded,
        value: state.userSettings.speedUnit,
        options: speedOptions,
        enabled: !state.personalSaving,
        onSelected: cubit.updateSpeedUnit,
      ),
      _PersonalSettingSelector<JourneyNodeLabelMode>(
        key: const Key('journey-node-label-setting'),
        title: 'Nhãn hành trình',
        icon: Icons.label_outline_rounded,
        value: state.userSettings.journeyNodeLabelMode,
        options: journeyLabelOptions,
        enabled: !state.personalSaving,
        onSelected: cubit.updateJourneyNodeLabelMode,
      ),
    ];

    return Column(
      key: const Key('personal-settings-content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PersonalSettingsSummary(saving: state.personalSaving),
        const SizedBox(height: 16),
        _SettingsCard(
          title: 'Tùy chọn hiển thị',
          icon: Icons.dashboard_customize_outlined,
          child: LayoutBuilder(
            key: const Key('personal-settings-grid'),
            builder: (context, constraints) {
              if (constraints.maxWidth < 680) {
                return Column(
                  children: [
                    for (var index = 0; index < selectors.length; index++) ...[
                      SizedBox(width: double.infinity, child: selectors[index]),
                      if (index != selectors.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                );
              }

              // Bốn selector cần hai cột ở chiều rộng trung bình để phần mô tả
              // không bị ép hẹp; màn hình rộng vẫn giữ một hàng như style cũ.
              if (constraints.maxWidth < 1120) {
                final itemWidth = (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: selectors
                      .map(
                        (selector) =>
                            SizedBox(width: itemWidth, child: selector),
                      )
                      .toList(growable: false),
                );
              }

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < selectors.length; index++) ...[
                      Expanded(child: selectors[index]),
                      if (index != selectors.length - 1)
                        const SizedBox(width: 12),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// Phần giới thiệu và tóm tắt giá trị hiện tại, giúp nhận biết cấu hình trước khi đổi.
class _PersonalSettingsSummary extends StatelessWidget {
  const _PersonalSettingsSummary({required this.saving});

  final bool saving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget introduction() => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.auto_awesome_outlined,
            color: colors.onPrimary,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trải nghiệm phù hợp với công việc',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Đồng bộ chủ đề, cách hiển thị bản đồ và đơn vị tốc độ cho tài khoản này.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return DecoratedBox(
      key: const Key('personal-settings-summary'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primaryContainer.withValues(alpha: 0.78),
            colors.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final status = _PersonalSaveStatus(saving: saving);
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  introduction(),
                  const SizedBox(height: 16),
                  Align(alignment: Alignment.centerLeft, child: status),
                  if (saving) ...[
                    const SizedBox(height: 14),
                    const LinearProgressIndicator(
                      minHeight: 3,
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                  ],
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: introduction()),
                    const SizedBox(width: 24),
                    status,
                  ],
                ),
                if (saving) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(
                    minHeight: 3,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

// Chỉ báo lưu gọn: spinner khi PATCH đang chạy, trạng thái bình thường khi hoàn tất.
class _PersonalSaveStatus extends StatelessWidget {
  const _PersonalSaveStatus({required this.saving});

  final bool saving;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = saving ? colors.primary : colors.onSurfaceVariant;
    return Container(
      key: const Key('personal-save-status'),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: saving
            ? colors.primaryContainer
            : colors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            saving ? Icons.sync_rounded : Icons.cloud_done_outlined,
            size: 17,
            color: foreground,
          ),
          const SizedBox(width: 7),
          Text(
            saving ? 'Đang lưu thay đổi' : 'Đã đồng bộ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// Dữ liệu trình bày của một lựa chọn generic: giá trị gửi, nhãn và mô tả cho người dùng.
class _PersonalSettingOption<T> {
  const _PersonalSettingOption({
    required this.value,
    required this.label,
    required this.description,
    required this.icon,
  });

  final T value;
  final String label;
  final String description;
  final IconData icon;
}

/// Thẻ lựa chọn vẫn dùng popup Material để bảo toàn điều hướng bàn phím,
/// focus, semantics và hành vi lưu hiện có.
// Bộ chọn dùng chung cho theme, loại bản đồ và đơn vị tốc độ; Wrap/Popup thích nghi
// chiều rộng và chỉ gọi callback với giá trị option đã khai báo.
class _PersonalSettingSelector<T> extends StatelessWidget {
  const _PersonalSettingSelector({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onSelected,
  });

  final String title;
  final IconData icon;
  final T value;
  final List<_PersonalSettingOption<T>> options;
  final bool enabled;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = options.firstWhere((option) => option.value == value);

    return PopupMenuButton<T>(
      // Popup trả đúng kiểu generic T nên callback không cần ép kiểu chuỗi.
      enabled: enabled,
      tooltip: 'Chọn $title',
      constraints: const BoxConstraints(minWidth: 250, maxWidth: 340),
      onSelected: onSelected,
      itemBuilder: (context) => options
          .map((option) {
            final isSelected = option.value == value;
            return PopupMenuItem<T>(
              value: option.value,
              height: 48,
              padding: EdgeInsets.zero,
              child: AppMenuItem(
                icon: option.icon,
                label: option.label,
                selected: isSelected,
                touchTarget: true,
                trailing: isSelected
                    ? const Icon(Icons.check_rounded)
                    : const SizedBox(width: 18),
              ),
            );
          })
          .toList(growable: false),
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Material(
          color: colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: colors.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.expand_more_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  selected.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  selected.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Trang Thông tin phần mềm kết hợp metadata package tại máy và thông tin kết nối từ AppConfig.
class _SoftwareInformationCard extends StatefulWidget {
  const _SoftwareInformationCard();

  @override
  State<_SoftwareInformationCard> createState() =>
      _SoftwareInformationCardState();
}

class _SoftwareInformationCardState extends State<_SoftwareInformationCard> {
  // Future được tạo một lần để PackageInfo không bị đọc lại sau mỗi lần rebuild theme.
  // Metadata chỉ cần đọc một lần trong vòng đời của trang. Dữ liệu lấy từ gói
  // ứng dụng đã build nên luôn đồng bộ với version trong pubspec.yaml.
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    // FutureBuilder chỉ điều khiển các trường phiên bản/tên gói; cấu hình server được
    // đọc trực tiếp từ AppConfig vì đã cố định tại thời điểm build.
    return FutureBuilder<PackageInfo>(
      future: _packageInfo,
      builder: (context, snapshot) {
        final packageInfo = snapshot.data;
        final version = _metadataValue(
          packageInfo?.version,
          snapshot.connectionState,
        );
        final entries = <_SoftwareInfoEntry>[
          const _SoftwareInfoEntry(
            keyName: 'software-name-tile',
            icon: Icons.apps_rounded,
            label: 'Tên phần mềm',
            value: 'V Monitor',
          ),
          _SoftwareInfoEntry(
            keyName: 'software-version-tile',
            valueKey: const Key('software-version-value'),
            icon: Icons.new_releases_outlined,
            label: 'Phiên bản',
            value: version,
          ),
          _SoftwareInfoEntry(
            keyName: 'software-build-tile',
            valueKey: const Key('software-build-value'),
            icon: Icons.build_circle_outlined,
            label: 'Bản dựng',
            value: _metadataValue(
              packageInfo?.buildNumber,
              snapshot.connectionState,
            ),
          ),
          _SoftwareInfoEntry(
            keyName: 'software-package-tile',
            valueKey: const Key('software-package-value'),
            icon: Icons.fingerprint_rounded,
            label: 'Mã ứng dụng',
            value: _metadataValue(
              packageInfo?.packageName,
              snapshot.connectionState,
            ),
          ),
        ];

        return Column(
          key: const Key('software-information-content'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SoftwareBrandPanel(version: version),
            const SizedBox(height: 16),
            KeyedSubtree(
              key: const Key('software-release-panel'),
              child: _SettingsCard(
                title: 'Thông tin phát hành',
                icon: Icons.info_outline_rounded,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 12.0;
                    final columns = constraints.maxWidth >= 600 ? 2 : 1;
                    final tileWidth =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                        columns;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (final entry in entries)
                          SizedBox(
                            width: tileWidth,
                            child: _SoftwareInfoTile(entry: entry),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _metadataValue(String? value, ConnectionState connectionState) {
    // Trong lúc plugin chưa trả kết quả, hiển thị trạng thái thay vì ký tự placeholder.
    if (connectionState == ConnectionState.waiting) return 'Đang tải…';
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? 'Không xác định' : normalized;
  }
}

// Khối nhận diện phần mềm gồm logo, tên và mô tả; bố cục đổi hàng/cột theo chiều rộng.
class _SoftwareBrandPanel extends StatelessWidget {
  const _SoftwareBrandPanel({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final logo = Container(
      key: const Key('software-app-icon'),
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.14),
            blurRadius: 20,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      // Ảnh thương hiệu có khoảng trắng bao quanh; phóng trong vùng cắt giúp
      // biểu tượng rõ ràng mà không sửa file ảnh gốc.
      child: Transform.scale(
        scale: 1.85,
        child: Image.asset(
          'assets/branding/v_monitor_logo.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          semanticLabel: 'Biểu tượng V Monitor',
        ),
      ),
    );

    Widget description({required TextAlign textAlign}) => Column(
      crossAxisAlignment: textAlign == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          'V Monitor',
          textAlign: textAlign,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Phần mềm giám sát thiết bị nội bộ',
          textAlign: textAlign,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: textAlign == TextAlign.center
              ? WrapAlignment.center
              : WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          children: [
            _SoftwareBadge(
              icon: Icons.verified_outlined,
              label: 'Phiên bản $version',
              emphasized: true,
            ),
            const _SoftwareBadge(
              icon: Icons.shield_outlined,
              label: 'Hệ thống nội bộ',
            ),
          ],
        ),
      ],
    );

    return DecoratedBox(
      key: const Key('software-brand-panel'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primaryContainer.withValues(alpha: 0.74),
            colors.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 560) {
              return Column(
                children: [
                  logo,
                  const SizedBox(height: 18),
                  description(textAlign: TextAlign.center),
                ],
              );
            }
            return Row(
              children: [
                logo,
                const SizedBox(width: 22),
                Expanded(child: description(textAlign: TextAlign.start)),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Badge metadata ngắn dùng trong phần thương hiệu, màu hoàn toàn lấy từ theme.
class _SoftwareBadge extends StatelessWidget {
  const _SoftwareBadge({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = emphasized ? colors.primary : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: emphasized
            ? colors.primaryContainer
            : colors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Model trình bày của một dòng thông tin kỹ thuật, không chứa logic kết nối.
class _SoftwareInfoEntry {
  const _SoftwareInfoEntry({
    required this.keyName,
    this.valueKey,
    required this.icon,
    required this.label,
    required this.value,
  });

  final String keyName;
  final Key? valueKey;
  final IconData icon;
  final String label;
  final String value;
}

// Một dòng label/value có icon; value được cho phép chọn/copy và tự xuống dòng.
class _SoftwareInfoTile extends StatelessWidget {
  const _SoftwareInfoTile({required this.entry});

  final _SoftwareInfoEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      key: Key(entry.keyName),
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.76),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                entry.icon,
                size: 20,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    entry.value,
                    key: entry.valueKey,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
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

// Trang Tài khoản và bảo mật lấy UserModel đã xác thực từ AuthState, hiển thị hồ sơ
// và chuyển sửa hồ sơ/đổi mật khẩu tới AuthCubit hoặc SettingsCubit phù hợp.
class _AccountSettingsCard extends StatelessWidget {
  const _AccountSettingsCard({
    required this.user,
    required this.hasAdminAccess,
    required this.operationInProgress,
  });

  final UserModel? user;
  final bool hasAdminAccess;
  final bool operationInProgress;

  Future<void> _editCurrentAccount(BuildContext context) async {
    // Mở form ở profileOnly để tài khoản không tự đổi role/is_active. Sau PATCH,
    // `/auth/me` được tải lại để giao diện dùng dữ liệu backend đã xác nhận.
    final currentUser = user;
    // Hiện tại endpoint sửa hồ sơ nằm trong router ADMIN nên user thường không mở form.
    if (!hasAdminAccess || currentUser == null) return;
    // profileOnly ẩn role/is_active nhưng vẫn dùng dialog quản trị đã kiểm thử.
    final saved = await showUserEditorDialog(
      context,
      user: currentUser,
      profileOnly: true,
    );
    // Chỉ refresh AuthState khi dialog báo lưu thành công và context còn mounted.
    if (saved != true || !context.mounted) return;

    // Đọc lại `/auth/me` để tên và email mới đồng bộ ở thẻ tài khoản, menu
    // người dùng và mọi màn hình khác đang theo dõi AuthState.
    final error = await context.read<AuthCubit>().refreshCurrentUser();
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // roleLabel lấy từ UserModel thật; null hiển thị trạng thái chưa xác định.
    final roleLabel = user == null
        ? 'Không xác định'
        : user!.isAdmin
        ? 'Quản trị viên'
        : 'Thành viên';

    // Trang tài khoản gồm card hồ sơ và card hành động bảo mật xếp dọc.
    return Column(
      key: const Key('account-settings-content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsCard(
          title: 'Thông tin tài khoản',
          icon: Icons.manage_accounts_outlined,
          // Nút không được tạo cho tài khoản thành viên; backend vẫn kiểm tra
          // require_admin khi API cập nhật được gọi.
          trailing: hasAdminAccess && user != null
              ? TextButton.icon(
                  key: const Key('edit-current-account'),
                  onPressed: operationInProgress
                      ? null
                      : () => _editCurrentAccount(context),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Sửa'),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AccountIdentitySummary(user: user, roleLabel: roleLabel),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  // 680 px dùng 3 cột; 460–679 dùng 2; nhỏ hơn dùng 1 để giữ giá trị đọc được.
                  final columns = constraints.maxWidth >= 680
                      ? 3
                      : constraints.maxWidth >= 460
                      ? 2
                      : 1;
                  // Trừ tổng khoảng cách trước khi chia để Wrap không vượt maxWidth.
                  final spacing = 12.0 * (columns - 1);
                  final itemWidth = (constraints.maxWidth - spacing) / columns;
                  final fields = [
                    _AccountDetailTile(
                      key: const Key('account-username-detail'),
                      icon: Icons.alternate_email_rounded,
                      label: 'Tên đăng nhập',
                      value: user?.username ?? '—',
                    ),
                    _AccountDetailTile(
                      key: const Key('account-email-detail'),
                      icon: Icons.mail_outline_rounded,
                      label: 'Email',
                      value: user?.email?.trim().isNotEmpty == true
                          ? user!.email!
                          : 'Chưa thiết lập',
                    ),
                    _AccountDetailTile(
                      key: const Key('account-role-detail'),
                      icon: Icons.verified_user_outlined,
                      label: 'Quyền truy cập',
                      value: roleLabel,
                    ),
                  ];
                  // Wrap cho phép hàng cuối có ít item mà không kéo giãn nội dung sai tỷ lệ.
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final field in fields)
                        SizedBox(width: itemWidth, child: field),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsCard(
          title: 'Bảo mật & phiên đăng nhập',
          icon: Icons.shield_outlined,
          child: Material(
            key: const Key('account-security-panel'),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _AccountSecurityAction(
                  icon: Icons.password_rounded,
                  title: 'Mật khẩu',
                  description:
                      'Đổi mật khẩu và đăng nhập lại để bảo vệ tài khoản trên các thiết bị.',
                  action: OutlinedButton.icon(
                    key: const Key('open-change-password'),
                    onPressed: () => _showChangePasswordDialog(context),
                    icon: const Icon(Icons.password_rounded, size: 18),
                    label: const Text('Đổi mật khẩu'),
                  ),
                ),
                const Divider(height: 1, indent: 64),
                _AccountSecurityAction(
                  icon: Icons.logout_rounded,
                  title: 'Phiên hiện tại',
                  description:
                      'Kết thúc phiên làm việc an toàn trên thiết bị đang sử dụng.',
                  action: FilledButton.tonalIcon(
                    key: const Key('logout-from-settings'),
                    onPressed: () => context.read<AuthCubit>().logout(),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Đăng xuất'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Khối nhận diện chính của tài khoản: avatar, họ tên, username và badge vai trò.
class _AccountIdentitySummary extends StatelessWidget {
  const _AccountIdentitySummary({required this.user, required this.roleLabel});

  final UserModel? user;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Tên hiển thị ưu tiên fullName có nội dung, fallback username rồi nhãn chung.
    final displayName = user?.fullName.trim().isNotEmpty == true
        ? user!.fullName.trim()
        : user?.username ?? 'Tài khoản';
    final username = user?.username.trim() ?? '';
    // Avatar chỉ dùng chữ đầu đã viết hoa; fallback `?` khi không có định danh.
    final initial = displayName.trim().characters.isEmpty
        ? '?'
        : displayName.trim().characters.first.toUpperCase();

    return Container(
      key: const Key('account-profile-summary'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primaryContainer.withValues(alpha: 0.62),
            colors.primaryContainer.withValues(alpha: 0.24),
          ],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            child: Text(
              initial,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colors.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // Username chỉ dựng khi có nội dung để không tạo dòng `@` rỗng.
                if (username.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    roleLabel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
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

// Dòng thông tin hồ sơ có icon/nhãn/giá trị, tự co giãn để email dài không overflow.
class _AccountDetailTile extends StatelessWidget {
  const _AccountDetailTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.secondaryContainer.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: colors.onSecondaryContainer),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Nút hành động bảo mật dạng card; callback được chuyển lên AuthCubit/dialog bên ngoài.
class _AccountSecurityAction extends StatelessWidget {
  const _AccountSecurityAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final information = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: colors.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
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
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Mobile đặt nút dưới mô tả với toàn chiều rộng; desktop đặt nút bên phải.
        final compact = constraints.maxWidth < 560;
        return Padding(
          padding: const EdgeInsets.all(14),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [information, const SizedBox(height: 12), action],
                )
              : Row(
                  children: [
                    Expanded(child: information),
                    const SizedBox(width: 18),
                    action,
                  ],
                ),
        );
      },
    );
  }
}

// Vỏ card thống nhất padding, tiêu đề và màu bề mặt cho các section cài đặt.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              // Hàng tiêu đề giữ icon/title co giãn và trailing tùy chọn ở cuối.
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            // Nội dung section luôn bắt đầu dưới tiêu đề với khoảng cách thống nhất.
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

// Banner lỗi lấy message đã được Cubit chuẩn hóa, không hiển thị raw stack/network exception.
class _LoadErrorBanner extends StatelessWidget {
  const _LoadErrorBanner({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message ?? 'Không thể tải đầy đủ cài đặt.',
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: () => context.read<SettingsCubit>().initialize(),
              child: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showChangePasswordDialog(BuildContext context) {
  // Dialog nhận AuthCubit hiện tại để đổi mật khẩu và tự xóa phiên sau khi backend commit.
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider.value(
      value: context.read<AuthCubit>(),
      child: const ChangePasswordDialog(),
    ),
  );
}
