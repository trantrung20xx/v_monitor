// Form ba ngưỡng theo dõi toàn hệ thống. Controller chỉ giữ dữ liệu nhập và validation;
// SettingsCubit gửi PATCH, chống lưu trùng và đồng bộ response thật.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../data/models/system_settings_model.dart';
import '../settings_cubit.dart';

// Form cấu hình ngưỡng vận hành dùng chung toàn hệ thống. Giá trị ban đầu đến từ
// SystemSettingsModel; chỉ ADMIN lưu được qua SettingsCubit/backend.
class TrackingSettingsCard extends StatefulWidget {
  const TrackingSettingsCard({
    super.key,
    required this.settings,
    required this.saving,
  });

  final SystemSettingsModel settings;
  final bool saving;

  @override
  State<TrackingSettingsCard> createState() => _TrackingSettingsCardState();
}

class _TrackingSettingsCardState extends State<TrackingSettingsCard> {
  // Controller giữ chuỗi đang nhập; `_dirty` ngăn dữ liệu realtime mới ghi đè form
  // khi quản trị viên chưa lưu thay đổi hiện tại.
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _offlineController;
  late final TextEditingController _movementController;
  late final TextEditingController _gapController;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    // Controller được tạo rỗng rồi đồng bộ cùng một hàm để init/update dùng chung quy tắc.
    _offlineController = TextEditingController();
    _movementController = TextEditingController();
    _gapController = TextEditingController();
    _synchronizeControllers(widget.settings);
  }

  @override
  void didUpdateWidget(covariant TrackingSettingsCard oldWidget) {
    // Chỉ đồng bộ response server mới khi form chưa bị chỉnh; tránh mất nội dung đang nhập.
    super.didUpdateWidget(oldWidget);
    // So sánh model giúp bỏ lần rebuild chỉ thay cờ saving mà giá trị cấu hình không đổi.
    // Không ghi đè dữ liệu Admin đang nhập khi một sự kiện WebSocket đến giữa chừng.
    if (!_dirty && oldWidget.settings != widget.settings) {
      _synchronizeControllers(widget.settings);
    }
  }

  @override
  void dispose() {
    _offlineController.dispose();
    _movementController.dispose();
    _gapController.dispose();
    super.dispose();
  }

  void _synchronizeControllers(SystemSettingsModel settings) {
    // Chuyển ba giá trị số từ model thành chuỗi hiển thị, không đổi đơn vị nghiệp vụ.
    // Controller chỉ phục vụ form; SystemSettingsModel vẫn là nguồn đã xác nhận.
    _offlineController.text = settings.offlineTimeoutSeconds.toString();
    _movementController.text = settings.movementThresholdMps.toString();
    _gapController.text = settings.defaultGapThresholdSeconds.toString();
  }

  Future<void> _save() async {
    // Form parse/validate trước để báo lỗi gần trường nhập; Cubit gửi cả snapshot đã
    // chuẩn hóa và chỉ cập nhật runtime toàn ứng dụng sau khi backend xác nhận.
    // Guard khóa double-submit và dừng khi bất kỳ validator nào báo lỗi.
    if (widget.saving || !(_formKey.currentState?.validate() ?? false)) return;
    // Parse sau validation nên các phép int.parse/double.parse đã có đầu vào hợp lệ.
    final value = SystemSettingsModel(
      offlineTimeoutSeconds: int.parse(_offlineController.text.trim()),
      movementThresholdMps: double.parse(
        _movementController.text.trim().replaceFirst(',', '.'),
      ),
      defaultGapThresholdSeconds: int.parse(_gapController.text.trim()),
    );
    // Cubit trả null khi backend đã commit; chuỗi khác null là lỗi nghiệp vụ.
    final error = await context.read<SettingsCubit>().saveSystemSettings(value);
    if (!mounted || error != null) return;
    // Thành công đưa form về trạng thái đồng bộ và hiển thị phản hồi ngắn.
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Đã lưu cấu hình theo dõi thiết bị.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Bố cục gồm header giải thích phạm vi, ba panel ngưỡng và vùng lưu cố định ở
    // cuối; Wrap/Column cho phép tự xuống hàng trên màn hình hẹp.
    // Card là ranh giới visual của toàn form và nhận màu trực tiếp từ ThemeData.
    return Card(
      key: const Key('tracking-settings-content'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          onChanged: () {
            // Lần thay đổi đầu tiên bật dirty; ký tự tiếp theo không setState lặp vô ích.
            if (!_dirty) setState(() => _dirty = true);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TrackingSettingsHeader(),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  // Từ 760 px ba panel nằm cùng hàng; thấp hơn xếp dọc toàn chiều rộng.
                  final isWide = constraints.maxWidth >= 760;
                  // Ba panel dùng cùng component nhưng giữ mô tả, đơn vị và biên riêng.
                  final fields = [
                    _TrackingSettingPanel(
                      key: const Key('offline-setting-panel'),
                      icon: Icons.cloud_off_outlined,
                      title: 'Thời gian xác định ngoại tuyến',
                      description:
                          'Không nhận dữ liệu trong khoảng này thì thiết bị được xem là ngoại tuyến.',
                      rangeLabel: 'Phạm vi: 30–86400 giây',
                      field: _IntegerSettingField(
                        key: const Key('offline-timeout-field'),
                        controller: _offlineController,
                        label: 'Giá trị',
                        suffix: 'giây',
                        minimum: 30,
                        maximum: 86400,
                      ),
                    ),
                    _TrackingSettingPanel(
                      key: const Key('movement-setting-panel'),
                      icon: Icons.speed_rounded,
                      title: 'Ngưỡng xác định di chuyển',
                      description:
                          'Tốc độ từ ngưỡng này trở lên được xem là thiết bị đang di chuyển.',
                      rangeLabel: 'Phạm vi: 0–10 m/s',
                      field: _DoubleSettingField(
                        key: const Key('movement-threshold-field'),
                        controller: _movementController,
                        label: 'Giá trị',
                        suffix: 'm/s',
                        minimum: 0,
                        maximum: 10,
                      ),
                    ),
                    _TrackingSettingPanel(
                      key: const Key('journey-gap-setting-panel'),
                      icon: Icons.route_outlined,
                      title: 'Khoảng ngắt lộ trình mặc định',
                      description:
                          'Khoảng gián đoạn dùng để nhận biết và tách các đoạn lộ trình.',
                      rangeLabel: 'Phạm vi: 60–3600 giây',
                      field: _IntegerSettingField(
                        key: const Key('journey-gap-field'),
                        controller: _gapController,
                        label: 'Giá trị',
                        suffix: 'giây',
                        minimum: 60,
                        maximum: 3600,
                      ),
                    ),
                  ];
                  // Nhánh hẹp thêm khoảng cách dọc giữa panel nhưng không thêm sau panel cuối.
                  if (!isWide) {
                    return Column(
                      children: [
                        for (var index = 0; index < fields.length; index++) ...[
                          fields[index],
                          if (index < fields.length - 1)
                            const SizedBox(height: 14),
                        ],
                      ],
                    );
                  }
                  // IntrinsicHeight giúp ba Expanded panel có chiều cao bằng panel nội dung dài nhất.
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < fields.length; index++) ...[
                          Expanded(child: fields[index]),
                          if (index < fields.length - 1)
                            const SizedBox(width: 14),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // Save panel nhận dirty/saving để mô tả đúng trạng thái form và khóa nút.
              _TrackingSavePanel(
                dirty: _dirty,
                saving: widget.saving,
                onSave: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Header giải thích đây là cấu hình vận hành toàn hệ thống và được áp dụng tức thời.
class _TrackingSettingsHeader extends StatelessWidget {
  const _TrackingSettingsHeader();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.sensors_rounded, color: colors.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Theo dõi thiết bị',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Thiết lập cách hệ thống nhận biết trạng thái, chuyển động và các đoạn lộ trình.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    // Badge áp dụng ngay đổi vị trí theo chiều rộng nhưng luôn nằm trong cùng header.
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        // Mobile xếp badge dưới heading để phần mô tả không bị ép ngang.
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: 12),
              const _ImmediateApplyBadge(),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 18),
            const _ImmediateApplyBadge(),
          ],
        );
      },
    );
  }
}

// Badge cảnh báo phạm vi áp dụng, dùng màu warning từ theme thay vì mã màu cố định.
class _ImmediateApplyBadge extends StatelessWidget {
  const _ImmediateApplyBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 16, color: colors.onTertiaryContainer),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'Áp dụng ngay sau khi lưu',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Panel của một ngưỡng: icon, tên dễ hiểu, mô tả nghiệp vụ và trường nhập số.
class _TrackingSettingPanel extends StatelessWidget {
  const _TrackingSettingPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.rangeLabel,
    required this.field,
  });

  final IconData icon;
  final String title;
  final String description;
  final String rangeLabel;
  final Widget field;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Panel luôn xếp icon/title, mô tả, field và nhãn phạm vi theo thứ tự đọc.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: colors.onSecondaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          field,
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  rangeLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Vùng cuối form hiển thị trạng thái chưa lưu và nút áp dụng; khóa nút khi đang gửi.
class _TrackingSavePanel extends StatelessWidget {
  const _TrackingSavePanel({
    required this.dirty,
    required this.saving,
    required this.onSave,
  });

  final bool dirty;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Ba chuỗi cùng dựa trên saving/dirty để tiêu đề và mô tả không mâu thuẫn.
    final statusTitle = saving
        ? 'Đang áp dụng cấu hình...'
        : dirty
        ? 'Có thay đổi chưa lưu'
        : 'Cấu hình đã đồng bộ';
    final statusDescription = saving
        ? 'Hệ thống đang đồng bộ các giá trị mới đến các màn hình đang mở.'
        : dirty
        ? 'Kiểm tra các giá trị trước khi áp dụng cho hệ thống.'
        : 'Các giá trị đang hiển thị là cấu hình hiện tại.';
    // Icon sử dụng cùng máy trạng thái ba nhánh với phần chữ.
    final statusIcon = saving
        ? Icons.sync_rounded
        : dirty
        ? Icons.pending_actions_outlined
        : Icons.check_circle_outline_rounded;

    // Pending chỉ đúng khi đã sửa và request chưa chạy; quyết định palette cảnh báo.
    final hasPendingChanges = dirty && !saving;
    final status = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: hasPendingChanges
                ? colors.tertiaryContainer
                : colors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            statusIcon,
            size: 20,
            color: hasPendingChanges
                ? colors.onTertiaryContainer
                : colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusTitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                statusDescription,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );

    // Nút bị disable khi saving; dirty=false vẫn cho phép lưu lại snapshot hiện tại như hành vi cũ.
    final saveButton = FilledButton.icon(
      key: const Key('save-system-settings'),
      onPressed: saving ? null : onSave,
      icon: saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppPalette.onAccent,
              ),
            )
          : const Icon(Icons.save_outlined),
      label: Text(saving ? 'Đang lưu...' : 'Lưu thay đổi'),
    );

    return Container(
      key: const Key('tracking-save-panel'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Dưới 600 px nút chuyển xuống hàng để status text có đủ chiều rộng.
          final compact = constraints.maxWidth < 600;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [status, const SizedBox(height: 14), saveButton],
            );
          }
          return Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: 20),
              saveButton,
            ],
          );
        },
      ),
    );
  }
}

// Trường số nguyên dùng cho timeout/gap theo giây, tái sử dụng decoration thống nhất.
class _IntegerSettingField extends StatelessWidget {
  const _IntegerSettingField({
    super.key,
    required this.controller,
    required this.label,
    required this.suffix,
    required this.minimum,
    required this.maximum,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final int minimum;
  final int maximum;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      validator: (rawValue) {
        // tryParse xử lý ô rỗng/ký tự lạ mà không ném exception trong build form.
        final value = int.tryParse(rawValue?.trim() ?? '');
        // Chỉ số nguyên được chấp nhận cho các khoảng thời gian theo giây.
        if (value == null) return 'Phải là số nguyên.';
        // Biên được truyền riêng cho từng field và khớp validation backend.
        if (value < minimum || value > maximum) {
          return 'Từ $minimum đến $maximum.';
        }
        return null;
      },
    );
  }
}

// Trường số thực dùng cho ngưỡng tốc độ m/s; validator do form cha cung cấp.
class _DoubleSettingField extends StatelessWidget {
  const _DoubleSettingField({
    super.key,
    required this.controller,
    required this.label,
    required this.suffix,
    required this.minimum,
    required this.maximum,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final double minimum;
  final double maximum;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      validator: (rawValue) {
        // Chấp nhận dấu phẩy thập phân quen thuộc rồi chuẩn hóa thành dấu chấm để parse.
        final value = double.tryParse(
          (rawValue ?? '').trim().replaceFirst(',', '.'),
        );
        // isFinite loại NaN/Infinity dù double.tryParse có thể đọc được chuỗi đặc biệt.
        if (value == null || !value.isFinite) return 'Phải là một số hợp lệ.';
        // Biên tốc độ bảo vệ logic trạng thái khỏi một ngưỡng không thực tế.
        if (value < minimum || value > maximum) {
          return 'Từ $minimum đến $maximum.';
        }
        return null;
      },
    );
  }
}
